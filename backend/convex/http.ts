/**
 * iOS HTTP bridge.
 *
 * Exposes the existing public Convex functions as ordinary REST-ish JSON
 * endpoints so Person A's native iOS `URLSession` client can call them without
 * a Convex client integration. Each handler is a thin wrapper: it validates the
 * request with the pure helpers in `lib/http.ts`, calls the matching public
 * function (the same ones `npx convex run` uses), and serializes the result.
 *
 *   GET  /api/health           -> { ok, service, time }
 *   GET  /api/people           -> PublicPerson[]            (no embeddings)
 *   GET  /api/state            -> BrainState
 *   POST /api/state/filter     -> BrainState                ({ command })
 *   POST /api/voice/interpret  -> FilterCommand             ({ transcript, visiblePersonIds? })
 *   POST /api/drafts/opener    -> DraftResult               ({ personId, userGoal? })
 *   POST /api/vision/match-face-> FaceMatchResult           ({ imageBase64, imageMimeType?, trackId? })
 *   POST /api/identity/resolve -> IdentityResolveResult     ({ trackId, transcript?, faceImageBase64?, contextImageBase64?, imageMimeType? })
 *   POST /api/voice/deepgram-token -> { temporaryToken, expiresAt }
 *
 * All responses (success and error) are JSON with permissive CORS headers, and
 * every route answers `OPTIONS` preflight. Errors use `{ ok:false, error }`.
 */

import { httpRouter, type RoutableMethod } from "convex/server";
import { httpAction, type ActionCtx } from "./_generated/server.js";
import { api } from "./_generated/api.js";
import {
  HttpError,
  errorResponse,
  jsonResponse,
  optionsResponse,
  parseFilterRequest,
  parseFollowUpStatusRequest,
  parseIdentityResolveRequest,
  parseInterpretRequest,
  parseMatchFaceRequest,
  parseMissionCurrentRequest,
  parseMissionParseRequest,
  parseOpenerRequest,
  parseScanMemoryUpsertRequest,
  parseScoreRequest,
  parseUpdateNotesRequest,
  parseGenerateOutreachRequest,
  sanitizeMatchResult,
} from "./lib/http.js";

const http = httpRouter();

/** Parse a request body as JSON, mapping malformed bodies to a clean 400. */
async function readJsonBody(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, "Request body must be valid JSON");
  }
}

/**
 * Wrap a handler so it always returns JSON: success -> 200 with the value,
 * HttpError -> its status, anything else -> 500 with the message. No stack
 * traces or secrets ever leave the process.
 */
function jsonAction(fn: (ctx: ActionCtx, request: Request) => Promise<unknown>) {
  return httpAction(async (ctx, request) => {
    try {
      const data = await fn(ctx, request);
      return jsonResponse(data);
    } catch (err) {
      if (err instanceof HttpError) return errorResponse(err.message, err.status);
      const message = err instanceof Error ? err.message : "Internal server error";
      return errorResponse(message, 500);
    }
  });
}

const optionsAction = httpAction(async () => optionsResponse());

/** Register a method handler plus an OPTIONS preflight handler for one path. */
function route(
  path: string,
  method: RoutableMethod,
  handler: ReturnType<typeof httpAction>,
): void {
  http.route({ path, method, handler });
  http.route({ path, method: "OPTIONS", handler: optionsAction });
}

// --- GET /api/health --------------------------------------------------------
route(
  "/api/health",
  "GET",
  jsonAction(async () => ({
    ok: true,
    service: "recco-backend",
    time: Date.now(),
  })),
);

// --- GET /api/people  (PublicPerson[], never embeddings) --------------------
route(
  "/api/people",
  "GET",
  jsonAction(async (ctx) => ctx.runQuery(api.people.list, {})),
);

// --- GET /api/state  (BrainState) -------------------------------------------
route(
  "/api/state",
  "GET",
  jsonAction(async (ctx) => ctx.runQuery(api.state.get, {})),
);

// --- POST /api/state/filter  ({ command }) -> BrainState --------------------
route(
  "/api/state/filter",
  "POST",
  jsonAction(async (ctx, request) => {
    const { command } = parseFilterRequest(await readJsonBody(request));
    return ctx.runMutation(api.state.setFilter, { command });
  }),
);

// --- POST /api/voice/interpret  -> FilterCommand ----------------------------
route(
  "/api/voice/interpret",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseInterpretRequest(await readJsonBody(request));
    return ctx.runAction(api.voice.interpretCommand, args);
  }),
);

// --- POST /api/drafts/opener  -> DraftResult --------------------------------
route(
  "/api/drafts/opener",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseOpenerRequest(await readJsonBody(request));
    return ctx.runAction(api.drafts.createOpener, args);
  }),
);

// --- POST /api/vision/match-face  -> FaceMatchResult ------------------------
route(
  "/api/vision/match-face",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseMatchFaceRequest(await readJsonBody(request));
    const result = await ctx.runAction(api.vision.matchFace, args);
    // Re-assert the safety invariant at the boundary: no name for low confidence.
    return sanitizeMatchResult(result);
  }),
);

// --- POST /api/identity/resolve  ("find info on him") -----------------------
route(
  "/api/identity/resolve",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseIdentityResolveRequest(await readJsonBody(request));
    return ctx.runAction(api.identity.resolveTarget, args);
  }),
);

// --- POST /api/voice/deepgram-token  -> short-lived streaming token ---------
route(
  "/api/voice/deepgram-token",
  "POST",
  jsonAction(async (ctx) => ctx.runAction(api.voice.getDeepgramToken, {})),
);

// --- GET /api/brain/memories[?clientId=...]  -> ScanMemory[] ----------------
route(
  "/api/brain/memories",
  "GET",
  jsonAction(async (ctx, request) => {
    const clientId = new URL(request.url).searchParams.get("clientId");
    return ctx.runQuery(api.scanMemories.list, { clientId: clientId ?? null });
  }),
);

// --- POST /api/mission/parse  -> MissionProfile -----------------------------
route(
  "/api/mission/parse",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseMissionParseRequest(await readJsonBody(request));
    return ctx.runAction(api.mission.parse, args);
  }),
);

// --- POST /api/mission/current  -> MissionProfile | null --------------------
route(
  "/api/mission/current",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseMissionCurrentRequest(await readJsonBody(request));
    return ctx.runQuery(api.mission.current, args);
  }),
);

// --- POST /api/brain/memories/upsert  -> ScanMemory -------------------------
route(
  "/api/brain/memories/upsert",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseScanMemoryUpsertRequest(await readJsonBody(request));
    return ctx.runMutation(api.scanMemories.upsertFromIdentityResult, args);
  }),
);

// --- POST /api/brain/memories/notes  -> ScanMemory | null -------------------
route(
  "/api/brain/memories/notes",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseUpdateNotesRequest(await readJsonBody(request));
    return ctx.runMutation(api.scanMemories.updateNotes, args);
  }),
);

// --- POST /api/brain/memories/score  -> ScanMemory | null -------------------
route(
  "/api/brain/memories/score",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseScoreRequest(await readJsonBody(request));
    return ctx.runMutation(api.scanMemories.score, args);
  }),
);

// --- POST /api/brain/memories/follow-up-status  -> ScanMemory | null --------
route(
  "/api/brain/memories/follow-up-status",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseFollowUpStatusRequest(await readJsonBody(request));
    return ctx.runMutation(api.scanMemories.updateFollowUpStatus, args);
  }),
);

// --- POST /api/brain/memories/outreach  -> OutreachDraft --------------------
route(
  "/api/brain/memories/outreach",
  "POST",
  jsonAction(async (ctx, request) => {
    const args = parseGenerateOutreachRequest(await readJsonBody(request));
    return ctx.runAction(api.scanMemories.generateOutreach, args);
  }),
);

export default http;
