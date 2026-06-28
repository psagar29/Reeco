/**
 * Enrollment script.
 *
 * Reads demo-data/people.sample.json, computes a face embedding per person, and
 * writes demo-data/embeddings.generated.json (a personId -> 512-floats map).
 *
 *   - When the CV service is reachable + ready AND the enrollment image exists,
 *     it calls Person A's POST /embed for a real ArcFace embedding.
 *   - Otherwise it falls back to a deterministic mock embedding (per person) so
 *     the demo still matches offline. The fallback reason is reported per person.
 *
 * Every embedding (real or mock) is validated before it is written: it must be a
 * 512-length array of finite numbers, and real CV embeddings must be ~L2-unit.
 *
 * The output file is git-ignored — it can carry real-photo-derived embeddings.
 *
 * Run with:  npm run enroll
 * Or point at a running CV service:  CV_SERVICE_URL=http://127.0.0.1:8000 npm run enroll
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { getEmbedding } from "../convex/lib/cv.js";
import { deterministicEmbedding } from "../convex/lib/mockEmbeddings.js";
import { getCvServiceUrl } from "../convex/lib/config.js";
import { EMBEDDING_DIM } from "../convex/lib/similarity.js";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const backendDir = resolve(scriptsDir, "..");
const repoRoot = resolve(backendDir, "..");

/** Real CV embeddings should be L2-normalized; tolerate small float drift. */
const NORM_TOLERANCE = 0.02;

/** Minimal .env.local loader (no dependency). Does not overwrite real env. */
function loadEnvLocal(): void {
  const envPath = resolve(backendDir, ".env.local");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/i);
    if (!m) continue;
    const key = m[1];
    let val = m[2];
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = val;
  }
}

type SamplePerson = {
  id: string;
  name: string;
  enrollmentImagePath?: string;
};

const MIME_BY_EXT: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
};

// ---------------------------------------------------------------------------
// CV health
// ---------------------------------------------------------------------------

type CvHealth = {
  /** Did the /health request complete (any HTTP response)? */
  reachable: boolean;
  /** Has the model finished loading? Only `ready` services get real embeds. */
  ready: boolean;
  model: string | null;
  detSize: number | null;
  minDetScore: number | null;
  error: string | null;
};

/** Probe GET {url}/health once, before enrolling. Never throws. */
async function checkCvHealth(url: string, timeoutMs = 5000): Promise<CvHealth> {
  const base = url.replace(/\/+$/, "");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${base}/health`, { signal: controller.signal });
    if (!res.ok) {
      return {
        reachable: true,
        ready: false,
        model: null,
        detSize: null,
        minDetScore: null,
        error: `HTTP ${res.status}`,
      };
    }
    const data = (await res.json()) as {
      ok?: boolean;
      model?: string;
      ready?: boolean;
      error?: string;
      detSize?: number;
      minDetScore?: number;
    };
    return {
      reachable: true,
      ready: Boolean(data.ready),
      model: data.model ?? null,
      detSize: typeof data.detSize === "number" ? data.detSize : null,
      minDetScore: typeof data.minDetScore === "number" ? data.minDetScore : null,
      error: data.error ?? null,
    };
  } catch (err) {
    return {
      reachable: false,
      ready: false,
      model: null,
      detSize: null,
      minDetScore: null,
      error: err instanceof Error ? err.message : String(err),
    };
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// Embedding validation helpers
// ---------------------------------------------------------------------------

/** True if `value` is an array whose every element is a finite number. */
function isFiniteEmbedding(value: unknown): value is number[] {
  return (
    Array.isArray(value) &&
    value.length > 0 &&
    value.every((x) => typeof x === "number" && Number.isFinite(x))
  );
}

/** Euclidean (L2) norm of a numeric vector. */
function embeddingNorm(values: number[]): number {
  let sum = 0;
  for (const x of values) sum += x * x;
  return Math.sqrt(sum);
}

/**
 * Validate a final embedding before it is written. Throws on a structural
 * problem (wrong length / non-finite values). For real CV output, also warns
 * (does not throw) if the vector is not roughly L2-normalized.
 */
function validateEmbedding(personId: string, values: unknown, source: string): asserts values is number[] {
  if (!isFiniteEmbedding(values)) {
    const detail = Array.isArray(values) ? `length ${values.length}` : typeof values;
    throw new Error(
      `Invalid embedding for ${personId} (source=${source}): expected ${EMBEDDING_DIM} finite numbers, got ${detail}`,
    );
  }
  if (values.length !== EMBEDDING_DIM) {
    throw new Error(
      `Invalid embedding for ${personId} (source=${source}): expected length ${EMBEDDING_DIM}, got ${values.length}`,
    );
  }
  if (source === "cv") {
    const norm = embeddingNorm(values);
    if (Math.abs(norm - 1) >= NORM_TOLERANCE) {
      console.warn(
        `  WARN ${personId}: real CV embedding L2 norm ${norm.toFixed(4)} is not ~1.0 ` +
          `(expected normalized output; matching re-normalizes defensively).`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Enrollment
// ---------------------------------------------------------------------------

type EnrollReport = {
  id: string;
  source: string;
  dim: number;
  norm: number;
};

async function main(): Promise<void> {
  loadEnvLocal();
  const cvServiceUrl = getCvServiceUrl(process.env);

  const samplePath = resolve(repoRoot, "demo-data", "people.sample.json");
  const people = JSON.parse(readFileSync(samplePath, "utf8")) as SamplePerson[];

  console.log(`Enrolling ${people.length} people.`);

  // --- Pre-flight CV health check -----------------------------------------
  let cvReady = false;
  if (!cvServiceUrl) {
    console.log("CV_SERVICE_URL is unset -> every embedding will be a deterministic mock.\n");
  } else {
    console.log(`CV_SERVICE_URL = ${cvServiceUrl}`);
    const health = await checkCvHealth(cvServiceUrl);
    if (!health.reachable) {
      console.log(`  /health: UNREACHABLE (${health.error}) -> mock fallback for everyone.`);
    } else if (!health.ready) {
      console.log(
        `  /health: reachable but NOT READY ` +
          `(model=${health.model ?? "?"}, error=${health.error ?? "still loading"}) -> mock fallback.`,
      );
    } else {
      const extras = [
        health.detSize != null ? `detSize=${health.detSize}` : null,
        health.minDetScore != null ? `minDetScore=${health.minDetScore}` : null,
      ]
        .filter(Boolean)
        .join(" ");
      console.log(`  /health: ready  model=${health.model ?? "?"}${extras ? "  " + extras : ""}`);
      console.log(`  (enrollment and live matching must use the SAME model: ${health.model ?? "?"})`);
    }
    cvReady = health.reachable && health.ready;
    console.log("");
  }

  const embeddings: Record<string, number[]> = {};
  const report: EnrollReport[] = [];

  for (const person of people) {
    const imagePath = person.enrollmentImagePath
      ? resolve(repoRoot, person.enrollmentImagePath)
      : null;
    const haveImage = imagePath !== null && existsSync(imagePath);

    let source: string;
    let embedding: number[];

    if (!haveImage) {
      source = "mock (image missing)";
      embedding = deterministicEmbedding(person.id);
    } else if (!cvReady) {
      source = "mock (CV unavailable)";
      embedding = deterministicEmbedding(person.id);
    } else {
      const ext = imagePath!.split(".").pop()?.toLowerCase() ?? "jpg";
      const mime = MIME_BY_EXT[ext] ?? "image/jpeg";
      const base64 = readFileSync(imagePath!).toString("base64");
      const outcome = await getEmbedding({
        imageBase64: base64,
        imageMimeType: mime,
        requestId: person.id,
        cvServiceUrl,
      });

      if (outcome.source === "cv" && outcome.faceDetected === false) {
        source = "mock (CV found no face)";
        embedding = deterministicEmbedding(person.id);
      } else if (outcome.source === "cv" && isFiniteEmbedding(outcome.embedding)) {
        source = "cv";
        embedding = outcome.embedding;
      } else {
        // cv.ts already degraded to a mock (timeout / network / malformed body).
        source = "mock (CV unavailable)";
        embedding = deterministicEmbedding(person.id);
      }
    }

    // Validate the final embedding before it can be written.
    validateEmbedding(person.id, embedding, source);

    embeddings[person.id] = embedding;
    const norm = embeddingNorm(embedding);
    report.push({ id: person.id, source, dim: embedding.length, norm });
    console.log(
      `  ${person.id.padEnd(20)} ${source.padEnd(24)} dim=${embedding.length} norm=${norm.toFixed(3)}`,
    );
  }

  const outPath = resolve(repoRoot, "demo-data", "embeddings.generated.json");
  writeFileSync(outPath, JSON.stringify(embeddings, null, 2));

  // --- Summary ------------------------------------------------------------
  const realCount = report.filter((r) => r.source === "cv").length;
  const mockCount = people.length - realCount;
  const outRel = relative(repoRoot, outPath);

  console.log("\n" + "─".repeat(60));
  console.log(`People enrolled : ${people.length}`);
  console.log(`Real CV embeds  : ${realCount}`);
  console.log(`Mock fallbacks  : ${mockCount}`);
  console.log(`Output written  : ${outRel}`);
  console.log("─".repeat(60));
  console.log("\nNext: load these embeddings into a running Convex deployment.");
  console.log("  cd backend");
  console.log('  # macOS / Linux / Git Bash:');
  console.log('  npx convex run seed:run "{\\"embeddings\\": $(cat ../demo-data/embeddings.generated.json)}"');
  console.log("  # PowerShell:");
  console.log('  #   npx convex run seed:run ("{\\"embeddings\\": $(Get-Content ../demo-data/embeddings.generated.json -Raw)}")');
  console.log("\nOr seed with deterministic mock embeddings only:");
  console.log("  npx convex run seed:run");
}

main().catch((err) => {
  console.error("Enrollment failed:", err);
  process.exit(1);
});
