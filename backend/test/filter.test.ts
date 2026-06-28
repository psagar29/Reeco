import { describe, it, expect } from "vitest";
import {
  applyFilter,
  computeVisibility,
  emptyBrainState,
  personMatchesFilter,
  defaultFilterCommand,
} from "../convex/lib/filter.js";
import { DEMO_PEOPLE } from "../convex/lib/demoRoster.js";
import type { FilterCommand } from "../convex/lib/types.js";

const NOW = 1782522000000;

function cmd(partial: Partial<FilterCommand>): FilterCommand {
  return {
    action: "filter",
    includeTags: [],
    excludeTags: [],
    rankBy: null,
    targetPersonId: null,
    rawText: null,
    ...partial,
  };
}

describe("personMatchesFilter", () => {
  const ava = DEMO_PEOPLE.find((p) => p.id === "person_ava_shah")!;
  it("matches when person has any include tag (OR semantics)", () => {
    expect(personMatchesFilter(ava, cmd({ includeTags: ["AI"] }))).toBe(true);
    expect(personMatchesFilter(ava, cmd({ includeTags: ["Growth"] }))).toBe(false);
    expect(personMatchesFilter(ava, cmd({ includeTags: ["Growth", "AI"] }))).toBe(true);
  });
  it("excludes when person has any exclude tag", () => {
    expect(personMatchesFilter(ava, cmd({ includeTags: ["AI"], excludeTags: ["Founder"] }))).toBe(false);
  });
  it("empty include matches everyone (subject to excludes)", () => {
    expect(personMatchesFilter(ava, cmd({}))).toBe(true);
  });
});

describe("computeVisibility", () => {
  it("'AI' filter brightens all AI people, dims the rest", () => {
    const { visiblePersonIds, dimmedPersonIds } = computeVisibility(DEMO_PEOPLE, cmd({ includeTags: ["AI"] }));
    expect(new Set(visiblePersonIds)).toEqual(
      new Set(["person_ava_shah", "person_nina_park", "person_omar_wilson"]),
    );
    expect(new Set(dimmedPersonIds)).toEqual(new Set(["person_miles_chen", "person_sam_rivera"]));
  });

  it("'Growth' filter -> only Sam", () => {
    const { visiblePersonIds } = computeVisibility(DEMO_PEOPLE, cmd({ includeTags: ["Growth"] }));
    expect(visiblePersonIds).toEqual(["person_sam_rivera"]);
  });

  it("reset -> everyone visible, nothing dimmed", () => {
    const { visiblePersonIds, dimmedPersonIds } = computeVisibility(DEMO_PEOPLE, cmd({ action: "reset" }));
    expect(visiblePersonIds).toHaveLength(DEMO_PEOPLE.length);
    expect(dimmedPersonIds).toEqual([]);
  });

  it("rank by infra orders Infra people first", () => {
    const { visiblePersonIds } = computeVisibility(
      DEMO_PEOPLE,
      cmd({ action: "rank", includeTags: ["Infra"], rankBy: "infra" }),
    );
    // Miles and Ava both have Infra; Miles ranks higher (Infra rankBy boost + tag).
    expect(visiblePersonIds[0]).toBe("person_miles_chen");
    expect(new Set(visiblePersonIds)).toEqual(new Set(["person_miles_chen", "person_ava_shah"]));
  });

  it("draft -> everyone visible (no tag filtering)", () => {
    const { visiblePersonIds } = computeVisibility(
      DEMO_PEOPLE,
      cmd({ action: "draft", targetPersonId: "person_ava_shah" }),
    );
    expect(visiblePersonIds).toHaveLength(DEMO_PEOPLE.length);
  });
});

describe("applyFilter (BrainState recompute)", () => {
  it("bumps updatedAt and records visible/dimmed", () => {
    const start = emptyBrainState(DEMO_PEOPLE, 0);
    const next = applyFilter(start, cmd({ includeTags: ["AI"], rawText: "show me ai" }), DEMO_PEOPLE, NOW);
    expect(next.updatedAt).toBe(NOW);
    expect(next.lastTranscript).toBe("show me ai");
    expect(next.visiblePersonIds.length).toBe(3);
    expect(next.isThinking).toBe(false);
  });

  it("clears highlight ONLY on reset", () => {
    let s = emptyBrainState(DEMO_PEOPLE, 0);
    s = { ...s, highlightedPersonId: "person_ava_shah" };
    const afterFilter = applyFilter(s, cmd({ includeTags: ["AI"] }), DEMO_PEOPLE, NOW);
    expect(afterFilter.highlightedPersonId).toBe("person_ava_shah"); // preserved
    const afterReset = applyFilter(s, defaultFilterCommand(), DEMO_PEOPLE, NOW);
    expect(afterReset.highlightedPersonId).toBeNull(); // cleared
  });

  it("sets selectedPersonId on draft", () => {
    const s = emptyBrainState(DEMO_PEOPLE, 0);
    const next = applyFilter(
      s,
      cmd({ action: "draft", targetPersonId: "person_miles_chen" }),
      DEMO_PEOPLE,
      NOW,
    );
    expect(next.selectedPersonId).toBe("person_miles_chen");
  });
});
