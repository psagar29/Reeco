import { describe, it, expect } from "vitest";
import {
  parseCommandOffline,
  sanitizeFilterCommand,
  resolveTargetPerson,
} from "../convex/lib/voiceParser.js";
import { extractTags, sanitizeTags, canonicalizeTag } from "../convex/lib/tags.js";
import { DEMO_PEOPLE } from "../convex/lib/demoRoster.js";

const roster = DEMO_PEOPLE.map((p) => ({ id: p.id, name: p.name }));

describe("extractTags / tag vocabulary", () => {
  it("maps natural language to canonical vocabulary tags", () => {
    expect(extractTags("show me ai founders")).toEqual(["AI", "Founder"]);
    expect(extractTags("anyone doing infrastructure or devops?")).toEqual(["Infra"]);
    expect(extractTags("machine learning and retrieval")).toEqual(["ML", "Search"]);
    expect(extractTags("go-to-market and growth")).toEqual(["Growth", "GoToMarket"]);
  });

  it("canonicalizes loose casing and rejects junk", () => {
    expect(canonicalizeTag("ai")).toBe("AI");
    expect(canonicalizeTag("FOUNDER")).toBe("Founder");
    expect(canonicalizeTag("wizardry")).toBeNull();
    expect(sanitizeTags(["ai", "founder", "nope", "AI"])).toEqual(["AI", "Founder"]);
  });
});

describe("parseCommandOffline — the 5 frozen demo phrases", () => {
  it('1) "Show me AI founders." -> filter [AI, Founder]', () => {
    const c = parseCommandOffline("Show me AI founders.", roster);
    expect(c.action).toBe("filter");
    expect(c.includeTags).toEqual(["AI", "Founder"]);
    expect(c.excludeTags).toEqual([]);
    expect(c.rankBy).toBe("relevance");
    expect(c.rawText).toBe("Show me AI founders.");
  });

  it('2) "Who should I talk to about infra?" -> rank [Infra]', () => {
    const c = parseCommandOffline("Who should I talk to about infra?", roster);
    expect(c.action).toBe("rank");
    expect(c.includeTags).toEqual(["Infra"]);
    expect(c.rankBy).toBe("infra");
  });

  it('3) "Only growth people." -> filter [Growth]', () => {
    const c = parseCommandOffline("Only growth people.", roster);
    expect(c.action).toBe("filter");
    expect(c.includeTags).toEqual(["Growth"]);
  });

  it('4) "Draft an opener for Ava." -> draft, target resolved', () => {
    const c = parseCommandOffline("Draft an opener for Ava.", roster);
    expect(c.action).toBe("draft");
    expect(c.targetPersonId).toBe("person_ava_shah");
  });

  it('5) "Reset." -> reset, empty tags', () => {
    const c = parseCommandOffline("Reset.", roster);
    expect(c.action).toBe("reset");
    expect(c.includeTags).toEqual([]);
    expect(c.excludeTags).toEqual([]);
    expect(c.rankBy).toBeNull();
  });
});

describe("parseCommandOffline — extras", () => {
  it("handles exclude phrasing", () => {
    const c = parseCommandOffline("show me ai people without growth", roster);
    expect(c.includeTags).toContain("AI");
    expect(c.excludeTags).toContain("Growth");
    expect(c.includeTags).not.toContain("Growth");
  });

  it("resolves draft targets by full or first name", () => {
    expect(parseCommandOffline("write to Miles Chen", roster).targetPersonId).toBe("person_miles_chen");
    expect(parseCommandOffline("draft an intro for omar", roster).targetPersonId).toBe("person_omar_wilson");
    expect(parseCommandOffline("draft an opener", roster).targetPersonId).toBeNull();
  });

  it("defaults unknown commands to a filter", () => {
    expect(parseCommandOffline("hello there", roster).action).toBe("filter");
  });
});

describe("resolveTargetPerson", () => {
  it("returns null when no roster name appears", () => {
    expect(resolveTargetPerson("draft for nobody", roster)).toBeNull();
  });
});

describe("sanitizeFilterCommand (LLM output clamping)", () => {
  it("clamps tags to the vocabulary and validates fields", () => {
    const c = sanitizeFilterCommand(
      {
        action: "filter",
        includeTags: ["ai", "founder", "totally-invalid"],
        excludeTags: ["growth"],
        rankBy: "relevance",
        targetPersonId: "",
        rawText: "show me ai founders",
      },
      "fallback",
    );
    expect(c.includeTags).toEqual(["AI", "Founder"]);
    expect(c.excludeTags).toEqual(["Growth"]);
    expect(c.targetPersonId).toBeNull();
    expect(c.rawText).toBe("show me ai founders");
  });

  it("falls back to safe defaults for garbage", () => {
    const c = sanitizeFilterCommand({ action: "explode", rankBy: "wizard" }, "raw");
    expect(c.action).toBe("filter");
    expect(c.rankBy).toBeNull();
    expect(c.includeTags).toEqual([]);
    expect(c.rawText).toBe("raw");
  });

  it("dedupes a tag that appears in both include and exclude", () => {
    const c = sanitizeFilterCommand({ includeTags: ["AI"], excludeTags: ["AI"] }, "raw");
    expect(c.includeTags).toEqual(["AI"]);
    expect(c.excludeTags).toEqual([]);
  });
});
