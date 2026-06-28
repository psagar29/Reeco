import { describe, it, expect } from "vitest";
import {
  cosine,
  l2normalize,
  isFiniteVector,
  classifyScore,
  matchBest,
  toFaceMatchResult,
  DEFAULT_THRESHOLDS,
  EMBEDDING_DIM,
} from "../convex/lib/similarity.js";
import { deterministicEmbedding } from "../convex/lib/mockEmbeddings.js";

describe("cosine", () => {
  it("returns 1 for identical vectors", () => {
    expect(cosine([1, 2, 3], [1, 2, 3])).toBeCloseTo(1, 12);
  });

  it("returns 0 for orthogonal vectors", () => {
    expect(cosine([1, 0], [0, 1])).toBeCloseTo(0, 12);
  });

  it("returns -1 for opposite vectors", () => {
    expect(cosine([1, 2], [-1, -2])).toBeCloseTo(-1, 12);
  });

  it("is scale-invariant (normalizes internally)", () => {
    expect(cosine([2, 0, 0], [9, 0, 0])).toBeCloseTo(1, 12);
  });

  it("returns 0 for degenerate input (length mismatch, empty, zero vector)", () => {
    expect(cosine([1, 2, 3], [1, 2])).toBe(0);
    expect(cosine([], [])).toBe(0);
    expect(cosine([0, 0, 0], [1, 2, 3])).toBe(0);
  });
});

describe("l2normalize", () => {
  it("produces a unit vector", () => {
    const v = l2normalize([3, 4]);
    expect(Math.hypot(...v)).toBeCloseTo(1, 12);
    expect(v[0]).toBeCloseTo(0.6, 12);
    expect(v[1]).toBeCloseTo(0.8, 12);
  });
  it("leaves a zero vector unchanged", () => {
    expect(l2normalize([0, 0])).toEqual([0, 0]);
  });
});

describe("isFiniteVector", () => {
  it("accepts finite numeric arrays", () => {
    expect(isFiniteVector([0.1, -0.2, 3])).toBe(true);
  });
  it("rejects empty, non-arrays, NaN/Infinity", () => {
    expect(isFiniteVector([])).toBe(false);
    expect(isFiniteVector("nope")).toBe(false);
    expect(isFiniteVector([1, NaN])).toBe(false);
    expect(isFiniteVector([1, Infinity])).toBe(false);
  });
});

describe("classifyScore (threshold classification)", () => {
  it("classifies by the 0.38 / 0.30 thresholds", () => {
    expect(classifyScore(0.5)).toBe("matched");
    expect(classifyScore(0.38)).toBe("matched"); // boundary inclusive
    expect(classifyScore(0.37)).toBe("tentative");
    expect(classifyScore(0.3)).toBe("tentative"); // boundary inclusive
    expect(classifyScore(0.29)).toBe("unknown");
    expect(classifyScore(-1)).toBe("unknown");
  });

  it("respects custom thresholds", () => {
    const t = { strong: 0.9, tentative: 0.5 };
    expect(classifyScore(0.8, t)).toBe("tentative");
    expect(classifyScore(0.95, t)).toBe("matched");
  });
});

describe("matchBest", () => {
  const enrolled = ["a", "b", "c", "d", "e"].map((id) => ({
    personId: id,
    embedding: deterministicEmbedding(id),
  }));

  it("matches a person's own embedding with score ~1", () => {
    const best = matchBest(deterministicEmbedding("c"), enrolled);
    expect(best.personId).toBe("c");
    expect(best.score).toBeGreaterThan(0.99);
    expect(best.status).toBe("matched");
  });

  it("produces near-orthogonal scores across distinct identities", () => {
    // Different deterministic identities should not strong-match each other.
    const best = matchBest(deterministicEmbedding("totally-different-person"), enrolled);
    expect(best.score).toBeLessThan(DEFAULT_THRESHOLDS.strong);
  });

  it("returns unknown for empty enrolled set or degenerate query", () => {
    expect(matchBest(deterministicEmbedding("a"), [])).toEqual({
      personId: null,
      score: 0,
      status: "unknown",
    });
    expect(matchBest([], enrolled).status).toBe("unknown");
  });

  it("deterministic embeddings have the expected dimensionality", () => {
    expect(deterministicEmbedding("a")).toHaveLength(EMBEDDING_DIM);
  });
});

describe("toFaceMatchResult", () => {
  it("drops personId for unknown so no wrong overlay is shown", () => {
    const r = toFaceMatchResult("t1", { personId: "x", score: 0.1, status: "unknown" });
    expect(r.personId).toBeNull();
    expect(r.status).toBe("unknown");
  });
  it("keeps personId for matched/tentative", () => {
    expect(toFaceMatchResult("t1", { personId: "x", score: 0.9, status: "matched" }).personId).toBe("x");
    expect(toFaceMatchResult("t1", { personId: "x", score: 0.33, status: "tentative" }).personId).toBe("x");
  });
});
