import { describe, it, expect } from "vitest";
import { sanitizeClue } from "../convex/lib/openaiVision.js";
import { parseFiberPeople } from "../convex/lib/fiber.js";
import {
  textMatchScore,
  combineScores,
  decideStatus,
  pickBest,
} from "../convex/lib/identityScoring.js";
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

  it("returns [] for garbage and skips entries without a name", () => {
    expect(parseFiberPeople(null)).toEqual([]);
    expect(parseFiberPeople({ profiles: [{ company: "Acme" }] })).toEqual([]);
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
