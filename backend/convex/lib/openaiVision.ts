/**
 * OpenAI Vision badge / name-tag reader.
 *
 * Sends a wider person/badge crop (base64) to the OpenAI vision model and asks
 * for a STRICT JSON extraction of any visible name / company / role / school.
 *
 * Runs from the BACKEND ONLY — the iOS app never holds the OpenAI key. Like
 * ./openai.ts, this module is allowed to throw on transport failure; the caller
 * (identity:resolveTarget) wraps it in try/catch and degrades to a
 * needs_clarification result.
 *
 * Everything coming back from the model is treated as untrusted and is
 * sanitized (length-clamped, control-characters stripped, confidence clamped to
 * 0..1) before it leaves this module.
 */

import type { IdentityClue } from "./types.js";

export type ReadBadgeOptions = {
  apiKey: string;
  model: string;
  /** Wider person/badge crop, base64 (no data: prefix). */
  imageBase64: string;
  imageMimeType: string;
  /** Optional user transcript/context, e.g. "find info on him". */
  transcript?: string | null;
  timeoutMs?: number;
  /** Test seam; defaults to the global fetch. */
  fetchImpl?: typeof fetch;
};

const SYSTEM_PROMPT = [
  "You are an OCR + entity-extraction engine for a networking app at a tech event.",
  "You receive ONE photo of a person, typically including a conference badge, name tag, or lanyard near their chest.",
  "Read ONLY what is actually printed/visible. Do NOT guess, infer, or invent a name that is not legible.",
  "",
  "Return a SINGLE JSON object with EXACTLY these keys:",
  "{",
  '  "rawText": string,        // all legible text you can see, joined by " | "',
  '  "personName": string|null,// the person\'s full name if a name tag is clearly legible, else null',
  '  "companyName": string|null,// employer/organization if printed, else null',
  '  "role": string|null,      // job title if printed, else null',
  '  "schoolName": string|null,// university/school if printed, else null',
  '  "confidence": number,     // 0..1, your confidence that personName is a real, correctly-read name',
  '  "evidence": string|null   // one short phrase describing where the name came from, e.g. "badge name line"',
  "}",
  "",
  "Rules:",
  "- If you cannot clearly read a name, set personName to null and confidence to a low value (< 0.4).",
  "- Never output a celebrity/placeholder name to fill the field.",
  "- Output JSON only. No prose, no markdown.",
].join("\n");

/** Clamp a number into [0,1], defaulting non-finite input to 0. */
function clamp01(n: unknown): number {
  const x = typeof n === "number" ? n : Number(n);
  if (!Number.isFinite(x)) return 0;
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

/** Sanitize a free-text field: strip control chars, collapse spaces, clamp. */
function cleanText(value: unknown, maxLen: number): string | null {
  if (typeof value !== "string") return null;
  // Drop control characters (incl. newlines/tabs), then collapse whitespace.
  // eslint-disable-next-line no-control-regex
  const stripped = value
    .replace(/[\u0000-\u001F\u007F]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!stripped) return null;
  return stripped.slice(0, maxLen);
}

/**
 * Coerce arbitrary model output into a safe IdentityClue. Exported for tests.
 */
export function sanitizeClue(raw: unknown): IdentityClue {
  const obj = (typeof raw === "object" && raw !== null ? raw : {}) as Record<
    string,
    unknown
  >;
  // Accept the spec's `personName/companyName/schoolName` keys as well as the
  // internal `fullName/company/school` spellings, so the model output maps no
  // matter which vocabulary it uses.
  const fullName = cleanText(obj.personName ?? obj.fullName, 120);
  return {
    rawText: cleanText(obj.rawText, 1000) ?? "",
    fullName,
    company: cleanText(obj.companyName ?? obj.company, 160),
    role: cleanText(obj.role, 160),
    school: cleanText(obj.schoolName ?? obj.school, 160),
    // If there is no name at all, force confidence to 0 regardless of what the
    // model claimed.
    confidence: fullName ? clamp01(obj.confidence) : 0,
    evidence: cleanText(obj.evidence, 200),
  };
}

/**
 * Read the badge/name-tag from a person/context crop. Throws on transport
 * failure (no key, HTTP error, unparseable JSON) — caller degrades gracefully.
 */
export async function readBadge(opts: ReadBadgeOptions): Promise<IdentityClue> {
  if (!opts.apiKey) throw new Error("OpenAI Vision: no API key configured");
  if (!opts.imageBase64) throw new Error("OpenAI Vision: empty image");

  const doFetch = opts.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 15000);

  try {
    const userText =
      `User context (may be empty): ${opts.transcript ?? ""}\n` +
      "Extract the person's identity from the badge/name tag. Return JSON only.";

    const res = await doFetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opts.apiKey}`,
      },
      body: JSON.stringify({
        model: opts.model,
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: userText },
              {
                type: "image_url",
                image_url: {
                  url: `data:${opts.imageMimeType};base64,${opts.imageBase64}`,
                  detail: "high",
                },
              },
            ],
          },
        ],
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`OpenAI Vision HTTP ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error("OpenAI Vision returned no content");
    return sanitizeClue(JSON.parse(content));
  } finally {
    clearTimeout(timer);
  }
}
