/**
 * Seeding / enrollment.
 *
 *   seed:run (public mutation) — (re)load the demo roster and initialize state.
 *
 * Pass `embeddings` (a personId -> 512-floats map produced by `npm run enroll`)
 * to store real enrolled embeddings; omit it to use deterministic mock
 * embeddings so face matching works fully offline.
 */

import { mutation } from "./_generated/server.js";
import { v } from "convex/values";
import { DEMO_PEOPLE } from "./lib/demoRoster.js";
import { deterministicEmbedding } from "./lib/mockEmbeddings.js";
import { emptyBrainState } from "./lib/filter.js";

const SINGLETON_KEY = "singleton";

export const run = mutation({
  args: {
    embeddings: v.optional(v.record(v.string(), v.array(v.number()))),
  },
  returns: v.object({
    peopleInserted: v.number(),
    usedRealEmbeddings: v.boolean(),
    embeddingSource: v.string(),
  }),
  handler: async (ctx, args) => {
    const provided = args.embeddings ?? {};
    let usedReal = false;

    // Clear existing roster + state so seeding is idempotent.
    for (const d of await ctx.db.query("people").collect()) await ctx.db.delete(d._id);
    for (const d of await ctx.db.query("appState").collect()) await ctx.db.delete(d._id);

    for (const person of DEMO_PEOPLE) {
      const real = provided[person.id];
      let embedding: number[];
      if (real && real.length > 0) {
        embedding = real;
        usedReal = true;
      } else {
        embedding = deterministicEmbedding(person.id);
      }

      await ctx.db.insert("people", {
        personId: person.id,
        name: person.name,
        role: person.role,
        company: person.company,
        avatarUrl: person.avatarUrl,
        bio: person.bio,
        tags: person.tags,
        links: person.links,
        whyTalk: person.whyTalk,
        openerSeed: person.openerSeed,
        faceEmbedding: embedding,
      });
    }

    // Initialize the singleton app state with everyone visible.
    const state = emptyBrainState(
      DEMO_PEOPLE.map((p) => ({ id: p.id })),
      Date.now(),
    );
    await ctx.db.insert("appState", { ...state, key: SINGLETON_KEY });

    return {
      peopleInserted: DEMO_PEOPLE.length,
      usedRealEmbeddings: usedReal,
      embeddingSource: usedReal ? "enrolled (real or per-person mock)" : "deterministic-mock",
    };
  },
});
