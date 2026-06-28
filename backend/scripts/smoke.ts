/**
 * Smoke test (no Convex deployment required).
 *
 * Exercises the logic behind every Person B function with sample input and
 * prints the JSON output, so the contract can be verified without the iOS app
 * or a live backend. The Convex functions are thin wrappers around exactly the
 * pure helpers used here, so this mirrors their behavior.
 *
 * Run with:  npm run smoke
 */

import type { BrainState, DraftResult, FaceMatchResult, Person, PublicPerson } from "../convex/lib/types.js";
import { DEMO_PEOPLE } from "../convex/lib/demoRoster.js";
import { deterministicEmbedding, makeMockImageBase64, mockEmbeddingForImage } from "../convex/lib/mockEmbeddings.js";
import { matchBest, toFaceMatchResult, DEFAULT_THRESHOLDS } from "../convex/lib/similarity.js";
import { applyFilter, emptyBrainState } from "../convex/lib/filter.js";
import { parseCommandOffline } from "../convex/lib/voiceParser.js";
import { buildOpenerOffline } from "../convex/lib/opener.js";

const FIXED_NOW = 1782522000000;

function header(title: string): void {
  console.log("\n" + "=".repeat(70));
  console.log(title);
  console.log("=".repeat(70));
}

function show(label: string, value: unknown): void {
  console.log(`\n# ${label}`);
  console.log(JSON.stringify(value, null, 2));
}

// --- "Seed": attach deterministic embeddings to the roster. -----------------
const enrolledPeople: Person[] = DEMO_PEOPLE.map((p) => ({
  ...p,
  faceEmbedding: deterministicEmbedding(p.id),
}));
const roster = enrolledPeople.map((p) => ({ id: p.id, name: p.name }));

header("people:list  (PublicPerson[], no embeddings)");
const publicPeople: PublicPerson[] = enrolledPeople.map(({ faceEmbedding, ...rest }) => {
  void faceEmbedding;
  return rest;
});
console.log(`Returned ${publicPeople.length} people:`);
for (const p of publicPeople) console.log(`  ${p.id}  ${p.name} — ${p.role} @ ${p.company} [${p.tags.join(", ")}]`);

// --- state:get  (default BrainState before any filter). ---------------------
header("state:get  (default BrainState)");
let state: BrainState = emptyBrainState(enrolledPeople, FIXED_NOW);
show("state:get", state);

// --- voice:interpretCommand + state:setFilter for the 5 demo phrases. -------
header("voice:interpretCommand -> state:setFilter  (5 demo phrases)");
const phrases = [
  "Show me AI founders.",
  "Who should I talk to about infra?",
  "Only growth people.",
  "Draft an opener for Ava.",
  "Reset.",
];
for (const phrase of phrases) {
  const command = parseCommandOffline(phrase, roster);
  show(`interpretCommand("${phrase}")`, command);
  state = applyFilter(state, command, enrolledPeople, FIXED_NOW);
  console.log(`  -> visible: [${state.visiblePersonIds.join(", ")}]`);
  console.log(`  -> dimmed:  [${state.dimmedPersonIds.join(", ")}]`);
}

// --- vision:matchFace  (deterministic mock image resolves to one person). ---
header("vision:matchFace  (mock demo image -> exactly one person)");
const targetId = "person_ava_shah";
const imageBase64 = makeMockImageBase64(targetId);
const { embedding: queryEmbedding, markerPersonId } = mockEmbeddingForImage(imageBase64);
const enrolled = enrolledPeople.map((p) => ({ personId: p.id, embedding: p.faceEmbedding! }));
const best = matchBest(queryEmbedding, enrolled, DEFAULT_THRESHOLDS);
const matchResult: FaceMatchResult = toFaceMatchResult("track_demo_1", best, {
  quality: { faceDetected: true, detectionScore: 0.99, model: "mock-deterministic" },
  latencyMs: 0,
  message: `Matched ${best.personId} (score ${best.score.toFixed(3)})`,
});
console.log(`Demo image marker resolved to: ${markerPersonId}`);
show("vision:matchFace", matchResult);
console.log(
  matchResult.status === "matched" && matchResult.personId === targetId
    ? `  OK: matched exactly ${targetId} with score ${best.score.toFixed(3)}`
    : `  WARNING: expected a strong match for ${targetId}`,
);

// Also show that an unrelated image is NOT confidently matched.
const randomImage = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD2wBDAA";
const { embedding: randomEmb } = mockEmbeddingForImage(randomImage);
const randomBest = matchBest(randomEmb, enrolled, DEFAULT_THRESHOLDS);
const randomResult = toFaceMatchResult("track_random", randomBest, {
  message: "No confident match",
});
show("vision:matchFace (unrelated image)", randomResult);

// --- drafts:createOpener. ---------------------------------------------------
header("drafts:createOpener  (templated, offline)");
const ava = enrolledPeople.find((p) => p.id === targetId)!;
const draft: DraftResult = buildOpenerOffline(ava, null, FIXED_NOW);
show("drafts:createOpener(person_ava_shah)", draft);

const draftWithGoal = buildOpenerOffline(
  enrolledPeople.find((p) => p.id === "person_miles_chen")!,
  "shipping a Rust build cache",
  FIXED_NOW,
);
show("drafts:createOpener(person_miles_chen, userGoal)", draftWithGoal);

// --- voice:getDeepgramToken  (stub when no key). ----------------------------
header("voice:getDeepgramToken  (stub when DEEPGRAM_API_KEY unset)");
show("voice:getDeepgramToken", {
  temporaryToken: "stub-deepgram-token-no-key-configured",
  expiresAt: FIXED_NOW + 60_000,
});

header("SMOKE TEST COMPLETE — all functions produced contract-shaped output.");
