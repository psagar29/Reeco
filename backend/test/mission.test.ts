import { describe, it, expect } from "vitest";
import {
  parseMissionFallback,
  sanitizeMission,
  defaultMission,
  detectIndustries,
  missionLabel,
  type MissionProfile,
} from "../convex/lib/mission.js";
import {
  scoreLead,
  type ScorableMemory,
} from "../convex/lib/leadScoring.js";
import {
  mergeMemory,
  applyLeadFields,
  type ScanMemoryFields,
} from "../convex/lib/scanMemory.js";
import { buildOutreachOffline, missionAngle } from "../convex/lib/outreach.js";
import {
  parseMissionParseRequest,
  parseMissionCurrentRequest,
  parseScoreRequest,
  parseFollowUpStatusRequest,
  parseScanMemoryUpsertRequest,
  HttpError,
} from "../convex/lib/http.js";

const NOW = 1_000;

function memory(partial: Partial<ScorableMemory>): ScorableMemory {
  return { confidence: "possible", scanCount: 1, sources: [], ...partial };
}

function scorableOf(fields: ScanMemoryFields, notes: string | null = null): ScorableMemory {
  return {
    name: fields.name,
    headline: fields.headline,
    role: fields.role,
    company: fields.company,
    school: fields.school,
    linkedinUrl: fields.linkedinUrl,
    email: fields.email,
    confidence: fields.confidence,
    notes,
    badgeText: fields.badgeText,
    scanCount: fields.scanCount,
    sources: fields.sources,
  };
}

// ---------------------------------------------------------------------------
// Mission parsing (fallback)
// ---------------------------------------------------------------------------

describe("parseMissionFallback", () => {
  it("maps 'looking for investors' to fundraising with investor roles", () => {
    const m = parseMissionFallback("looking for investors", NOW);
    expect(m.goalType).toBe("fundraising");
    expect(m.targetRoles).toContain("investor");
    expect(m.targetKeywords).toEqual(expect.arrayContaining(["venture", "seed"]));
    expect(m.preferredAction).toBe("linkedin_dm");
  });

  it("maps 'trying to get hired' to get_hired with recruiter roles", () => {
    const m = parseMissionFallback("trying to get hired", NOW);
    expect(m.goalType).toBe("get_hired");
    expect(m.targetRoles).toEqual(
      expect.arrayContaining(["recruiter", "hiring manager"]),
    );
  });

  it("maps sponsors / founders / customers", () => {
    expect(parseMissionFallback("looking for sponsors", NOW).goalType).toBe("sponsors");
    expect(parseMissionFallback("find founders", NOW).goalType).toBe("founders");
    expect(parseMissionFallback("looking for design partners", NOW).goalType).toBe(
      "customers",
    );
  });

  it("tags industries: 'looking for AI infra founders'", () => {
    const m = parseMissionFallback("looking for AI infra founders", NOW);
    expect(m.goalType).toBe("founders");
    expect(m.targetIndustries).toEqual(expect.arrayContaining(["ai", "infra"]));
  });

  it("does not falsely tag 'ai' inside 'fundraising'", () => {
    expect(detectIndustries("fundraising for my startup")).not.toContain("ai");
  });

  it("falls back to networking for empty/unknown input", () => {
    const empty = parseMissionFallback("", NOW);
    expect(empty.goalType).toBe("networking");
    expect(empty.rawText).toBe("General networking");
    expect(parseMissionFallback("qwerty zzz", NOW).goalType).toBe("networking");
  });

  it("defaultMission is networking", () => {
    expect(defaultMission(NOW).goalType).toBe("networking");
  });

  it("missionLabel gives a short human label", () => {
    expect(missionLabel({ goalType: "fundraising", rawText: "x" })).toBe("Investors");
    expect(missionLabel({ goalType: "get_hired", rawText: "x" })).toBe("Get hired");
  });
});

describe("sanitizeMission", () => {
  it("fills missing fields from the deterministic fallback", () => {
    const m = sanitizeMission({ goalType: "sponsors" }, "looking for sponsors", NOW);
    expect(m.goalType).toBe("sponsors");
    expect(m.targetRoles.length).toBeGreaterThan(0);
    expect(m.preferredAction).toBe("cold_email");
  });

  it("ignores garbage and returns a complete fallback", () => {
    const m = sanitizeMission(42, "find founders", NOW);
    expect(m.goalType).toBe("founders");
  });
});

// ---------------------------------------------------------------------------
// Lead scoring
// ---------------------------------------------------------------------------

describe("scoreLead", () => {
  it("fundraising: an investor with LinkedIn is a hot lead", () => {
    const mission = parseMissionFallback("looking for investors", NOW);
    const m = memory({
      name: "Ava Shah",
      role: "Partner",
      headline: "Partner at Sequoia",
      company: "Sequoia",
      confidence: "verified",
      linkedinUrl: "https://linkedin.com/in/ava",
    });
    const s = scoreLead(m, mission, NOW);
    expect(s.priority).toBe("hot");
    expect(s.score).toBeGreaterThanOrEqual(75);
    expect(s.reasons).toContain("Matches your investor mission");
  });

  it("get_hired: a recruiter is a hot lead", () => {
    const mission = parseMissionFallback("trying to get hired", NOW);
    const m = memory({
      name: "Rae Kim",
      role: "Technical Recruiter",
      headline: "Recruiter at Stripe",
      company: "Stripe",
      confidence: "possible",
      linkedinUrl: "https://linkedin.com/in/rae",
    });
    const s = scoreLead(m, mission, NOW);
    expect(s.priority).toBe("hot");
    expect(s.reasons.join(" ")).toContain("Recruiter");
  });

  it("sponsors: a partnerships lead is hot/warm", () => {
    const mission = parseMissionFallback("looking for sponsors", NOW);
    const m = memory({
      name: "Pat Lee",
      role: "Head of Partnerships",
      headline: "Partnerships at AWS",
      company: "AWS",
      confidence: "verified",
      linkedinUrl: "https://linkedin.com/in/pat",
    });
    const s = scoreLead(m, mission, NOW);
    expect(["hot", "warm"]).toContain(s.priority);
    expect(s.reasons.join(" ").toLowerCase()).toContain("sponsorship");
  });

  it("no mission: still produces a valid, deterministic score", () => {
    const m = memory({
      name: "Sam Doe",
      confidence: "verified",
      linkedinUrl: "https://linkedin.com/in/sam",
    });
    const s = scoreLead(m, null, NOW);
    expect(["hot", "warm", "cold", "needs_info"]).toContain(s.priority);
    expect(s.reasons.length).toBeGreaterThan(0);
    expect(s.scoredAt).toBe(NOW);
  });

  it("needs_info when there is no name or contact", () => {
    const s = scoreLead(memory({ confidence: "unknown" }), null, NOW);
    expect(s.priority).toBe("needs_info");
    expect(s.missingInfo).toEqual(
      expect.arrayContaining(["No name resolved", "No contact link found"]),
    );
  });

  it("notes flagged 'not relevant' force cold + archive hint", () => {
    const m = memory({
      name: "Lin",
      confidence: "verified",
      linkedinUrl: "https://linkedin.com/in/lin",
      notes: "not relevant, ignore",
    });
    const s = scoreLead(m, null, NOW);
    expect(s.priority).toBe("cold");
    expect(s.reasons.join(" ")).toContain("Marked not relevant");
  });

  it("notes flagged 'high priority' boost the score", () => {
    const mission = parseMissionFallback("networking", NOW);
    const base = scoreLead(memory({ name: "Jo", confidence: "verified", linkedinUrl: "https://linkedin.com/in/jo" }), mission, NOW);
    const boosted = scoreLead(
      memory({ name: "Jo", confidence: "verified", linkedinUrl: "https://linkedin.com/in/jo", notes: "high priority, great fit" }),
      mission,
      NOW,
    );
    expect(boosted.score).toBeGreaterThan(base.score);
    expect(boosted.reasons.join(" ")).toContain("high priority");
  });
});

// ---------------------------------------------------------------------------
// Upsert scoring composition (merge -> score -> applyLeadFields)
// ---------------------------------------------------------------------------

describe("applyLeadFields (upsert scoring path)", () => {
  it("scores a freshly-merged memory and preserves follow-up state", () => {
    const fields = mergeMemory(
      null,
      {
        scanId: "trk_1",
        status: "verified",
        name: "Ava Shah",
        role: "Partner",
        company: "Sequoia",
        linkedinUrl: "https://linkedin.com/in/ava-shah",
      },
      NOW,
    );
    const mission = parseMissionFallback("looking for investors", NOW);
    const s = scoreLead(scorableOf(fields), mission, NOW);
    const scored = applyLeadFields(fields, s, {
      goalType: mission.goalType,
      rawText: mission.rawText,
    });

    expect(scored.leadPriority).toBe("hot");
    expect(scored.leadScore).toBeGreaterThanOrEqual(75);
    expect(scored.leadReasons.length).toBeGreaterThan(0);
    expect(scored.followUpStatus).toBe("new");
    expect(scored.sentAt).toBeNull();
    expect(scored.missionSnapshot).toEqual({
      goalType: "fundraising",
      rawText: "looking for investors",
    });
  });

  it("no mission: a merged memory carries default lead fields", () => {
    const fields = mergeMemory(
      null,
      { scanId: "trk_2", status: "possible", name: "Sam" },
      NOW,
    );
    expect(fields.leadPriority).toBeNull();
    expect(fields.leadReasons).toEqual([]);
    expect(fields.followUpStatus).toBe("new");
  });
});

// ---------------------------------------------------------------------------
// Outreach mission context
// ---------------------------------------------------------------------------

describe("mission-aware outreach", () => {
  it("adds a goal-aware angle for fundraising, none for networking", () => {
    expect(missionAngle({ goalType: "fundraising" })).toContain("investor");
    expect(missionAngle({ goalType: "networking" })).toBe("");
    expect(missionAngle({})).toBe("");
  });

  it("weaves the investor angle into the offline draft", () => {
    const d = buildOutreachOffline(
      { name: "Ava", company: "Acme", eventName: "X", goalType: "fundraising" },
      NOW,
    );
    expect(d.linkedinDm).toContain("investor");
    expect(d.coldEmail).toContain("investor");
  });

  it("no goalType: output is unchanged (still references Recco + topic)", () => {
    const d = buildOutreachOffline({ name: "Ava", company: "Acme", eventName: "X" }, NOW);
    expect(d.linkedinDm).toContain("Recco");
    expect(d.coldEmail).toContain("Acme");
  });
});

// ---------------------------------------------------------------------------
// HTTP request parsers
// ---------------------------------------------------------------------------

describe("mission + lead http parsers", () => {
  it("parseMissionParseRequest requires clientId, defaults rawText", () => {
    expect(() => parseMissionParseRequest({})).toThrow(HttpError);
    expect(parseMissionParseRequest({ clientId: "c1" })).toEqual({
      clientId: "c1",
      rawText: "",
    });
    expect(parseMissionParseRequest({ clientId: "c1", rawText: "investors" })).toEqual({
      clientId: "c1",
      rawText: "investors",
    });
  });

  it("parseMissionCurrentRequest requires clientId", () => {
    expect(() => parseMissionCurrentRequest({})).toThrow(HttpError);
    expect(parseMissionCurrentRequest({ clientId: "c1" })).toEqual({ clientId: "c1" });
  });

  it("parseScoreRequest requires id + a mission object", () => {
    expect(() => parseScoreRequest({ id: "m1" })).toThrow(HttpError);
    const parsed = parseScoreRequest({
      id: "m1",
      clientId: "c1",
      mission: { rawText: "looking for investors", goalType: "fundraising" },
    });
    expect(parsed.id).toBe("m1");
    expect(parsed.mission.goalType).toBe("fundraising");
  });

  it("parseFollowUpStatusRequest validates status + parses sent payload", () => {
    expect(() => parseFollowUpStatusRequest({ id: "m1", status: "bogus" })).toThrow(HttpError);
    const sent = parseFollowUpStatusRequest({
      id: "m1",
      status: "sent",
      sentAt: 123,
      editedOutreach: {
        linkedinDm: "hi",
        coldEmailSubject: "s",
        coldEmail: "b",
        inPersonOpener: "o",
        generatedAt: 1,
      },
    });
    expect(sent.status).toBe("sent");
    expect(sent.sentAt).toBe(123);
    expect(sent.editedOutreach?.linkedinDm).toBe("hi");
  });

  it("parseScanMemoryUpsertRequest carries clientId + normalized mission", () => {
    const parsed = parseScanMemoryUpsertRequest({
      scanId: "t",
      status: "possible",
      clientId: "c1",
      mission: { rawText: "looking for investors", goalType: "fundraising" },
    });
    expect(parsed.clientId).toBe("c1");
    expect(parsed.mission?.goalType).toBe("fundraising");
    // sanitized mission is complete
    expect(parsed.mission?.targetRoles.length).toBeGreaterThan(0);
  });
});
