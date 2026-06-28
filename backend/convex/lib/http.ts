/**
 * Framework-free helpers for the iOS HTTP bridge (convex/http.ts).
 *
 * Everything here is pure (no Convex imports) so it can be unit-tested with
 * plain Node/Vitest. The Convex `http.ts` router is a thin wiring layer that
 * reads the request body, calls these validators, invokes the existing public
 * functions, and serializes the result with `jsonResponse`.
 *
 * Design goals:
 *  - Every response (success AND error) is JSON with permissive CORS headers so
 *    local tools (curl, iOS URLSession, a browser fetch) can call it directly.
 *  - Invalid input fails closed with a readable 4xx, never a leaked stack trace.
 *  - Face-match results are normalized so iOS can only ever show a name for a
 *    confident match (see `sanitizeMatchResult`).
 */

import type { FaceMatchResult, FilterCommand } from "./types.js";

/** An error carrying the HTTP status the bridge should return. */
export class HttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

/** CORS headers applied to every bridge response (incl. errors & preflight). */
export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

/** Headers for a JSON body response: CORS + content type. */
export const JSON_HEADERS: Record<string, string> = {
  ...CORS_HEADERS,
  "Content-Type": "application/json",
};

/** Build a JSON `Response` with CORS headers and the given status (default 200). */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

/** Build a JSON error `Response` in the frozen `{ ok:false, error }` shape. */
export function errorResponse(message: string, status = 500): Response {
  return jsonResponse({ ok: false, error: message }, status);
}

/** Empty 204 response for a CORS preflight (`OPTIONS`) request. */
export function optionsResponse(): Response {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

/** Narrow an unknown JSON value to a plain object, or throw a 400. */
function asObject(body: unknown, label = "Request body"): Record<string, unknown> {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, `${label} must be a JSON object`);
  }
  return body as Record<string, unknown>;
}

/** Coerce a value to a string array, dropping non-strings. Missing -> []. */
function toStringArray(value: unknown): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) return [];
  return value.filter((x): x is string => typeof x === "string");
}

const FILTER_ACTIONS = new Set(["filter", "rank", "reset", "draft"]);
const RANK_BY = new Set(["relevance", "infra", "growth", "ai", "founder"]);

/**
 * Validate the body of `POST /api/state/filter` and return a clean
 * `{ command }`. Accepts `{ command: FilterCommand }`. Throws 400 on bad input
 * so the bridge never forwards garbage into the Convex mutation validator.
 */
export function parseFilterRequest(body: unknown): { command: FilterCommand } {
  const root = asObject(body);
  const raw = asObject(root.command, "`command`");

  const action = raw.action;
  if (typeof action !== "string" || !FILTER_ACTIONS.has(action)) {
    throw new HttpError(
      400,
      '`command.action` must be one of "filter" | "rank" | "reset" | "draft"',
    );
  }

  const command: FilterCommand = {
    action: action as FilterCommand["action"],
    includeTags: toStringArray(raw.includeTags),
    excludeTags: toStringArray(raw.excludeTags),
  };

  if (raw.rankBy === null) {
    command.rankBy = null;
  } else if (typeof raw.rankBy === "string") {
    if (!RANK_BY.has(raw.rankBy)) {
      throw new HttpError(400, "`command.rankBy` is not a recognized value");
    }
    command.rankBy = raw.rankBy as FilterCommand["rankBy"];
  }

  if (raw.targetPersonId === null || typeof raw.targetPersonId === "string") {
    command.targetPersonId = raw.targetPersonId as string | null;
  }
  if (raw.rawText === null || typeof raw.rawText === "string") {
    command.rawText = raw.rawText as string | null;
  }

  return { command };
}

/** Validate the body of `POST /api/voice/interpret`. */
export function parseInterpretRequest(body: unknown): {
  transcript: string;
  visiblePersonIds?: string[];
} {
  const root = asObject(body);
  if (typeof root.transcript !== "string") {
    throw new HttpError(400, "`transcript` must be a string");
  }
  const out: { transcript: string; visiblePersonIds?: string[] } = {
    transcript: root.transcript,
  };
  if (root.visiblePersonIds !== undefined) {
    out.visiblePersonIds = toStringArray(root.visiblePersonIds);
  }
  return out;
}

/** Validate the body of `POST /api/drafts/opener`. */
export function parseOpenerRequest(body: unknown): {
  personId: string;
  userGoal?: string | null;
} {
  const root = asObject(body);
  if (typeof root.personId !== "string" || root.personId.length === 0) {
    throw new HttpError(400, "`personId` must be a non-empty string");
  }
  const out: { personId: string; userGoal?: string | null } = {
    personId: root.personId,
  };
  if (root.userGoal === null || typeof root.userGoal === "string") {
    out.userGoal = root.userGoal as string | null;
  }
  return out;
}

const IMAGE_MIME_TYPES = new Set(["image/jpeg", "image/png"]);

/**
 * Validate the body of `POST /api/identity/resolve` ("find info on him").
 * `trackId` is required. Both crops are optional (the action degrades to
 * `needs_clarification` when the context/badge image is missing) so a minimal
 * payload still works. `imageMimeType` defaults to "image/jpeg".
 */
export function parseIdentityResolveRequest(body: unknown): {
  trackId: string;
  transcript?: string | null;
  faceImageBase64: string;
  contextImageBase64: string;
  imageMimeType: "image/jpeg" | "image/png";
} {
  const root = asObject(body);
  if (typeof root.trackId !== "string" || root.trackId.length === 0) {
    throw new HttpError(400, "`trackId` must be a non-empty string");
  }

  const faceImageBase64 =
    typeof root.faceImageBase64 === "string" ? root.faceImageBase64 : "";
  const contextImageBase64 =
    typeof root.contextImageBase64 === "string" ? root.contextImageBase64 : "";

  let imageMimeType: "image/jpeg" | "image/png" = "image/jpeg";
  if (root.imageMimeType !== undefined) {
    if (
      typeof root.imageMimeType !== "string" ||
      !IMAGE_MIME_TYPES.has(root.imageMimeType)
    ) {
      throw new HttpError(
        400,
        '`imageMimeType` must be "image/jpeg" or "image/png"',
      );
    }
    imageMimeType = root.imageMimeType as "image/jpeg" | "image/png";
  }

  const out: {
    trackId: string;
    transcript?: string | null;
    faceImageBase64: string;
    contextImageBase64: string;
    imageMimeType: "image/jpeg" | "image/png";
  } = { trackId: root.trackId, faceImageBase64, contextImageBase64, imageMimeType };

  if (root.transcript === null || typeof root.transcript === "string") {
    out.transcript = root.transcript as string | null;
  }
  return out;
}

/**
 * Validate the body of `POST /api/vision/match-face`. `imageBase64` is required;
 * `imageMimeType` defaults to "image/jpeg" and `trackId` is generated when
 * absent so a minimal iOS payload still works.
 */
export function parseMatchFaceRequest(body: unknown): {
  imageBase64: string;
  imageMimeType: "image/jpeg" | "image/png";
  trackId: string;
} {
  const root = asObject(body);
  if (typeof root.imageBase64 !== "string" || root.imageBase64.length === 0) {
    throw new HttpError(400, "`imageBase64` must be a non-empty base64 string");
  }

  let imageMimeType: "image/jpeg" | "image/png" = "image/jpeg";
  if (root.imageMimeType !== undefined) {
    if (
      typeof root.imageMimeType !== "string" ||
      !IMAGE_MIME_TYPES.has(root.imageMimeType)
    ) {
      throw new HttpError(
        400,
        '`imageMimeType` must be "image/jpeg" or "image/png"',
      );
    }
    imageMimeType = root.imageMimeType as "image/jpeg" | "image/png";
  }

  const trackId =
    typeof root.trackId === "string" && root.trackId.length > 0
      ? root.trackId
      : `trk_${Date.now()}`;

  return { imageBase64: root.imageBase64, imageMimeType, trackId };
}

/**
 * Defensive safety net for face matches crossing the HTTP boundary: only a
 * `matched` or `tentative` result may carry a `personId`. `unknown` / `no_face`
 * / `error` always have it stripped so iOS can never render a wrong named
 * overlay. (vision:matchFace already does this; this re-asserts the invariant.)
 */
export function sanitizeMatchResult(result: FaceMatchResult): FaceMatchResult {
  if (result.status === "matched" || result.status === "tentative") {
    return result;
  }
  if (result.personId == null) return result;
  return { ...result, personId: null };
}
