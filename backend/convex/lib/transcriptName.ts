/**
 * Extract an explicit spoken/typed person name from identity commands.
 *
 * Examples:
 *   "find info on Saahith Veeramaneni" -> "Saahith Veeramaneni"
 *   "get linkedin for Zhi Hao"         -> "Zhi Hao"
 *   "find info on him"                 -> null
 */

const BAD_TARGETS = new Set([
  "he",
  "him",
  "his",
  "she",
  "her",
  "hers",
  "them",
  "they",
  "this",
  "that",
  "person",
  "guy",
  "girl",
  "man",
  "woman",
  "target",
]);

function cleanNameCandidate(value: string): string | null {
  if (/https?:\/\/|linkedin\.com|\/in\//i.test(value)) return null;
  const cleaned = value
    .replace(/[.,!?;:()[\]{}"'`]+/g, " ")
    .replace(/\b(?:please|thanks|thank you|linkedin|profile|info|information)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return null;

  const tokens = cleaned.split(/\s+/).filter(Boolean);
  if (tokens.length === 0 || tokens.length > 5) return null;

  const lower = tokens.map((t) => t.toLowerCase());
  if (lower.every((t) => BAD_TARGETS.has(t))) return null;
  if (lower.some((t) => BAD_TARGETS.has(t))) return null;
  if (!tokens.some((t) => /[a-z]/i.test(t))) return null;

  return tokens
    .map((t) => (t === t.toUpperCase() ? t : t[0]!.toUpperCase() + t.slice(1)))
    .join(" ");
}

export function extractSpokenIdentityName(
  transcript: string | null | undefined,
): string | null {
  if (!transcript) return null;
  const text = transcript.trim();
  if (!text) return null;

  const patterns = [
    /\bfind\s+(?:me\s+)?(?:info|information|linkedin|profile)\s+(?:on|for|about)\s+(.+)$/i,
    /\b(?:get|show|open|search|lookup|look\s+up)\s+(?:the\s+)?(?:linkedin|profile|info|information)\s+(?:of|for|on|about)\s+(.+)$/i,
    /\b(?:get|show|open|search|lookup|look\s+up)\s+(.+?)\s+(?:on\s+)?(?:linkedin|profile)$/i,
    /\bwho\s+is\s+(.+)$/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    const candidate = cleanNameCandidate(match?.[1] ?? "");
    if (candidate) return candidate;
  }

  return null;
}

export function extractLinkedInProfileUrl(
  transcript: string | null | undefined,
): string | null {
  if (!transcript) return null;
  const match = transcript.match(
    /(?:https?:\/\/)?(?:www\.)?linkedin\.com\/in\/([A-Za-z0-9_-]+)\/?/i,
  );
  const slug = match?.[1]?.trim();
  if (!slug) return null;
  return `https://www.linkedin.com/in/${slug}`;
}
