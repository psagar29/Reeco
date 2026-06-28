/**
 * Fiber AI person-lookup client.
 *
 * Resolves an extracted name (+ optional company/school) into candidate
 * profiles (LinkedIn URL, role, company, profile photo, email). Runs from the
 * BACKEND ONLY — the Fiber key is never exposed to iOS.
 *
 * Fiber's exact response envelope can vary, so the parser is deliberately
 * tolerant: it looks for a candidate array under several common keys and maps
 * many possible field spellings. Network helpers throw on transport failure;
 * the caller (identity:resolveTarget) wraps them and degrades gracefully.
 * Best-effort enrichment helpers (profile pics, contact details) never throw —
 * they return the input unchanged on any failure.
 */

import type { IdentityCandidate } from "./types.js";

export type FiberConfig = {
  apiKey: string;
  /** Base URL with no trailing slash, e.g. "https://api.fiber.ai". */
  baseUrl: string;
};

export type FiberLookupInput = {
  personName: string;
  companyName?: string | null;
  schoolName?: string | null;
  numProfiles?: number;
};

export type FiberClientOptions = {
  config: FiberConfig;
  timeoutMs?: number;
  /** Test seam; defaults to the global fetch. */
  fetchImpl?: typeof fetch;
};

// --- small tolerant helpers -------------------------------------------------

/** Trim + return a non-empty string, or null. */
function str(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const t = value.trim();
  return t ? t : null;
}

/** Join first + last name parts into a full name if both are present. */
function joinName(a: unknown, b: unknown): string | null {
  const first = str(a);
  const last = str(b);
  if (first && last) return `${first} ${last}`;
  return first ?? last ?? null;
}

/** kebab/underscore slug of a name, for stable candidate ids. */
function slug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
}

/** Find the first array living under any of the given keys. */
function firstArray(
  obj: Record<string, unknown>,
  keys: string[],
): unknown[] | null {
  for (const k of keys) {
    const val = obj[k];
    if (Array.isArray(val)) return val;
  }
  // Sometimes nested one level under "result"/"response".
  for (const wrapper of ["result", "response", "data"]) {
    const inner = obj[wrapper];
    if (inner && typeof inner === "object" && !Array.isArray(inner)) {
      const found = firstArray(inner as Record<string, unknown>, keys);
      if (found) return found;
    }
  }
  return null;
}

const NAME_KEYS_FIRST = ["firstName", "first_name", "givenName", "given_name"];
const NAME_KEYS_LAST = ["lastName", "last_name", "familyName", "family_name"];

function pick(p: Record<string, unknown>, keys: string[]): unknown {
  for (const k of keys) {
    if (p[k] !== undefined && p[k] !== null) return p[k];
  }
  return undefined;
}

/**
 * Map an arbitrary Fiber person payload into IdentityCandidate[]. Exported so
 * it can be unit-tested without any network access.
 */
export function parseFiberPeople(
  raw: unknown,
  source = "fiber:kitchen-sink",
): IdentityCandidate[] {
  const root =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {};
  const arr =
    firstArray(root, [
      "profiles",
      "people",
      "results",
      "candidates",
      "matches",
      "data",
    ]) ?? (Array.isArray(raw) ? (raw as unknown[]) : []);

  const out: IdentityCandidate[] = [];
  arr.forEach((item, i) => {
    if (typeof item !== "object" || item === null) return;
    const p = item as Record<string, unknown>;
    const fullName =
      str(pick(p, ["fullName", "full_name", "name", "displayName"])) ??
      joinName(pick(p, NAME_KEYS_FIRST), pick(p, NAME_KEYS_LAST));
    if (!fullName) return;
    const linkedinUrl = str(
      pick(p, [
        "linkedinUrl",
        "linkedin_url",
        "linkedin",
        "profileUrl",
        "profile_url",
        "url",
      ]),
    );
    out.push({
      candidateId: `cand_${i}_${slug(fullName)}`,
      fullName,
      headline: str(pick(p, ["headline", "summary", "bio", "tagline"])),
      role: str(
        pick(p, ["role", "title", "jobTitle", "job_title", "occupation"]),
      ),
      company: str(
        pick(p, [
          "company",
          "companyName",
          "company_name",
          "organization",
          "employer",
          "currentCompany",
        ]),
      ),
      school: str(pick(p, ["school", "university", "education"])),
      location: str(pick(p, ["location", "city", "region", "country"])),
      linkedinUrl,
      email: str(
        pick(p, ["email", "workEmail", "work_email", "contactEmail"]),
      ),
      profilePhotoUrl: str(
        pick(p, [
          "profilePhotoUrl",
          "profilePicUrl",
          "profile_pic_url",
          "profilePictureUrl",
          "photoUrl",
          "photo_url",
          "imageUrl",
          "image_url",
          "picture",
          "avatar",
          "avatarUrl",
        ]),
      ),
      source,
      matchScore: 0,
    });
  });
  return out;
}

/**
 * Fiber "Kitchen Sink" person lookup. Throws on transport failure.
 */
export async function findCandidates(
  input: FiberLookupInput,
  opts: FiberClientOptions,
): Promise<IdentityCandidate[]> {
  if (!opts.config.apiKey) throw new Error("Fiber: no API key configured");
  const doFetch = opts.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 20000);
  try {
    // Fiber's hackathon API authenticates via `apiKey` IN THE JSON BODY (not a
    // Bearer header), and wraps each query field in a `{ value, ... }` object.
    const body: Record<string, unknown> = {
      apiKey: opts.config.apiKey,
      personName: { value: input.personName, looseMatch: true },
      numProfiles: input.numProfiles ?? 5,
      liveFetch: true,
    };
    if (input.companyName) body.companyName = { value: input.companyName };
    if (input.schoolName) body.schoolName = { value: input.schoolName };

    const res = await doFetch(`${opts.config.baseUrl}/v1/kitchen-sink/person`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(
        `Fiber kitchen-sink HTTP ${res.status}: ${body.slice(0, 200)}`,
      );
    }
    return parseFiberPeople(await res.json(), "fiber:kitchen-sink");
  } finally {
    clearTimeout(timer);
  }
}

/** Tolerantly build a linkedinUrl(lowercased) -> photoUrl map. */
function parseProfilePicMap(raw: unknown): Record<string, string> {
  const map: Record<string, string> = {};
  const root =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {};
  const arr =
    firstArray(root, ["profiles", "results", "pics", "data", "items"]) ??
    (Array.isArray(raw) ? (raw as unknown[]) : []);
  for (const item of arr) {
    if (typeof item !== "object" || item === null) continue;
    const p = item as Record<string, unknown>;
    const url = str(pick(p, ["linkedinUrl", "linkedin_url", "linkedin", "url"]));
    const pic = str(
      pick(p, [
        "profilePicUrl",
        "profile_pic_url",
        "profilePhotoUrl",
        "photoUrl",
        "imageUrl",
        "picture",
      ]),
    );
    if (url && pic) map[url.toLowerCase()] = pic;
  }
  return map;
}

/**
 * Best-effort: fill missing profile photos via Fiber's bulk profile-pic
 * endpoint. Never throws — returns the input unchanged on any failure.
 */
export async function enrichProfilePics(
  candidates: IdentityCandidate[],
  opts: FiberClientOptions,
): Promise<IdentityCandidate[]> {
  if (!opts.config.apiKey) return candidates;
  const missing = candidates.filter((c) => !c.profilePhotoUrl && c.linkedinUrl);
  if (missing.length === 0) return candidates;
  try {
    const doFetch = opts.fetchImpl ?? fetch;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 20000);
    try {
      const res = await doFetch(`${opts.config.baseUrl}/v1/profile-pic/bulk`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          apiKey: opts.config.apiKey,
          linkedinUrls: missing.map((c) => c.linkedinUrl),
        }),
        signal: controller.signal,
      });
      if (!res.ok) return candidates;
      const map = parseProfilePicMap(await res.json());
      return candidates.map((c) => {
        if (c.profilePhotoUrl || !c.linkedinUrl) return c;
        const pic = map[c.linkedinUrl.toLowerCase()];
        return pic ? { ...c, profilePhotoUrl: pic } : c;
      });
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return candidates;
  }
}

/**
 * Best-effort: backfill a candidate's email/role via Fiber's contact-details
 * endpoint. Never throws — returns the input candidate unchanged on failure.
 */
export async function enrichContactDetails(
  candidate: IdentityCandidate,
  opts: FiberClientOptions,
): Promise<IdentityCandidate> {
  if (!opts.config.apiKey || !candidate.linkedinUrl) return candidate;
  if (candidate.email) return candidate;
  try {
    const doFetch = opts.fetchImpl ?? fetch;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 20000);
    try {
      const res = await doFetch(
        `${opts.config.baseUrl}/v1/contact-details/single`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            apiKey: opts.config.apiKey,
            linkedinUrl: candidate.linkedinUrl,
            validateEmails: true,
          }),
          signal: controller.signal,
        },
      );
      if (!res.ok) return candidate;
      const data = await res.json();
      const root =
        typeof data === "object" && data !== null
          ? (data as Record<string, unknown>)
          : {};
      const inner =
        root.result && typeof root.result === "object"
          ? (root.result as Record<string, unknown>)
          : root;
      const email = str(
        pick(inner, [
          "email",
          "workEmail",
          "work_email",
          "personalEmail",
          "contactEmail",
        ]),
      );
      return email ? { ...candidate, email } : candidate;
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return candidate;
  }
}
