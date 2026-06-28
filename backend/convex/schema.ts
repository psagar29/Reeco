/**
 * Convex schema for the Recco backend.
 *
 *   people         - the enrolled demo roster (+ server-side face embeddings)
 *   appState       - the single reactive BrainState the iOS app subscribes to
 *   faceMatches    - append-only log of match attempts (debugging / analytics)
 *   drafts         - generated openers (history; latest wins on read)
 *   identityLookups- append-only debug log of "find info on him" resolutions
 *                    (extracted text + scores only; NEVER raw images)
 */

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  brainStateValidator,
  faceMatchResultValidator,
  filterCommandValidator,
  personLinksValidator,
} from "./validators.js";

export default defineSchema({
  people: defineTable({
    // Stable contract id (e.g. "person_ava_shah"). Distinct from Convex _id.
    personId: v.string(),
    name: v.string(),
    role: v.string(),
    company: v.string(),
    avatarUrl: v.optional(v.string()),
    bio: v.string(),
    tags: v.array(v.string()),
    links: personLinksValidator,
    whyTalk: v.string(),
    openerSeed: v.optional(v.string()),
    // Server-side only; never returned to iOS.
    faceEmbedding: v.optional(v.union(v.array(v.number()), v.null())),
  }).index("by_personId", ["personId"]),

  // Singleton document; `key` is always "singleton".
  appState: defineTable({
    key: v.string(),
    ...brainStateValidator.fields,
  }).index("by_key", ["key"]),

  faceMatches: defineTable({
    trackId: v.string(),
    result: faceMatchResultValidator,
    source: v.optional(v.string()),
    createdAt: v.number(),
  }).index("by_trackId", ["trackId"]),

  drafts: defineTable({
    personId: v.string(),
    subject: v.optional(v.union(v.string(), v.null())),
    opener: v.string(),
    email: v.optional(v.union(v.string(), v.null())),
    source: v.optional(v.string()),
    generatedAt: v.number(),
  }).index("by_personId", ["personId"]),

  // Debug log for identity resolution. Stores only extracted text + scores so
  // a demo can be inspected after the fact; raw face/badge images are NEVER
  // persisted.
  identityLookups: defineTable({
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
    createdAt: v.number(),
  }).index("by_trackId", ["trackId"]),
});

// Re-export so callers can build args that match the stored filter shape.
export { filterCommandValidator };
