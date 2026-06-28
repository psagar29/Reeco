/**
 * Mission ("Today's Goal") parsing — pure, framework-free, deterministic.
 *
 * Turns a free-text event goal ("looking for investors", "trying to get hired")
 * into a structured `MissionProfile` the lead scorer can use. The Convex action
 * in `mission.ts` tries OpenAI first and falls back to `parseMissionFallback`
 * here; this module is also the offline parser used by the iOS MockBackend's
 * Swift twin. No external calls, fully testable.
 */

export type GoalType =
  | "fundraising"
  | "hiring"
  | "get_hired"
  | "customers"
  | "sponsors"
  | "cofounder"
  | "founders"
  | "networking"
  | "other";

export type PreferredAction =
  | "linkedin_dm"
  | "cold_email"
  | "in_person"
  | "reminder";

/** The structured mission. Storage adds `clientId`; this is the portable core. */
export type MissionProfile = {
  rawText: string;
  goalType: GoalType;
  targetRoles: string[];
  targetKeywords: string[];
  targetCompanies: string[];
  targetIndustries: string[];
  preferredAction: PreferredAction;
  userContext: string | null;
  tone: string;
  createdAt: number;
  updatedAt: number;
};

const DEFAULT_TONE = "warm, concise, specific";

/** Industries we can spot by name, so "AI infra founders" tags ai + infra. */
const INDUSTRY_KEYWORDS: Record<string, string[]> = {
  ai: ["ai", "a.i.", "artificial intelligence", "ml", "machine learning", "llm"],
  infra: ["infra", "infrastructure", "devops", "platform", "cloud", "kubernetes"],
  fintech: ["fintech", "payments", "banking", "finance"],
  health: ["health", "healthcare", "biotech", "medical", "bio"],
  climate: ["climate", "energy", "sustainability", "cleantech"],
  crypto: ["crypto", "web3", "blockchain", "defi"],
  devtools: ["devtools", "developer tools", "sdk", "api platform"],
  data: ["data", "analytics", "database", "warehouse"],
  security: ["security", "cyber", "infosec"],
  design: ["design", "product design", "ux", "ui"],
  hardware: ["hardware", "robotics", "devices", "chips", "semiconductor"],
  saas: ["saas", "b2b", "enterprise software"],
};

type GoalRule = {
  goalType: GoalType;
  /** Substrings that select this goal (checked in order). */
  match: string[];
  targetRoles: string[];
  targetKeywords: string[];
  preferredAction: PreferredAction;
};

/**
 * Ordered goal rules. The first whose `match` appears in the text wins, so the
 * most specific phrasings (get_hired, cofounder) sit above the broader ones.
 */
const GOAL_RULES: GoalRule[] = [
  {
    goalType: "get_hired",
    match: [
      "get hired",
      "getting hired",
      "trying to get hired",
      "looking for a job",
      "find a job",
      "get a job",
      "looking for work",
      "land a role",
      "find a role",
      "job hunting",
    ],
    targetRoles: ["recruiter", "hiring manager", "engineering manager", "founder", "head of talent"],
    targetKeywords: ["hiring", "recruiting", "open roles", "talent"],
    preferredAction: "linkedin_dm",
  },
  {
    goalType: "fundraising",
    match: [
      "investor",
      "investors",
      "raise",
      "raising",
      "fundrais",
      "venture",
      "vc",
      "angel",
      "seed round",
      "pre-seed",
      "capital",
      "lp ",
      "limited partner",
    ],
    targetRoles: ["investor", "partner", "angel", "venture partner", "general partner"],
    targetKeywords: ["venture", "seed", "fund", "capital", "angel", "portfolio"],
    preferredAction: "linkedin_dm",
  },
  {
    goalType: "cofounder",
    match: ["cofounder", "co-founder", "co founder", "technical cofounder"],
    targetRoles: ["founder", "engineer", "cto", "co-founder"],
    targetKeywords: ["cofounder", "founding", "startup", "build"],
    preferredAction: "in_person",
  },
  {
    goalType: "sponsors",
    match: [
      "sponsor",
      "sponsors",
      "sponsorship",
      "partnership",
      "partnerships",
      "community",
      "devrel",
      "developer relations",
    ],
    targetRoles: ["sponsor", "partnerships", "community", "devrel", "marketing"],
    targetKeywords: ["sponsorship", "partnership", "community", "brand", "budget"],
    preferredAction: "cold_email",
  },
  {
    goalType: "hiring",
    match: [
      "hiring",
      "recruit",
      "looking to hire",
      "find engineers",
      "find talent",
      "build my team",
      "grow my team",
    ],
    targetRoles: ["engineer", "designer", "candidate", "operator"],
    targetKeywords: ["hiring", "open to work", "candidate"],
    preferredAction: "linkedin_dm",
  },
  {
    goalType: "customers",
    match: [
      "customer",
      "customers",
      "clients",
      "design partner",
      "design partners",
      "pilot",
      "users",
      "sell",
      "selling",
      "go to market",
      "leads",
    ],
    targetRoles: ["founder", "head of", "vp", "director", "product lead", "operator"],
    targetKeywords: ["product", "pilot", "customer", "budget", "team"],
    preferredAction: "cold_email",
  },
  {
    goalType: "founders",
    match: [
      "founder",
      "founders",
      "startup founders",
      "find founders",
      "meet founders",
      "early stage",
    ],
    targetRoles: ["founder", "ceo", "co-founder", "cto"],
    targetKeywords: ["startup", "founder", "building", "early stage"],
    preferredAction: "linkedin_dm",
  },
  {
    goalType: "networking",
    match: ["network", "networking", "meet people", "make friends", "connections", "general"],
    targetRoles: [],
    targetKeywords: [],
    preferredAction: "in_person",
  },
];

function uniq(items: string[]): string[] {
  return Array.from(new Set(items.filter((s) => s && s.trim()).map((s) => s.trim())));
}

/**
 * Whether `needle` appears in `text`. Short/punctuated tokens ("ai", "ml", "vc",
 * "a.i.") require a word boundary so "fundraising" doesn't match "ai".
 */
function needleHit(text: string, needle: string): boolean {
  const n = needle.toLowerCase();
  if (n.length <= 3 || /[^a-z]/.test(n)) {
    const escaped = n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^a-z])${escaped}([^a-z]|$)`, "i").test(text);
  }
  return text.includes(n);
}

/** Detect named industries mentioned in the text. */
export function detectIndustries(text: string): string[] {
  const lower = text.toLowerCase();
  const found: string[] = [];
  for (const [industry, needles] of Object.entries(INDUSTRY_KEYWORDS)) {
    if (needles.some((n) => needleHit(lower, n))) found.push(industry);
  }
  return found;
}

/**
 * Deterministic fallback parser. Picks the first matching goal rule, augments it
 * with any detected industries, and returns a complete `MissionProfile`. Unknown
 * input becomes `networking` (never throws).
 */
export function parseMissionFallback(rawText: string, now: number): MissionProfile {
  const text = (rawText ?? "").trim();
  const lower = text.toLowerCase();

  let rule: GoalRule | undefined = GOAL_RULES.find((r) =>
    r.match.some((m) => lower.includes(m)),
  );

  // Empty or unrecognized → general networking.
  if (!text) {
    rule = GOAL_RULES.find((r) => r.goalType === "networking");
  }
  const resolved = rule ?? {
    goalType: "networking" as GoalType,
    match: [],
    targetRoles: [],
    targetKeywords: [],
    preferredAction: "in_person" as PreferredAction,
  };

  const industries = detectIndustries(lower);

  return {
    rawText: text || "General networking",
    goalType: resolved.goalType,
    targetRoles: uniq(resolved.targetRoles),
    targetKeywords: uniq([...resolved.targetKeywords, ...industries]),
    targetCompanies: [],
    targetIndustries: industries,
    preferredAction: resolved.preferredAction,
    userContext: null,
    tone: DEFAULT_TONE,
    createdAt: now,
    updatedAt: now,
  };
}

/** The default mission used when a user skips setup. */
export function defaultMission(now: number): MissionProfile {
  return parseMissionFallback("General networking", now);
}

const GOAL_TYPES: ReadonlySet<string> = new Set([
  "fundraising",
  "hiring",
  "get_hired",
  "customers",
  "sponsors",
  "cofounder",
  "founders",
  "networking",
  "other",
]);

const ACTIONS: ReadonlySet<string> = new Set([
  "linkedin_dm",
  "cold_email",
  "in_person",
  "reminder",
]);

function strArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return uniq(value.filter((x): x is string => typeof x === "string"));
}

/**
 * Validate/normalize an LLM (or external) mission object, filling any
 * missing/blank field from the deterministic fallback so the result is always a
 * complete, well-typed `MissionProfile`. Never throws.
 */
export function sanitizeMission(
  input: unknown,
  rawText: string,
  now: number,
): MissionProfile {
  const fallback = parseMissionFallback(rawText, now);
  if (!input || typeof input !== "object") return fallback;
  const obj = input as Record<string, unknown>;

  const goalType =
    typeof obj.goalType === "string" && GOAL_TYPES.has(obj.goalType)
      ? (obj.goalType as GoalType)
      : fallback.goalType;

  const preferredAction =
    typeof obj.preferredAction === "string" && ACTIONS.has(obj.preferredAction)
      ? (obj.preferredAction as PreferredAction)
      : fallback.preferredAction;

  const roles = strArray(obj.targetRoles);
  const keywords = strArray(obj.targetKeywords);

  return {
    rawText: (typeof obj.rawText === "string" && obj.rawText.trim()) || fallback.rawText,
    goalType,
    targetRoles: roles.length ? roles : fallback.targetRoles,
    targetKeywords: keywords.length ? keywords : fallback.targetKeywords,
    targetCompanies: strArray(obj.targetCompanies),
    targetIndustries: strArray(obj.targetIndustries).length
      ? strArray(obj.targetIndustries)
      : fallback.targetIndustries,
    preferredAction,
    userContext:
      typeof obj.userContext === "string" && obj.userContext.trim()
        ? obj.userContext.trim()
        : null,
    tone:
      typeof obj.tone === "string" && obj.tone.trim() ? obj.tone.trim() : fallback.tone,
    createdAt: now,
    updatedAt: now,
  };
}

/** A short human label for a mission ("Investors", "Get hired", "Sponsors"). */
export function missionLabel(mission: Pick<MissionProfile, "goalType" | "rawText">): string {
  switch (mission.goalType) {
    case "fundraising":
      return "Investors";
    case "hiring":
      return "Hiring";
    case "get_hired":
      return "Get hired";
    case "customers":
      return "Customers";
    case "sponsors":
      return "Sponsors";
    case "cofounder":
      return "Cofounder";
    case "founders":
      return "Founders";
    case "networking":
      return "Networking";
    default:
      return mission.rawText.slice(0, 24) || "Mission";
  }
}
