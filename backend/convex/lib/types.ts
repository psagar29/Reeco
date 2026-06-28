/**
 * Canonical TypeScript types for the Recco backend.
 *
 * These mirror docs/API_CONTRACTS.md exactly and are the single source of
 * truth used by both the Convex functions and the framework-free helpers in
 * this folder (so the helpers can be unit-tested with plain Node/Vitest, no
 * live Convex deployment required).
 *
 * DO NOT change these shapes without updating docs/API_CONTRACTS.md and telling
 * Persons A/C/D — the contract is frozen.
 */

/** Links block on a Person. All fields optional. */
export type PersonLinks = {
  github?: string;
  linkedin?: string;
  x?: string;
  site?: string;
};

/** A demo roster participant. `faceEmbedding` is server-side only. */
export type Person = {
  id: string;
  name: string;
  role: string;
  company: string;
  avatarUrl?: string;
  bio: string;
  tags: string[];
  links: PersonLinks;
  whyTalk: string;
  openerSeed?: string;
  faceEmbedding?: number[] | null;
};

/** Public-facing person (no embedding). What iOS receives from people:list. */
export type PublicPerson = Omit<Person, "faceEmbedding">;

/** The parsed intent from a voice/typed command. */
export type FilterCommand = {
  action: "filter" | "rank" | "reset" | "draft";
  includeTags: string[];
  excludeTags: string[];
  rankBy?: "relevance" | "infra" | "growth" | "ai" | "founder" | null;
  targetPersonId?: string | null;
  rawText?: string | null;
};

/** Basic quality data attached to a face match. */
export type FaceQuality = {
  faceDetected: boolean;
  detectionScore?: number | null;
  cropWidth?: number | null;
  cropHeight?: number | null;
  model?: string | null;
};

/** Result of attempting to match a face crop to an enrolled person. */
export type FaceMatchResult = {
  trackId: string;
  status: "matched" | "tentative" | "unknown" | "no_face" | "error";
  personId?: string | null;
  score?: number | null;
  quality?: FaceQuality | null;
  message?: string | null;
  latencyMs?: number | null;
};

/** The single reactive app state iOS subscribes to via state:get. */
export type BrainState = {
  activeFilter: FilterCommand;
  highlightedPersonId?: string | null;
  selectedPersonId?: string | null;
  visiblePersonIds: string[];
  dimmedPersonIds: string[];
  lastTranscript?: string | null;
  lastMatch?: FaceMatchResult | null;
  isThinking: boolean;
  updatedAt: number;
};

/** Result of drafting an opener for a person. */
export type DraftResult = {
  personId: string;
  subject?: string | null;
  opener: string;
  email?: string | null;
  generatedAt: number;
};

/** Output of voice:getDeepgramToken. */
export type DeepgramToken = {
  temporaryToken: string;
  expiresAt: number;
};

/** Shape returned by Person A's CV service POST /embed. */
export type EmbedResponse = {
  requestId?: string;
  faceDetected: boolean;
  embedding: number[] | null;
  quality?: FaceQuality | null;
  latencyMs?: number | null;
  error?: string | null;
};

// ---------------------------------------------------------------------------
// Identity resolution ("find info on him").
//
// The camera locks the center/largest face, captures a tight face crop (for
// face verification) plus a wider person/badge crop (for OCR). The backend
// reads the name tag with OpenAI Vision, finds candidate profiles with Fiber
// AI, and verifies a candidate's profile photo against the live face with the
// existing InsightFace CV service. iOS holds NONE of these keys.
// ---------------------------------------------------------------------------

/** A clue read off the badge/name-tag/context crop by OpenAI Vision. */
export type IdentityClue = {
  /** Raw OCR text the model saw (sanitized). */
  rawText: string;
  fullName?: string | null;
  company?: string | null;
  role?: string | null;
  school?: string | null;
  /** 0..1 model confidence that `fullName` is a real, readable name. */
  confidence: number;
  /** Short human-readable note on what the reading was based on. */
  evidence?: string | null;
};

/** A candidate identity returned by the Fiber AI person lookup. */
export type IdentityCandidate = {
  /** Stable id we mint for this candidate within one resolve call. */
  candidateId: string;
  fullName: string;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  location?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  profilePhotoUrl?: string | null;
  /** Where this candidate came from, e.g. "fiber:kitchen-sink". */
  source: string;
  /**
   * Ranking score filled in by identityScoring.combineScores. Non-verified
   * candidates fall in [0, 1]; face-verified candidates are lifted to [1, 2] so
   * they always outrank non-verified ones. Used only for ranking/debug — the
   * user-facing signal is the result `status`, never this number.
   */
  matchScore: number;
};

/** Face verification of a candidate's profile photo against the live face. */
export type FaceVerification = {
  candidateId: string;
  /** True only when a face was found in both photos AND score >= threshold. */
  verified: boolean;
  /** Cosine similarity 0..1, or null when verification could not run. */
  score?: number | null;
  threshold: number;
  faceDetected: boolean;
  message?: string | null;
};

/** Status of an identity resolution attempt. */
export type IdentityResolveStatus =
  | "verified"
  | "possible"
  | "not_found"
  | "needs_clarification"
  | "error";

/** Request to resolve the identity of the locked target (HTTP body). */
export type IdentityResolveRequest = {
  trackId: string;
  transcript?: string | null;
  /** Tight face crop, base64 (no data: prefix). May be empty in mock mode. */
  faceImageBase64: string;
  /** Wider person/badge crop, base64 (no data: prefix). */
  contextImageBase64: string;
  imageMimeType: "image/jpeg" | "image/png";
};

/** Final result of an identity resolution attempt. */
export type IdentityResolveResult = {
  trackId: string;
  status: IdentityResolveStatus;
  clue?: IdentityClue | null;
  candidates: IdentityCandidate[];
  bestCandidate?: IdentityCandidate | null;
  verification?: FaceVerification | null;
  message?: string | null;
  latencyMs?: number | null;
};
