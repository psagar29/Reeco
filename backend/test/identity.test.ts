import { describe, it, expect } from "vitest";
import { sanitizeClue } from "../convex/lib/openaiVision.js";
import { findCandidates, parseFiberPeople } from "../convex/lib/fiber.js";
import {
  textMatchScore,
  combineScores,
  decideStatus,
  pickBest,
} from "../convex/lib/identityScoring.js";
import {
  extractLinkedInProfileUrl,
  extractSpokenIdentityName,
} from "../convex/lib/transcriptName.js";
import type {
  IdentityCandidate,
  IdentityClue,
  FaceVerification,
} from "../convex/lib/types.js";

function clue(partial: Partial<IdentityClue>): IdentityClue {
  return {
    rawText: "",
    fullName: null,
    company: null,
    role: null,
    school: null,
    confidence: 0,
    evidence: null,
    ...partial,
  };
}

function candidate(partial: Partial<IdentityCandidate>): IdentityCandidate {
  return {
    candidateId: "cand_0_x",
    fullName: "X",
    headline: null,
    role: null,
    company: null,
    school: null,
    location: null,
    linkedinUrl: null,
    email: null,
    profilePhotoUrl: null,
    source: "test",
    matchScore: 0,
    ...partial,
  };
}

describe("sanitizeClue", () => {
  it("keeps a legible name and clamps confidence to [0,1]", () => {
    const c = sanitizeClue({
      rawText: "Ada Lovelace | Analytical Engines",
      fullName: "Ada Lovelace",
      company: "Analytical Engines",
      confidence: 5,
    });
    expect(c.fullName).toBe("Ada Lovelace");
    expect(c.company).toBe("Analytical Engines");
    expect(c.confidence).toBe(1);
  });

  it("forces confidence to 0 when there is no name", () => {
    const c = sanitizeClue({ fullName: null, confidence: 0.9 });
    expect(c.fullName).toBeNull();
    expect(c.confidence).toBe(0);
  });

  it("strips control characters and collapses whitespace", () => {
    const c = sanitizeClue({ rawText: "a\u0000b\n\tc   d" });
    expect(c.rawText).toBe("a b c d");
  });

  it("is safe on non-object input", () => {
    const c = sanitizeClue("garbage");
    expect(c.fullName).toBeNull();
    expect(c.confidence).toBe(0);
    expect(c.rawText).toBe("");
  });
});

describe("parseFiberPeople", () => {
  it("maps a profiles array with varied field spellings", () => {
    const out = parseFiberPeople({
      profiles: [
        {
          name: "Ada Lovelace",
          linkedin_url: "https://linkedin.com/in/ada",
          title: "Engineer",
          company: "Acme",
          profilePicUrl: "https://img/ada.jpg",
        },
      ],
    });
    expect(out).toHaveLength(1);
    expect(out[0]!.fullName).toBe("Ada Lovelace");
    expect(out[0]!.linkedinUrl).toBe("https://linkedin.com/in/ada");
    expect(out[0]!.role).toBe("Engineer");
    expect(out[0]!.company).toBe("Acme");
    expect(out[0]!.profilePhotoUrl).toBe("https://img/ada.jpg");
  });

  it("joins first/last name and reads nested envelopes", () => {
    const out = parseFiberPeople({
      result: { results: [{ first_name: "Grace", last_name: "Hopper" }] },
    });
    expect(out).toHaveLength(1);
    expect(out[0]!.fullName).toBe("Grace Hopper");
  });

  it("maps Fiber's documented output.data profile shape", () => {
    const out = parseFiberPeople({
      output: {
        data: [
          {
            name: "Ada Lovelace",
            headline: "Founder",
            primary_slug: "ada-lovelace",
            profile_pic: "https://img/ada.jpg",
            current_job: { company_name: "Analytical Engines" },
          },
        ],
      },
    });

    expect(out).toHaveLength(1);
    expect(out[0]!.fullName).toBe("Ada Lovelace");
    expect(out[0]!.linkedinUrl).toBe("https://www.linkedin.com/in/ada-lovelace");
    expect(out[0]!.company).toBe("Analytical Engines");
    expect(out[0]!.profilePhotoUrl).toBe("https://img/ada.jpg");
  });

  it("maps Fiber nlp-search output.results.people envelope", () => {
    const out = parseFiberPeople(
      {
        output: {
          results: {
            people: [
              {
                name: "Taylor Chen",
                primary_slug: "taylor-chen",
                headline: "iOS Engineer at Northwind",
                current_job: {
                  title: "iOS Engineer",
                  company_name: "Northwind",
                },
                inferred_location: {
                  formatted_address: "San Francisco, CA",
                },
                relevance_score: 309.6855,
              },
            ],
          },
        },
      },
      "fiber:nlp-search",
    );

    expect(out).toHaveLength(1);
    expect(out[0]!.fullName).toBe("Taylor Chen");
    expect(out[0]!.linkedinUrl).toBe("https://www.linkedin.com/in/taylor-chen");
    expect(out[0]!.role).toBe("iOS Engineer");
    expect(out[0]!.company).toBe("Northwind");
    expect(out[0]!.location).toBe("San Francisco, CA");
    expect(out[0]!.matchScore).toBeGreaterThan(0.7);
    expect(out[0]!.source).toBe("fiber:nlp-search");
  });

  it("returns [] for garbage and skips entries without a name", () => {
    expect(parseFiberPeople(null)).toEqual([]);
    expect(parseFiberPeople({ profiles: [{ company: "Acme" }] })).toEqual([]);
  });
});

describe("findCandidates", () => {
  it("uses natural-language profile search before falling back to Kitchen Sink", async () => {
    const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
    const fetchImpl = (async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({
        url: String(url),
        body: JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>,
      });
      const body =
        calls.length === 1
          ? { output: { data: [] } }
          : {
              output: {
                data: [
                  {
                    name: "Ada Lovelace",
                    primary_slug: "ada-lovelace",
                    profile_pic: "https://img/ada.jpg",
                  },
                ],
              },
            };
      return new Response(JSON.stringify(body), { status: 200 });
    }) as typeof fetch;

    const out = await findCandidates(
      { personName: "Ada Lovelace", companyName: "Analytical Engines" },
      {
        config: { apiKey: "test-key", baseUrl: "https://api.fiber.ai" },
        fetchImpl,
      },
    );

    expect(calls).toHaveLength(2);
    expect(calls[0]!.url).toContain("/v1/nlp-search/run");
    expect(calls[0]!.body.query).toContain("Ada Lovelace");
    expect(calls[1]!.url).toContain("/v1/kitchen-sink/person");
    expect(out).toHaveLength(1);
    expect(out[0]!.source).toBe("fiber:kitchen-sink");
    expect(out[0]!.linkedinUrl).toBe("https://www.linkedin.com/in/ada-lovelace");
  });

  it("uses an explicitly provided LinkedIn URL before profile search", async () => {
    const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
    const fetchImpl = (async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({
        url: String(url),
        body: JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>,
      });
      return new Response(
        JSON.stringify({
          output: {
            data: [
              {
                name: "Ada Lovelace",
                primary_slug: "ada-lovelace",
                profile_pic: "https://img/ada.jpg",
              },
            ],
          },
        }),
        { status: 200 },
      );
    }) as typeof fetch;

    const out = await findCandidates(
      {
        personName: "Ada Lovelace",
        linkedinUrl: "https://www.linkedin.com/in/ada-lovelace",
      },
      {
        config: { apiKey: "test-key", baseUrl: "https://api.fiber.ai" },
        fetchImpl,
      },
    );

    expect(calls).toHaveLength(1);
    expect(calls[0]!.url).toContain("/v1/kitchen-sink/person");
    expect(calls[0]!.body.profileIdentifier).toEqual({
      identifier: "linkedinUrl",
      value: "https://www.linkedin.com/in/ada-lovelace",
    });
    expect(out).toHaveLength(1);
    expect(out[0]!.linkedinUrl).toBe("https://www.linkedin.com/in/ada-lovelace");
  });
});

describe("extractSpokenIdentityName", () => {
  it("extracts an explicit name from identity commands", () => {
    expect(extractSpokenIdentityName("find info on Jordan Lee")).toBe(
      "Jordan Lee",
    );
    expect(extractSpokenIdentityName("get linkedin for Zhi Hao")).toBe(
      "Zhi Hao",
    );
    expect(extractSpokenIdentityName("look up Morgan Chen linkedin")).toBe(
      "Morgan Chen",
    );
  });

  it("ignores pronoun-only target commands", () => {
    expect(extractSpokenIdentityName("find info on him")).toBeNull();
    expect(extractSpokenIdentityName("get her linkedin")).toBeNull();
    expect(extractSpokenIdentityName("who is this person")).toBeNull();
  });
});

describe("extractLinkedInProfileUrl", () => {
  it("extracts and normalizes LinkedIn profile URLs", () => {
    expect(
      extractLinkedInProfileUrl(
        "find info on linkedin.com/in/jordan-lee-demo",
      ),
    ).toBe("https://www.linkedin.com/in/jordan-lee-demo");
    expect(
      extractLinkedInProfileUrl(
        "https://www.linkedin.com/in/dat888/",
      ),
    ).toBe("https://www.linkedin.com/in/dat888");
  });

  it("ignores non-profile text", () => {
    expect(extractLinkedInProfileUrl("find info on him")).toBeNull();
  });
});

describe("textMatchScore", () => {
  it("is 1 for an exact name match", () => {
    expect(
      textMatchScore(
        clue({ fullName: "Ada Lovelace" }),
        candidate({ fullName: "Ada Lovelace" }),
      ),
    ).toBe(1);
  });

  it("is 0 for an unrelated name", () => {
    expect(
      textMatchScore(
        clue({ fullName: "Ada Lovelace" }),
        candidate({ fullName: "Bob Smith" }),
      ),
    ).toBe(0);
  });

  it("adds a company-agreement bonus", () => {
    const base = textMatchScore(
      clue({ fullName: "Ada Lee" }),
      candidate({ fullName: "Ada Lee" }),
    );
    const withCompany = textMatchScore(
      clue({ fullName: "Ada Lee", company: "Acme Corp" }),
      candidate({ fullName: "Ada Lee", company: "Acme Corp" }),
    );
    expect(withCompany).toBeGreaterThanOrEqual(base);
  });
});

describe("combineScores", () => {
  it("returns the text score when there is no verification", () => {
    const score = combineScores({
      clue: clue({ fullName: "Ada Lovelace" }),
      candidate: candidate({ fullName: "Ada Lovelace" }),
      verification: null,
    });
    expect(score).toBeCloseTo(1, 5);
  });

  it("boosts a verified candidate above an unverified one", () => {
    const c = clue({ fullName: "Ada Lovelace" });
    const cand = candidate({ fullName: "Ada Lovelace" });
    const verified: FaceVerification = {
      candidateId: cand.candidateId,
      verified: true,
      score: 0.5,
      threshold: 0.32,
      faceDetected: true,
      message: null,
    };
    const unverified: FaceVerification = {
      ...verified,
      verified: false,
      score: 0.1,
    };
    expect(
      combineScores({ clue: c, candidate: cand, verification: verified }),
    ).toBeGreaterThan(
      combineScores({ clue: c, candidate: cand, verification: unverified }),
    );
  });
});

describe("decideStatus", () => {
  const strongClue = clue({ fullName: "Ada Lovelace", confidence: 0.9 });
  const matchCand = candidate({ fullName: "Ada Lovelace" });

  it("needs_clarification when no name or low confidence", () => {
    expect(
      decideStatus({
        clue: clue({ fullName: null, confidence: 0 }),
        best: null,
        verification: null,
        hadCandidates: false,
        minOcrConfidence: 0.45,
      }),
    ).toBe("needs_clarification");
    expect(
      decideStatus({
        clue: clue({ fullName: "Ada", confidence: 0.2 }),
        best: matchCand,
        verification: null,
        hadCandidates: true,
        minOcrConfidence: 0.45,
      }),
    ).toBe("needs_clarification");
  });

  it("not_found when there are no candidates", () => {
    expect(
      decideStatus({
        clue: strongClue,
        best: null,
        verification: null,
        hadCandidates: false,
        minOcrConfidence: 0.45,
      }),
    ).toBe("not_found");
  });

  it("possible when text matches but no face verification", () => {
    expect(
      decideStatus({
        clue: strongClue,
        best: matchCand,
        verification: null,
        hadCandidates: true,
        minOcrConfidence: 0.45,
      }),
    ).toBe("possible");
  });

  it("verified only when strong text AND face verification pass", () => {
    const verification: FaceVerification = {
      candidateId: matchCand.candidateId,
      verified: true,
      score: 0.5,
      threshold: 0.32,
      faceDetected: true,
      message: null,
    };
    expect(
      decideStatus({
        clue: strongClue,
        best: matchCand,
        verification,
        hadCandidates: true,
        minOcrConfidence: 0.45,
      }),
    ).toBe("verified");

    // Face present but failed -> never "verified".
    expect(
      decideStatus({
        clue: strongClue,
        best: matchCand,
        verification: { ...verification, verified: false },
        hadCandidates: true,
        minOcrConfidence: 0.45,
      }),
    ).toBe("possible");
  });
});

describe("pickBest", () => {
  it("returns the highest matchScore candidate or null", () => {
    expect(pickBest([])).toBeNull();
    const best = pickBest([
      candidate({ candidateId: "a", matchScore: 0.2 }),
      candidate({ candidateId: "b", matchScore: 0.8 }),
      candidate({ candidateId: "c", matchScore: 0.5 }),
    ]);
    expect(best?.candidateId).toBe("b");
  });
});
