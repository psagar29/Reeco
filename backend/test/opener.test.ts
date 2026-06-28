import { describe, it, expect } from "vitest";
import { buildOpenerOffline, sanitizeDraft, topicForPerson } from "../convex/lib/opener.js";
import { DEMO_PEOPLE } from "../convex/lib/demoRoster.js";
import { decodeMatchMarker, makeMockImageBase64, mockEmbeddingForImage } from "../convex/lib/mockEmbeddings.js";

const ava = DEMO_PEOPLE.find((p) => p.id === "person_ava_shah")!;
const NOW = 1782522000000;

describe("buildOpenerOffline", () => {
  it("produces a short, person-specific, contract-shaped draft", () => {
    const d = buildOpenerOffline(ava, null, NOW);
    expect(d.personId).toBe("person_ava_shah");
    expect(d.generatedAt).toBe(NOW);
    expect(d.opener.startsWith("Hey Ava,")).toBe(true);
    expect(d.opener.length).toBeGreaterThan(20);
    expect(d.opener.length).toBeLessThan(400);
    expect(typeof d.subject).toBe("string");
    expect(d.email).toContain("Ava");
  });

  it("incorporates a user goal when provided", () => {
    const d = buildOpenerOffline(ava, "raising a seed round", NOW);
    expect(d.opener.toLowerCase()).toContain("raising a seed round");
  });

  it("picks a sensible subject topic per person", () => {
    expect(topicForPerson(ava)).toBe("AI infra");
    expect(topicForPerson(DEMO_PEOPLE.find((p) => p.id === "person_sam_rivera")!)).toBe("early growth");
  });
});

describe("sanitizeDraft (LLM draft clamping)", () => {
  it("accepts a valid object", () => {
    const d = sanitizeDraft({ subject: "Hi", opener: "Hey there", email: "Hey there\n\nCheers" }, ava, NOW);
    expect(d).not.toBeNull();
    expect(d!.opener).toBe("Hey there");
  });
  it("rejects an object with no opener", () => {
    expect(sanitizeDraft({ subject: "Hi" }, ava, NOW)).toBeNull();
    expect(sanitizeDraft(null, ava, NOW)).toBeNull();
  });
});

describe("mock demo image markers", () => {
  it("round-trips a person id through a base64 demo image", () => {
    const b64 = makeMockImageBase64("person_omar_wilson");
    expect(decodeMatchMarker(b64)).toBe("person_omar_wilson");
    expect(mockEmbeddingForImage(b64).markerPersonId).toBe("person_omar_wilson");
  });
  it("returns null marker for a non-marked image", () => {
    expect(decodeMatchMarker("/9j/4AAQSkZJRgABAQAAAQABAAD")).toBeNull();
  });
});
