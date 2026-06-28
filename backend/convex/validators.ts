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

// ---------------------------------------------------------------------------
// Identity resolution ("find info on him").
// ---------------------------------------------------------------------------

/** Validator for IdentityClue. */
export const identityClueValidator = v.object({
  rawText: v.string(),
  fullName: v.optional(v.union(v.string(), v.null())),
  company: v.optional(v.union(v.string(), v.null())),
  role: v.optional(v.union(v.string(), v.null())),
  school: v.optional(v.union(v.string(), v.null())),
  confidence: v.number(),
  evidence: v.optional(v.union(v.string(), v.null())),
});

/** Validator for IdentityCandidate. */
export const identityCandidateValidator = v.object({
  candidateId: v.string(),
  fullName: v.string(),
  headline: v.optional(v.union(v.string(), v.null())),
  role: v.optional(v.union(v.string(), v.null())),
  company: v.optional(v.union(v.string(), v.null())),
  school: v.optional(v.union(v.string(), v.null())),
  location: v.optional(v.union(v.string(), v.null())),
  linkedinUrl: v.optional(v.union(v.string(), v.null())),
  email: v.optional(v.union(v.string(), v.null())),
  profilePhotoUrl: v.optional(v.union(v.string(), v.null())),
  source: v.string(),
  matchScore: v.number(),
});

/** Validator for FaceVerification. */
export const faceVerificationValidator = v.object({
  candidateId: v.string(),
  verified: v.boolean(),
  score: v.optional(v.union(v.number(), v.null())),
  threshold: v.number(),
  faceDetected: v.boolean(),
  message: v.optional(v.union(v.string(), v.null())),
});

// ---------------------------------------------------------------------------
// Brain scan memory ("event memory").
// ---------------------------------------------------------------------------

/** Validator for a generated outreach draft (3 variants). */
export const outreachDraftValidator = v.object({
  linkedinDm: v.string(),
  coldEmailSubject: v.string(),
  coldEmail: v.string(),
  inPersonOpener: v.string(),
  generatedAt: v.number(),
});

// ---------------------------------------------------------------------------
// Mission ("Today's Goal") + lead scoring.
// ---------------------------------------------------------------------------

/** The portable mission core (no storage id/clientId). */
export const missionCoreValidator = v.object({
  rawText: v.string(),
  goalType: v.string(),
  targetRoles: v.array(v.string()),
  targetKeywords: v.array(v.string()),
  targetCompanies: v.array(v.string()),
  targetIndustries: v.array(v.string()),
  preferredAction: v.string(),
  userContext: v.optional(v.union(v.string(), v.null())),
  tone: v.string(),
  createdAt: v.number(),
  updatedAt: v.number(),
});

/** Public MissionProfile returned to iOS (core + optional storage ids). */
export const missionProfileValidator = v.object({
  id: v.optional(v.union(v.string(), v.null())),
  clientId: v.optional(v.union(v.string(), v.null())),
  ...missionCoreValidator.fields,
});

/** Compact mission snapshot stored on a scored memory (for display context). */
export const missionSnapshotValidator = v.object({
  goalType: v.string(),
  rawText: v.string(),
});

/** Validator for a computed LeadScore. */
export const leadScoreValidator = v.object({
  priority: v.string(),
  score: v.number(),
  reasons: v.array(v.string()),
  nextAction: v.string(),
  missingInfo: v.array(v.string()),
  scoredAt: v.number(),
});

/**
 * Validator for a public scan memory returned to iOS. `id` is the Convex
 * document id as a string. Dedup keys are NOT exposed. Metadata/links/scores
 * only — never raw images.
 */
export const scanMemoryValidator = v.object({
  id: v.string(),
  scanId: v.string(),
  personId: v.optional(v.union(v.string(), v.null())),
  name: v.optional(v.union(v.string(), v.null())),
  headline: v.optional(v.union(v.string(), v.null())),
  role: v.optional(v.union(v.string(), v.null())),
  company: v.optional(v.union(v.string(), v.null())),
  school: v.optional(v.union(v.string(), v.null())),
  linkedinUrl: v.optional(v.union(v.string(), v.null())),
  email: v.optional(v.union(v.string(), v.null())),
  confidence: v.string(),
  confidenceScore: v.optional(v.union(v.number(), v.null())),
  sources: v.array(v.string()),
  notes: v.optional(v.union(v.string(), v.null())),
  badgeText: v.optional(v.union(v.string(), v.null())),
  outreach: v.optional(v.union(outreachDraftValidator, v.null())),
  firstScannedAt: v.number(),
  lastScannedAt: v.number(),
  scanCount: v.number(),
  // Mission-driven lead scoring (always present in the public projection;
  // older rows default to new/empty via the projection, never crash).
  clientId: v.optional(v.union(v.string(), v.null())),
  leadPriority: v.optional(v.union(v.string(), v.null())),
  leadScore: v.optional(v.union(v.number(), v.null())),
  leadReasons: v.array(v.string()),
  nextAction: v.optional(v.union(v.string(), v.null())),
  followUpStatus: v.string(),
  sentAt: v.optional(v.union(v.number(), v.null())),
  editedOutreach: v.optional(v.union(outreachDraftValidator, v.null())),
  missionSnapshot: v.optional(v.union(missionSnapshotValidator, v.null())),
});

/** Validator for IdentityResolveResult (response of /api/identity/resolve). */
export const identityResolveResultValidator = v.object({
  trackId: v.string(),
  status: v.union(
    v.literal("verified"),
    v.literal("possible"),
    v.literal("not_found"),
    v.literal("needs_clarification"),
    v.literal("error"),
  ),
  clue: v.optional(v.union(identityClueValidator, v.null())),
  candidates: v.array(identityCandidateValidator),
  bestCandidate: v.optional(v.union(identityCandidateValidator, v.null())),
  verification: v.optional(v.union(faceVerificationValidator, v.null())),
  message: v.optional(v.union(v.string(), v.null())),
  latencyMs: v.optional(v.union(v.number(), v.null())),
});
