/**
 * Outreach drafting for a saved scan memory.
 *
 * Produces three short, natural, person-specific variants — a LinkedIn DM, a
 * cold email, and an in-person follow-up opener — from the metadata we already
 * stored. Framework-free and deterministic so it can be unit-tested and used as
 * the no-API fallback. The real OpenAI path lives in `scanMemories.ts` and falls
 * back here whenever a key is missing or the call fails.
 *
 * Recco's pitch (woven in lightly, never salesy): a lightweight AR memory layer
 * for event networking.
 */

export type OutreachInput = {
  name?: string | null;
  role?: string | null;
  company?: string | null;
  school?: string | null;
  headline?: string | null;
  /** Event/hackathon name, e.g. "Orange Slice". Defaults to "the event". */
  eventName?: string | null;
  /** Sign-off name for the cold email. Omitted from the sign-off when empty. */
  senderName?: string | null;
  /** Mission goal type — adds a subtle, goal-aware angle when present. */
  goalType?: string | null;
  /** Lead priority ("hot" | "warm" | ...). Reserved for tone tuning. */
  priority?: string | null;
};

export type OutreachDraft = {
  linkedinDm: string;
  coldEmailSubject: string;
  coldEmail: string;
  inPersonOpener: string;
  generatedAt: number;
};

export function firstNameOf(name?: string | null): string {
  const n = (name ?? "").trim();
  if (!n) return "there";
  return n.split(/\s+/)[0] || "there";
}

/** A short topic phrase: the company, else the role, else a neutral fallback. */
export function topicOf(input: OutreachInput): string {
  const company = (input.company ?? "").trim();
  if (company) return company;
  const role = (input.role ?? "").trim();
  if (role) return role;
  const headline = (input.headline ?? "").trim();
  if (headline) return headline;
  return "what you're building";
}

function eventOf(input: OutreachInput): string {
  return (input.eventName ?? "").trim() || "the event";
}

/**
 * A subtle, goal-aware extra clause. Returns "" for no/networking/other goals,
 * so the no-mission output stays identical to the original deterministic draft.
 */
export function missionAngle(input: OutreachInput): string {
  switch ((input.goalType ?? "").trim()) {
    case "fundraising":
      return "I'd genuinely value your perspective as an investor as we shape our next round.";
    case "get_hired":
      return "I'm exploring my next role, and your team came to mind.";
    case "hiring":
      return "We're growing the team and I'd love to keep you in the loop.";
    case "customers":
      return "Curious whether what we're building could be useful for your team.";
    case "sponsors":
      return "Wondering if there might be a fit for a partnership down the line.";
    case "cofounder":
      return "Always keen to meet people I might end up building with.";
    case "founders":
      return "Always up for trading notes with other founders.";
    default:
      return "";
  }
}

/** Build all three outreach variants deterministically (no external calls). */
export function buildOutreachOffline(
  input: OutreachInput,
  now: number,
): OutreachDraft {
  const fn = firstNameOf(input.name);
  const topic = topicOf(input);
  const event = eventOf(input);
  const sender = (input.senderName ?? "").trim();
  const signoff = sender ? `Best,\n${sender}` : "Best";
  const angle = missionAngle(input);
  const dmAngle = angle ? ` ${angle}` : "";
  const emailAngle = angle ? `${angle}\n\n` : "";

  const linkedinDm =
    `Hey ${fn}, great meeting you at ${event}. ` +
    `Loved hearing about ${topic}.${dmAngle} We're building Recco, an AR memory layer ` +
    `for event networking — would love to compare notes.`;

  const coldEmailSubject = `Great meeting you at ${event}`;

  const coldEmail =
    `Hey ${fn},\n\n` +
    `Great meeting you at ${event}. I noticed you're working around ${topic}, ` +
    `and it connected with what we're building in Recco: a lightweight AR ` +
    `memory layer for event networking.\n\n` +
    `${emailAngle}` +
    `Would love to compare notes sometime this week.\n\n` +
    `${signoff}`;

  const inPersonOpener =
    `Hey ${fn} — good to see you again. I was just telling someone about your ` +
    `work on ${topic}. How's ${event} treating you?`;

  return { linkedinDm, coldEmailSubject, coldEmail, inPersonOpener, generatedAt: now };
}

/**
 * Validate/normalize an LLM outreach object, filling any missing/blank field
 * from the deterministic fallback so the result is always complete.
 */
export function sanitizeOutreach(
  input: unknown,
  fallback: OutreachDraft,
): OutreachDraft {
  if (!input || typeof input !== "object") return fallback;
  const obj = input as Record<string, unknown>;
  const str = (key: string, fb: string): string => {
    const v = obj[key];
    return typeof v === "string" && v.trim() ? v.trim() : fb;
  };
  return {
    linkedinDm: str("linkedinDm", fallback.linkedinDm),
    coldEmailSubject: str("coldEmailSubject", fallback.coldEmailSubject),
    coldEmail: str("coldEmail", fallback.coldEmail),
    inPersonOpener: str("inPersonOpener", fallback.inPersonOpener),
    generatedAt: fallback.generatedAt,
  };
}
