/**
 * Identity scoring + status decision.
 *
 * Pure, framework-free logic (unit-testable with plain Vitest) that combines:
 *   - OCR text agreement between the badge clue and a Fiber candidate,
 *   - the face-verification score (cosine of the candidate's profile photo vs
 *     the live face), when a profile photo exists.
 *
 * Guiding rule (safety): a candidate is only ever "verified" when the text
 * match is strong AND face verification passed. With no profile photo we return
 * "possible" — never "verified".
 */

import type {
  FaceVerification,
  IdentityCandidate,
  IdentityClue,
  IdentityResolveStatus,
} from "./types.js";

/** Normalized cosine reference: a profile-vs-live cosine at/above this is a
 * confident face match for normalization purposes. */
const FACE_NORM_REFERENCE = 0.6;

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return n < 0 ? 0 : n > 1 ? 1 : n;
}

/** Lowercase alphanumeric tokens of length >= 2 (drops middle initials). */
function tokens(s: string | null | undefined): string[] {
  if (!s) return [];
  return s
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length >= 2);
}

function anyOverlap(a: Set<string>, b: string[]): boolean {
  return b.some((t) => a.has(t));
}

/**
 * 0..1 measure of how well a Fiber candidate matches the OCR clue, based on
 * name-token overlap with small bonuses for company/school agreement.
 */
export function textMatchScore(
  clue: IdentityClue,
  candidate: IdentityCandidate,
): number {
  const clueName = tokens(clue.fullName);
  const candName = new Set(tokens(candidate.fullName));
  if (clueName.length === 0 || candName.size === 0) return 0;

  let hits = 0;
  for (const t of clueName) if (candName.has(t)) hits++;
  let score = hits / clueName.length;

  if (clue.company && candidate.company) {
    if (anyOverlap(new Set(tokens(clue.company)), tokens(candidate.company))) {
      score += 0.15;
    }
  }
  if (clue.school && candidate.school) {
    if (anyOverlap(new Set(tokens(clue.school)), tokens(candidate.school))) {
      score += 0.1;
    }
  }
  return clamp01(score);
}

/**
 * Ranking score for a candidate. Non-verified candidates score in [0, 1] (text,
 * or a text+face blend when a face was found but did not pass). A face-verified
 * candidate is lifted into a strictly higher band [1, 2] so it ALWAYS outranks
 * any non-verified one — even a perfect-text-match homonym (text can reach 1.0).
 *
 * Without this band separation the [0,1] clamp would let an unverified homonym
 * tie or beat the verified candidate, which would both surface the wrong person
 * and wrongly downgrade the result from "verified" to "possible".
 */
export function combineScores(input: {
  clue: IdentityClue;
  candidate: IdentityCandidate;
  verification?: FaceVerification | null;
}): number {
  const text = textMatchScore(input.clue, input.candidate);
  const v = input.verification;
  if (!v || !v.faceDetected || v.score == null) {
    return clamp01(text);
  }
  const faceNorm = clamp01(v.score / FACE_NORM_REFERENCE);
  const base = clamp01(0.55 * text + 0.45 * faceNorm);
  return v.verified ? base + 1 : base;
}

/** Pick the highest-`matchScore` candidate (null when the list is empty). */
export function pickBest(
  candidates: IdentityCandidate[],
): IdentityCandidate | null {
  let best: IdentityCandidate | null = null;
  for (const c of candidates) {
    if (!best || c.matchScore > best.matchScore) best = c;
  }
  return best;
}

/**
 * Final status decision. "verified" requires strong text AND a passing face
 * verification; otherwise we degrade conservatively.
 */
export function decideStatus(input: {
  clue: IdentityClue;
  best: IdentityCandidate | null;
  verification: FaceVerification | null;
  hadCandidates: boolean;
  minOcrConfidence: number;
}): IdentityResolveStatus {
  const { clue, best, verification, hadCandidates, minOcrConfidence } = input;
  if (!clue.fullName || clue.confidence < minOcrConfidence) {
    return "needs_clarification";
  }
  if (!hadCandidates || !best) return "not_found";
  const strongText = textMatchScore(clue, best) >= 0.5;
  if (verification && verification.verified && strongText) return "verified";
  return "possible";
}
