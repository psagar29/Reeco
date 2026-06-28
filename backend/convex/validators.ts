/**
 * Shared Convex value validators, kept in one place so the schema and the
 * function argument/return validators stay consistent with the frozen contract.
 */

import { v } from "convex/values";

/** Validator for FilterCommand (docs/API_CONTRACTS.md). */
export const filterCommandValidator = v.object({
  action: v.union(
    v.literal("filter"),
    v.literal("rank"),
    v.literal("reset"),
    v.literal("draft"),
  ),
  includeTags: v.array(v.string()),
  excludeTags: v.array(v.string()),
  rankBy: v.optional(
    v.union(
      v.literal("relevance"),
      v.literal("infra"),
      v.literal("growth"),
      v.literal("ai"),
      v.literal("founder"),
      v.null(),
    ),
  ),
  targetPersonId: v.optional(v.union(v.string(), v.null())),
  rawText: v.optional(v.union(v.string(), v.null())),
});

/** Validator for FaceQuality. */
export const faceQualityValidator = v.object({
  faceDetected: v.boolean(),
  detectionScore: v.optional(v.union(v.number(), v.null())),
  cropWidth: v.optional(v.union(v.number(), v.null())),
  cropHeight: v.optional(v.union(v.number(), v.null())),
  model: v.optional(v.union(v.string(), v.null())),
});

/** Validator for FaceMatchResult. */
export const faceMatchResultValidator = v.object({
  trackId: v.string(),
  status: v.union(
    v.literal("matched"),
    v.literal("tentative"),
    v.literal("unknown"),
    v.literal("no_face"),
    v.literal("error"),
  ),
  personId: v.optional(v.union(v.string(), v.null())),
  score: v.optional(v.union(v.number(), v.null())),
  quality: v.optional(v.union(faceQualityValidator, v.null())),
  message: v.optional(v.union(v.string(), v.null())),
  latencyMs: v.optional(v.union(v.number(), v.null())),
});

/** Validator for the Person links block. */
export const personLinksValidator = v.object({
  github: v.optional(v.string()),
  linkedin: v.optional(v.string()),
  x: v.optional(v.string()),
  site: v.optional(v.string()),
});

/** Validator for a public Person (no embedding) returned to iOS. */
export const publicPersonValidator = v.object({
  id: v.string(),
  name: v.string(),
  role: v.string(),
  company: v.string(),
  avatarUrl: v.optional(v.string()),
  bio: v.string(),
  tags: v.array(v.string()),
  links: personLinksValidator,
  whyTalk: v.string(),
  openerSeed: v.optional(v.string()),
});

/** Validator for BrainState returned by state:get / state:setFilter. */
export const brainStateValidator = v.object({
  activeFilter: filterCommandValidator,
  highlightedPersonId: v.optional(v.union(v.string(), v.null())),
  selectedPersonId: v.optional(v.union(v.string(), v.null())),
  visiblePersonIds: v.array(v.string()),
  dimmedPersonIds: v.array(v.string()),
  lastTranscript: v.optional(v.union(v.string(), v.null())),
  lastMatch: v.optional(v.union(faceMatchResultValidator, v.null())),
  isThinking: v.boolean(),
  updatedAt: v.number(),
});

/** Validator for DraftResult. */
export const draftResultValidator = v.object({
  personId: v.string(),
  subject: v.optional(v.union(v.string(), v.null())),
  opener: v.string(),
  email: v.optional(v.union(v.string(), v.null())),
  generatedAt: v.number(),
});
