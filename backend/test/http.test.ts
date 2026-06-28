import { describe, it, expect } from "vitest";
import {
  HttpError,
  CORS_HEADERS,
  jsonResponse,
  errorResponse,
  optionsResponse,
  parseFilterRequest,
  parseInterpretRequest,
  parseOpenerRequest,
  parseMatchFaceRequest,
  parseIdentityResolveRequest,
  sanitizeMatchResult,
} from "../convex/lib/http.js";
import type { FaceMatchResult } from "../convex/lib/types.js";

describe("response builders", () => {
  it("jsonResponse sets status, CORS, and content-type", async () => {
    const res = jsonResponse({ a: 1 }, 201);
    expect(res.status).toBe(201);
    expect(res.headers.get("Content-Type")).toBe("application/json");
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST, OPTIONS");
    expect(await res.json()).toEqual({ a: 1 });
  });

  it("jsonResponse defaults to 200", () => {
    expect(jsonResponse({}).status).toBe(200);
  });

  it("errorResponse emits the { ok:false, error } shape with status", async () => {
    const res = errorResponse("bad input", 400);
    expect(res.status).toBe(400);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(await res.json()).toEqual({ ok: false, error: "bad input" });
  });

  it("optionsResponse is a 204 with CORS and no body", async () => {
    const res = optionsResponse();
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Headers")).toBe(
      CORS_HEADERS["Access-Control-Allow-Headers"],
    );
    expect(await res.text()).toBe("");
  });
});

describe("parseFilterRequest", () => {
  it("accepts a valid command and normalizes tag arrays", () => {
    const { command } = parseFilterRequest({
      command: {
        action: "filter",
        includeTags: ["AI", 5, "Founder"],
        excludeTags: ["Infra"],
        rankBy: "relevance",
        targetPersonId: null,
        rawText: "show me ai founders",
      },
    });
    expect(command.action).toBe("filter");
    expect(command.includeTags).toEqual(["AI", "Founder"]); // non-strings dropped
    expect(command.excludeTags).toEqual(["Infra"]);
    expect(command.rankBy).toBe("relevance");
    expect(command.targetPersonId).toBeNull();
    expect(command.rawText).toBe("show me ai founders");
  });

  it("defaults missing tag arrays to []", () => {
    const { command } = parseFilterRequest({ command: { action: "reset" } });
    expect(command.includeTags).toEqual([]);
    expect(command.excludeTags).toEqual([]);
  });

  it.each([
    [undefined, "missing body"],
    [{}, "missing command"],
    [{ command: { action: "nope" } }, "bad action"],
    [{ command: { action: "filter", rankBy: "wrong" } }, "bad rankBy"],
    [{ command: [] }, "command not an object"],
  ])("rejects invalid input (%s) with a 400", (body, _label) => {
    try {
      parseFilterRequest(body);
      throw new Error("expected HttpError");
    } catch (err) {
      expect(err).toBeInstanceOf(HttpError);
      expect((err as HttpError).status).toBe(400);
    }
  });
});

describe("parseInterpretRequest", () => {
  it("accepts transcript and optional visiblePersonIds", () => {
    expect(
      parseInterpretRequest({ transcript: "hi", visiblePersonIds: ["a", "b"] }),
    ).toEqual({ transcript: "hi", visiblePersonIds: ["a", "b"] });
  });
  it("omits visiblePersonIds when absent", () => {
    expect(parseInterpretRequest({ transcript: "hi" })).toEqual({ transcript: "hi" });
  });
  it("rejects a missing/non-string transcript with 400", () => {
    expect(() => parseInterpretRequest({})).toThrow(HttpError);
    expect(() => parseInterpretRequest({ transcript: 3 })).toThrow(HttpError);
  });
});

describe("parseOpenerRequest", () => {
  it("accepts personId and optional userGoal", () => {
    expect(parseOpenerRequest({ personId: "person_ava_shah", userGoal: "x" })).toEqual({
      personId: "person_ava_shah",
      userGoal: "x",
    });
    expect(parseOpenerRequest({ personId: "person_ava_shah", userGoal: null })).toEqual({
      personId: "person_ava_shah",
      userGoal: null,
    });
  });
  it("rejects a missing/empty personId with 400", () => {
    expect(() => parseOpenerRequest({})).toThrow(HttpError);
    expect(() => parseOpenerRequest({ personId: "" })).toThrow(HttpError);
  });
});

describe("parseMatchFaceRequest", () => {
  it("accepts a full payload", () => {
    expect(
      parseMatchFaceRequest({
        imageBase64: "abc",
        imageMimeType: "image/png",
        trackId: "trk_1",
      }),
    ).toEqual({ imageBase64: "abc", imageMimeType: "image/png", trackId: "trk_1" });
  });

  it("defaults mime type to image/jpeg and generates a trackId", () => {
    const out = parseMatchFaceRequest({ imageBase64: "abc" });
    expect(out.imageBase64).toBe("abc");
    expect(out.imageMimeType).toBe("image/jpeg");
    expect(out.trackId).toMatch(/^trk_/);
  });

  it("rejects a missing/empty imageBase64 with 400", () => {
    expect(() => parseMatchFaceRequest({})).toThrow(HttpError);
    expect(() => parseMatchFaceRequest({ imageBase64: "" })).toThrow(HttpError);
  });

  it("rejects an unsupported mime type with 400", () => {
    expect(() =>
      parseMatchFaceRequest({ imageBase64: "abc", imageMimeType: "image/gif" }),
    ).toThrow(HttpError);
  });
});

describe("parseIdentityResolveRequest", () => {
  it("accepts a full payload", () => {
    expect(
      parseIdentityResolveRequest({
        trackId: "trk_1",
        transcript: "find info on him",
        faceImageBase64: "AAAA",
        contextImageBase64: "BBBB",
        imageMimeType: "image/png",
      }),
    ).toEqual({
      trackId: "trk_1",
      transcript: "find info on him",
      faceImageBase64: "AAAA",
      contextImageBase64: "BBBB",
      imageMimeType: "image/png",
    });
  });

  it("defaults images to '' and mime to image/jpeg; omits transcript when absent", () => {
    const out = parseIdentityResolveRequest({ trackId: "trk_1" });
    expect(out.faceImageBase64).toBe("");
    expect(out.contextImageBase64).toBe("");
    expect(out.imageMimeType).toBe("image/jpeg");
    expect("transcript" in out).toBe(false);
  });

  it("rejects a missing/empty trackId with 400", () => {
    expect(() => parseIdentityResolveRequest({})).toThrow(HttpError);
    expect(() => parseIdentityResolveRequest({ trackId: "" })).toThrow(HttpError);
  });

  it("rejects an unsupported mime type with 400", () => {
    expect(() =>
      parseIdentityResolveRequest({ trackId: "t", imageMimeType: "image/gif" }),
    ).toThrow(HttpError);
  });
});

describe("sanitizeMatchResult (HTTP-boundary safety net)", () => {
  const base = (status: FaceMatchResult["status"], personId: string | null): FaceMatchResult => ({
    trackId: "t",
    status,
    personId,
    score: 0.5,
  });

  it("keeps personId for matched and tentative", () => {
    expect(sanitizeMatchResult(base("matched", "person_ava_shah")).personId).toBe(
      "person_ava_shah",
    );
    expect(sanitizeMatchResult(base("tentative", "person_ava_shah")).personId).toBe(
      "person_ava_shah",
    );
  });

  it("strips a leaked personId for unknown / no_face / error", () => {
    for (const status of ["unknown", "no_face", "error"] as const) {
      expect(sanitizeMatchResult(base(status, "person_ava_shah")).personId).toBeNull();
    }
  });

  it("leaves an already-null personId untouched", () => {
    const r = base("unknown", null);
    expect(sanitizeMatchResult(r)).toBe(r);
  });
});
