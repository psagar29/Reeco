/**
 * Enrollment script.
 *
 * Reads demo-data/people.sample.json, computes a face embedding per person, and
 * writes demo-data/embeddings.generated.json (a personId -> 512-floats map).
 *
 *   - When CV_SERVICE_URL is reachable AND the enrollment image exists, it calls
 *     Person A's POST /embed for a real embedding.
 *   - Otherwise it falls back to a deterministic mock embedding so the demo
 *     still matches offline.
 *
 * Load the result into a running deployment with:
 *   npx convex run seed:run "$(node -e "process.stdout.write(JSON.stringify({embeddings: require('./demo-data/embeddings.generated.json')}))")"
 * (the README shows a copy-paste version for Windows PowerShell too).
 *
 * Run with:  npm run enroll
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { getEmbedding } from "../convex/lib/cv.js";
import { deterministicEmbedding } from "../convex/lib/mockEmbeddings.js";
import { getCvServiceUrl } from "../convex/lib/config.js";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const backendDir = resolve(scriptsDir, "..");
const repoRoot = resolve(backendDir, "..");

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

async function main(): Promise<void> {
  loadEnvLocal();
  const cvServiceUrl = getCvServiceUrl(process.env);

  const samplePath = resolve(repoRoot, "demo-data", "people.sample.json");
  const people = JSON.parse(readFileSync(samplePath, "utf8")) as SamplePerson[];

  console.log(`Enrolling ${people.length} people.`);
  console.log(`CV_SERVICE_URL = ${cvServiceUrl || "(unset -> mock embeddings)"}\n`);

  const embeddings: Record<string, number[]> = {};
  const report: Array<{ id: string; source: string; dim: number }> = [];

  for (const person of people) {
    let source = "mock";
    let embedding = deterministicEmbedding(person.id);

    const imagePath = person.enrollmentImagePath
      ? resolve(repoRoot, person.enrollmentImagePath)
      : null;

    if (cvServiceUrl && imagePath && existsSync(imagePath)) {
      const ext = imagePath.split(".").pop()?.toLowerCase() ?? "jpg";
      const mime = MIME_BY_EXT[ext] ?? "image/jpeg";
      const base64 = readFileSync(imagePath).toString("base64");
      const outcome = await getEmbedding({
        imageBase64: base64,
        imageMimeType: mime,
        requestId: person.id,
        cvServiceUrl,
      });
      if (outcome.source === "cv" && outcome.embedding) {
        embedding = outcome.embedding;
        source = "cv";
      } else if (outcome.faceDetected === false) {
        source = "mock (CV found no face)";
      } else {
        source = "mock (CV unreachable)";
      }
    } else if (cvServiceUrl && imagePath) {
      source = "mock (image missing)";
    }

    embeddings[person.id] = embedding;
    report.push({ id: person.id, source, dim: embedding.length });
    console.log(`  ${person.id.padEnd(20)} ${source.padEnd(24)} dim=${embedding.length}`);
  }

  const outPath = resolve(repoRoot, "demo-data", "embeddings.generated.json");
  writeFileSync(outPath, JSON.stringify(embeddings, null, 2));
  console.log(`\nWrote ${outPath}`);

  const realCount = report.filter((r) => r.source === "cv").length;
  console.log(`\nReal CV embeddings: ${realCount}/${people.length}.`);
  console.log("Load into a running Convex deployment with (PowerShell):");
  console.log(
    `  npx convex run seed:run (\"{\\\"embeddings\\\": $(Get-Content demo-data/embeddings.generated.json -Raw)}\")`,
  );
  console.log("Or just run `npx convex run seed:run` to seed with deterministic mock embeddings.");
}

main().catch((err) => {
  console.error("Enrollment failed:", err);
  process.exit(1);
});
