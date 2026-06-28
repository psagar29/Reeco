/**
 * identity:resolveTarget — the "find info on him" action.
 *
 * Given a locked target's tight face crop (for verification) and a wider
 * person/badge crop (for OCR), this:
 *   1. reads the name tag with OpenAI Vision (lib/openaiVision),
 *   2. finds candidate profiles with Fiber AI (lib/fiber),
 *   3. embeds the live face + each candidate's profile photo via the CV service
 *      (lib/cv) and compares them with cosine similarity (lib/similarity),
 *   4. scores + decides a final status (lib/identityScoring).
 *
 * Every external key (OpenAI, Fiber) is read from the deployment env here — the
 * iOS app never holds them. Like the other actions, this NEVER throws: failures
 * are caught and returned as a structured `error`/degraded result. A debug row
 * (text + scores only, NEVER raw images) is logged to `identityLookups`.
 */

import { action, internalMutation } from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import { identityResolveResultValidator } from "./validators.js";
import type {
  FaceVerification,
  IdentityCandidate,
  IdentityClue,
  IdentityResolveResult,
  IdentityResolveStatus,
} from "./lib/types.js";
import {
  getOpenAiConfig,
  getOpenAiVisionModel,
  getFiberConfig,
  getCvServiceUrl,
  getIdentityThresholds,
} from "./lib/config.js";
import { readBadge } from "./lib/openaiVision.js";
import {
  findCandidates,
  enrichProfilePics,
  enrichContactDetails,
} from "./lib/fiber.js";
import { getEmbedding } from "./lib/cv.js";
import { cosine } from "./lib/similarity.js";
import {
  combineScores,
  decideStatus,
  pickBest,
} from "./lib/identityScoring.js";
import type { ActionCtx } from "./_generated/server.js";

const emptyClue = (evidence: string): IdentityClue => ({
  rawText: "",
  fullName: null,
  company: null,
  role: null,
  school: null,
  confidence: 0,
  evidence,
});

/** Encode raw bytes to base64 (chunked so we don't blow the call stack). */
function base64FromBytes(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** Download a candidate's profile photo and face-verify it vs the live face. */
async function verifyCandidate(
  candidate: IdentityCandidate,
  liveEmbedding: number[],
  liveSource: "cv" | "mock",
  cvServiceUrl: string,
  threshold: number,
): Promise<FaceVerification> {
  const base: FaceVerification = {
    candidateId: candidate.candidateId,
    verified: false,
    score: null,
    threshold,
    faceDetected: false,
    message: null,
  };
  if (!candidate.profilePhotoUrl) {
    return { ...base, message: "no profile photo" };
  }
  // Bound the profile-photo download so a slow or bad image URL can never hang
  // the whole identity request.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(candidate.profilePhotoUrl, {
      signal: controller.signal,
    });
    if (!res.ok) {
      return { ...base, message: `photo HTTP ${res.status}` };
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    const contentType = res.headers.get("content-type") ?? "";
    const mime = contentType.includes("png") ? "image/png" : "image/jpeg";
    const photo = await getEmbedding({
      imageBase64: base64FromBytes(bytes),
      imageMimeType: mime,
      requestId: `${candidate.candidateId}-photo`,
      cvServiceUrl,
    });
    if (!photo.faceDetected || !photo.embedding) {
      return { ...base, message: "no face in profile photo" };
    }
    const score = cosine(liveEmbedding, photo.embedding);
    // SAFETY: only declare a verified match when BOTH embeddings came from the
    // REAL CV service. If either side fell back to deterministic mock embeddings
    // (CV unavailable / not ready), report the score but never "verified" —
    // mock vectors are unrelated, so a "verified" there would be meaningless.
    const realCv = liveSource === "cv" && photo.source === "cv";
    return {
      candidateId: candidate.candidateId,
      verified: realCv && score >= threshold,
      score,
      threshold,
      faceDetected: true,
      message: realCv
        ? null
        : "CV service unavailable (mock embeddings) — not verified.",
    };
  } catch (err) {
    return {
      ...base,
      message: err instanceof Error ? err.message : String(err),
    };
  } finally {
    clearTimeout(timer);
  }
}

function messageFor(
  status: IdentityResolveStatus,
  clue: IdentityClue,
  best: IdentityCandidate | null,
  verification: FaceVerification | null,
): string {
  switch (status) {
    case "verified":
      return best
        ? `Verified ${best.fullName}${best.company ? ` · ${best.company}` : ""}.`
        : "Verified.";
    case "possible": {
      const who = best ? best.fullName : "someone";
      if (verification && verification.faceDetected && !verification.verified) {
        return `Possible match: ${who}. Face did not confirm.`;
      }
      return `Possible match: ${who}. Not face-verified.`;
    }
    case "not_found":
      return clue.fullName
        ? `No profile found for ${clue.fullName}.`
        : "No profile found.";
    case "needs_clarification":
      return clue.fullName
        ? "Low confidence reading the name tag — try again or say the name."
        : "Couldn't read a name tag. Move closer or say the name.";
    case "error":
    default:
      return "Something went wrong resolving this person.";
  }
}

async function safeLog(
  ctx: ActionCtx,
  result: IdentityResolveResult,
  transcript: string | null,
): Promise<void> {
  try {
    await ctx.runMutation(internal.identity.recordLookup, {
      trackId: result.trackId,
      status: result.status,
      transcript,
      clueName: result.clue?.fullName ?? null,
      clueCompany: result.clue?.company ?? null,
      ocrConfidence: result.clue?.confidence ?? null,
      candidateCount: result.candidates.length,
      selectedCandidateId: result.bestCandidate?.candidateId ?? null,
      selectedName: result.bestCandidate?.fullName ?? null,
      selectedLinkedin: result.bestCandidate?.linkedinUrl ?? null,
      verificationScore: result.verification?.score ?? null,
      verified: result.verification?.verified ?? null,
      latencyMs: result.latencyMs ?? null,
    });
  } catch {
    // Logging is best-effort; never let it affect the response.
  }
}

export const resolveTarget = action({
  args: {
    trackId: v.string(),
    transcript: v.optional(v.union(v.string(), v.null())),
    faceImageBase64: v.string(),
    contextImageBase64: v.string(),
    imageMimeType: v.union(v.literal("image/jpeg"), v.literal("image/png")),
  },
  returns: identityResolveResultValidator,
  handler: async (ctx, args): Promise<IdentityResolveResult> => {
    const start = Date.now();
    const { trackId } = args;
    const transcript = args.transcript ?? null;

    const finish = async (
      status: IdentityResolveStatus,
      clue: IdentityClue | null,
      candidates: IdentityCandidate[],
      best: IdentityCandidate | null,
      verification: FaceVerification | null,
    ): Promise<IdentityResolveResult> => {
      const result: IdentityResolveResult = {
        trackId,
        status,
        clue,
        candidates,
        bestCandidate: best,
        verification,
        message: messageFor(status, clue ?? emptyClue(""), best, verification),
        latencyMs: Date.now() - start,
      };
      await safeLog(ctx, result, transcript);
      return result;
    };

    try {
      const openai = getOpenAiConfig(process.env);
      const visionModel = getOpenAiVisionModel(process.env);
      const fiber = getFiberConfig(process.env);
      const cvServiceUrl = getCvServiceUrl(process.env);
      const { minOcrConfidence, faceVerifyThreshold } =
        getIdentityThresholds(process.env);

      // 1. OCR the badge / context crop.
      let clue: IdentityClue;
      if (!openai.apiKey) {
        clue = emptyClue("OpenAI Vision not configured");
      } else if (!args.contextImageBase64) {
        clue = emptyClue("no context image captured");
      } else {
        try {
          clue = await readBadge({
            apiKey: openai.apiKey,
            model: visionModel,
            imageBase64: args.contextImageBase64,
            imageMimeType: args.imageMimeType,
            transcript,
          });
        } catch (err) {
          clue = emptyClue(
            err instanceof Error ? err.message : "vision failed",
          );
        }
      }

      if (!clue.fullName || clue.confidence < minOcrConfidence) {
        return finish("needs_clarification", clue, [], null, null);
      }

      // 2. Fiber candidate lookup (+ best-effort profile-pic enrichment).
      let candidates: IdentityCandidate[] = [];
      if (fiber.apiKey) {
        candidates = await findCandidates(
          {
            personName: clue.fullName,
            companyName: clue.company,
            schoolName: clue.school,
            numProfiles: 5,
          },
          { config: fiber },
        );
        candidates = await enrichProfilePics(candidates, { config: fiber });
      } else {
        return finish(
          "not_found",
          { ...clue, evidence: "Fiber lookup not configured" },
          [],
          null,
          null,
        );
      }

      if (candidates.length === 0) {
        return finish("not_found", clue, [], null, null);
      }

      // 3. Embed the live face once, then face-verify each candidate that has a
      //    profile photo. Track whether the live embedding is REAL CV — a
      //    candidate can only be "verified" when both sides are real CV.
      let liveEmbedding: number[] | null = null;
      let liveSource: "cv" | "mock" = "mock";
      if (args.faceImageBase64) {
        const live = await getEmbedding({
          imageBase64: args.faceImageBase64,
          imageMimeType: args.imageMimeType,
          requestId: `${trackId}-live`,
          cvServiceUrl,
        });
        liveEmbedding = live.faceDetected ? live.embedding : null;
        liveSource = live.source;
      }

      const verifications = new Map<string, FaceVerification>();
      for (const cand of candidates) {
        let verification: FaceVerification | null = null;
        if (liveEmbedding && cand.profilePhotoUrl) {
          verification = await verifyCandidate(
            cand,
            liveEmbedding,
            liveSource,
            cvServiceUrl,
            faceVerifyThreshold,
          );
          verifications.set(cand.candidateId, verification);
        }
        cand.matchScore = combineScores({ clue, candidate: cand, verification });
      }

      candidates.sort((a, b) => b.matchScore - a.matchScore);
      const best = pickBest(candidates);
      const bestVerification = best
        ? verifications.get(best.candidateId) ?? null
        : null;

      // 4. Best-effort: backfill the chosen candidate's email.
      let chosen = best;
      if (chosen && !chosen.email) {
        chosen = await enrichContactDetails(chosen, { config: fiber });
        if (best) {
          best.email = chosen.email;
        }
      }

      const status = decideStatus({
        clue,
        best,
        verification: bestVerification,
        hadCandidates: true,
        minOcrConfidence,
      });

      return finish(status, clue, candidates, best, bestVerification);
    } catch (err) {
      const result: IdentityResolveResult = {
        trackId,
        status: "error",
        clue: null,
        candidates: [],
        bestCandidate: null,
        verification: null,
        message: err instanceof Error ? err.message : String(err),
        latencyMs: Date.now() - start,
      };
      await safeLog(ctx, result, transcript);
      return result;
    }
  },
});

/** Append a debug row for an identity resolution. Text + scores only. */
export const recordLookup = internalMutation({
  args: {
    trackId: v.string(),
    status: v.string(),
    transcript: v.optional(v.union(v.string(), v.null())),
    clueName: v.optional(v.union(v.string(), v.null())),
    clueCompany: v.optional(v.union(v.string(), v.null())),
    ocrConfidence: v.optional(v.union(v.number(), v.null())),
    candidateCount: v.number(),
    selectedCandidateId: v.optional(v.union(v.string(), v.null())),
    selectedName: v.optional(v.union(v.string(), v.null())),
    selectedLinkedin: v.optional(v.union(v.string(), v.null())),
    verificationScore: v.optional(v.union(v.number(), v.null())),
    verified: v.optional(v.union(v.boolean(), v.null())),
    latencyMs: v.optional(v.union(v.number(), v.null())),
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    await ctx.db.insert("identityLookups", {
      ...args,
      createdAt: Date.now(),
    });
    return null;
  },
});
