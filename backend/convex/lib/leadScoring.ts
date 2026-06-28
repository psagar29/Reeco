/**
 * Lead scoring — pure, framework-free, deterministic.
 *
 * Scores a saved scan memory against the user's mission and produces a priority
 * bucket (hot / warm / cold / needs_info), a 0-100 score, human-readable reasons,
 * a suggested next action, and any missing info. Determinism is the contract:
 * the same memory + mission always yields the same priority. OpenAI may later
 * polish *wording*, but the priority never depends on an LLM (spec PART 3).
 */

import type { MissionProfile, PreferredAction } from "./mission.js";

export type LeadPriority = "hot" | "warm" | "cold" | "needs_info";

export type LeadScore = {
  priority: LeadPriority;
  score: number; // clamped 0-100
  reasons: string[];
  nextAction: PreferredAction;
  missingInfo: string[];
  scoredAt: number;
};

/** The subset of a scan memory the scorer reads. */
export type ScorableMemory = {
  name?: string | null;
  headline?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  linkedinUrl?: string | null;
  email?: string | null;
  /** "verified" | "possible" | "needs_confirmation" | "unknown". */
  confidence?: string | null;
  notes?: string | null;
  badgeText?: string | null;
  transcript?: string | null;
  scanCount?: number | null;
  sources?: string[] | null;
};

function clean(s?: string | null): string {
  return (s ?? "").trim();
}

function has(s?: string | null): boolean {
  return clean(s).length > 0;
}

/** Phrases that signal the user wants this person prioritized. */
const HIGH_PRIORITY_CUES = [
  "high priority",
  "must follow",
  "follow up",
  "important",
  "key contact",
  "priority",
  "great fit",
  "perfect fit",
  "love to",
  "definitely",
  "top of list",
];

/** Phrases that signal the user wants this person dropped. */
const NOT_RELEVANT_CUES = [
  "not relevant",
  "not a fit",
  "ignore",
  "skip",
  "no thanks",
  "not interested",
  "irrelevant",
  "archive",
];

/** Goal-specific strong-signal role keywords and the points they earn. */
const GOAL_SIGNALS: Record<
  string,
  { needles: string[]; points: number; reason: string }
> = {
  fundraising: {
    needles: ["investor", "venture", "vc", "partner", "angel", "capital", "fund", "lp"],
    points: 35,
    reason: "Matches your investor mission",
  },
  get_hired: {
    needles: ["recruiter", "hiring", "talent", "people ops", "engineering manager", "head of"],
    points: 35,
    reason: "Recruiter / hiring signal — matches your search",
  },
  sponsors: {
    needles: ["sponsor", "partnership", "partnerships", "community", "devrel", "brand", "marketing"],
    points: 30,
    reason: "Sponsorship / partnerships match",
  },
};

/** Founder-ish signal helps fundraising, customers, founders, cofounder goals. */
const FOUNDER_NEEDLES = ["founder", "co-founder", "cofounder", "ceo", "cto"];
const FOUNDER_GOALS = new Set(["fundraising", "customers", "founders", "cofounder"]);

function chooseNextAction(
  mission: MissionProfile | null,
  hasLinkedIn: boolean,
  hasEmail: boolean,
  needsInfo: boolean,
): PreferredAction {
  if (needsInfo) return "reminder";
  if (mission) {
    if (mission.preferredAction === "linkedin_dm" && !hasLinkedIn && hasEmail) return "cold_email";
    if (mission.preferredAction === "cold_email" && !hasEmail && hasLinkedIn) return "linkedin_dm";
    return mission.preferredAction;
  }
  if (hasLinkedIn) return "linkedin_dm";
  if (hasEmail) return "cold_email";
  return "in_person";
}

function bucketize(score: number, missingInfo: string[]): LeadPriority {
  if (score >= 75) return "hot";
  if (score >= 45) return "warm";
  if (score >= 15) return "cold";
  // Below 15: needs_info if we're actually missing identifying signal.
  return missingInfo.length > 0 ? "needs_info" : "cold";
}

/**
 * Score one memory against a mission (or null for "no mission yet"). Always
 * returns a complete, clamped `LeadScore`.
 */
export function scoreLead(
  memory: ScorableMemory,
  mission: MissionProfile | null,
  now: number,
): LeadScore {
  const reasons: string[] = [];
  const missingInfo: string[] = [];
  let score = 0;

  const confidence = clean(memory.confidence) || "unknown";
  const hasLinkedIn = has(memory.linkedinUrl);
  const hasEmail = has(memory.email);
  const hasName = has(memory.name);
  const scanCount = memory.scanCount ?? 1;

  // --- Base signal -----------------------------------------------------------
  if (confidence === "verified") {
    score += 20;
    reasons.push("Verified identity");
  } else if (confidence === "possible") {
    score += 8;
    reasons.push("Possible identity");
  } else if (confidence === "needs_confirmation") {
    score -= 15;
    reasons.push("Needs confirmation before follow-up");
  }

  if (hasLinkedIn) {
    score += 15;
    reasons.push("LinkedIn profile found");
  }
  if (hasEmail) {
    score += 10;
    reasons.push("Email found");
  }
  if (scanCount > 1) {
    score += 5;
    reasons.push(`Scanned ${scanCount} times`);
  }
  if (has(memory.notes)) {
    score += 8;
    reasons.push("You added notes");
  }

  // --- Mission matching ------------------------------------------------------
  const haystack = [
    memory.role,
    memory.headline,
    memory.company,
    memory.school,
    memory.badgeText,
  ]
    .map(clean)
    .join(" ")
    .toLowerCase();

  if (mission) {
    const roleHit = mission.targetRoles.find((r) => r && haystack.includes(r.toLowerCase()));
    if (roleHit) {
      score += 25;
      reasons.push(`Matches target role: ${roleHit}`);
    }

    const keywordHit = mission.targetKeywords.find(
      (k) => k && haystack.includes(k.toLowerCase()),
    );
    if (keywordHit) {
      score += 20;
      reasons.push(`Keyword match: ${keywordHit}`);
    }

    const companyHit = mission.targetCompanies.find(
      (c) => c && haystack.includes(c.toLowerCase()),
    );
    if (companyHit) {
      score += 15;
      reasons.push(`Target company: ${companyHit}`);
    }

    const industryHit = mission.targetIndustries.find(
      (i) => i && haystack.includes(i.toLowerCase()),
    );
    if (industryHit) {
      score += 15;
      reasons.push(`Industry match: ${industryHit}`);
    }

    const signal = GOAL_SIGNALS[mission.goalType];
    if (signal && signal.needles.some((n) => haystack.includes(n))) {
      score += signal.points;
      reasons.push(signal.reason);
    }

    if (FOUNDER_GOALS.has(mission.goalType) && FOUNDER_NEEDLES.some((n) => haystack.includes(n))) {
      score += 15;
      reasons.push("Founder keyword in headline");
    }
  }

  // --- Explicit user intent in notes/transcript ------------------------------
  const intentText = `${clean(memory.notes)} ${clean(memory.transcript)}`.toLowerCase();
  const flaggedNotRelevant = NOT_RELEVANT_CUES.some((c) => intentText.includes(c));
  const flaggedHigh = HIGH_PRIORITY_CUES.some((c) => intentText.includes(c));

  if (flaggedHigh && !flaggedNotRelevant) {
    score += 30;
    reasons.push("You flagged this as high priority");
  }

  // --- Missing info ----------------------------------------------------------
  if (!hasName) missingInfo.push("No name resolved");
  if (!hasLinkedIn && !hasEmail) missingInfo.push("No contact link found");
  if (confidence === "needs_confirmation" || confidence === "unknown") {
    missingInfo.push("Identity needs confirmation");
  }

  // --- Resolve priority ------------------------------------------------------
  score = Math.max(0, Math.min(100, Math.round(score)));

  let priority: LeadPriority;
  if (flaggedNotRelevant) {
    priority = "cold";
    reasons.push("Marked not relevant — suggest archive");
  } else {
    priority = bucketize(score, missingInfo);
  }

  if (reasons.length === 0) reasons.push("Not enough signal yet");

  const nextAction = chooseNextAction(
    mission,
    hasLinkedIn,
    hasEmail,
    priority === "needs_info",
  );

  return { priority, score, reasons, nextAction, missingInfo, scoredAt: now };
}
