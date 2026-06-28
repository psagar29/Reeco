/**
 * Environment-driven configuration helpers.
 *
 * Takes an explicit env bag (defaults to process.env) so it stays testable and
 * works identically in the Convex runtime and Node scripts.
 */

import {
  DEFAULT_STRONG_MATCH_SCORE,
  DEFAULT_TENTATIVE_MATCH_SCORE,
  type Thresholds,
} from "./similarity.js";

export type EnvBag = Record<string, string | undefined>;

function num(value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

/** Face-match thresholds from FACE_STRONG/TENTATIVE_MATCH_SCORE env vars. */
export function getThresholds(env: EnvBag = process.env): Thresholds {
  return {
    strong: num(env.FACE_STRONG_MATCH_SCORE, DEFAULT_STRONG_MATCH_SCORE),
    tentative: num(env.FACE_TENTATIVE_MATCH_SCORE, DEFAULT_TENTATIVE_MATCH_SCORE),
  };
}

export function getCvServiceUrl(env: EnvBag = process.env): string {
  return (env.CV_SERVICE_URL ?? "").trim();
}

export function getOpenAiConfig(env: EnvBag = process.env): {
  apiKey: string;
  model: string;
} {
  return {
    apiKey: (env.OPENAI_API_KEY ?? "").trim(),
    model: (env.OPENAI_MODEL ?? "gpt-4o-mini").trim() || "gpt-4o-mini",
  };
}

export function getDeepgramApiKey(env: EnvBag = process.env): string {
  return (env.DEEPGRAM_API_KEY ?? "").trim();
}

// ---------------------------------------------------------------------------
// Identity resolution ("find info on him") config.
// ---------------------------------------------------------------------------

/** Defaults for the identity thresholds, also reused in tests. */
export const DEFAULT_IDENTITY_MIN_OCR_CONFIDENCE = 0.45;
/**
 * Cosine-similarity floor for declaring a candidate's profile photo a match
 * for the live face. Slightly below FACE_STRONG_MATCH_SCORE (0.38) because the
 * profile photo and live frame differ in lighting/angle; still conservative
 * enough that we never label someone "verified" on a weak match.
 */
export const DEFAULT_IDENTITY_FACE_VERIFY_THRESHOLD = 0.32;

/** Fiber AI lookup credentials + base URL. */
export function getFiberConfig(env: EnvBag = process.env): {
  apiKey: string;
  baseUrl: string;
} {
  const baseUrl = (env.FIBER_API_BASE_URL ?? "").trim() || "https://api.fiber.ai";
  return {
    apiKey: (env.FIBER_API_KEY ?? "").trim(),
    // Normalize: drop any trailing slashes so callers can append "/v1/...".
    baseUrl: baseUrl.replace(/\/+$/, ""),
  };
}

/** OpenAI vision model used to read badges/name tags (OCR + extraction). */
export function getOpenAiVisionModel(env: EnvBag = process.env): string {
  return (env.OPENAI_VISION_MODEL ?? "gpt-4o").trim() || "gpt-4o";
}

/** Identity-resolution thresholds (OCR confidence floor + face-verify floor). */
export function getIdentityThresholds(env: EnvBag = process.env): {
  minOcrConfidence: number;
  faceVerifyThreshold: number;
} {
  return {
    minOcrConfidence: num(
      env.IDENTITY_MIN_OCR_CONFIDENCE,
      DEFAULT_IDENTITY_MIN_OCR_CONFIDENCE,
    ),
    faceVerifyThreshold: num(
      env.IDENTITY_FACE_VERIFY_THRESHOLD,
      DEFAULT_IDENTITY_FACE_VERIFY_THRESHOLD,
    ),
  };
}
