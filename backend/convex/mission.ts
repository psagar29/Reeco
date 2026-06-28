/**
 * Mission ("Today's Goal") parsing + storage.
 *
 *   mission:parse        (action)          -> MissionProfile   ({ clientId, rawText })
 *   mission:current      (query)           -> MissionProfile | null   ({ clientId })
 *   mission:upsertMission(internalMutation)-> MissionProfile   (store/update for a client)
 *
 * Parsing tries OpenAI (when OPENAI_API_KEY is set) and always falls back to the
 * deterministic `parseMissionFallback`, so the route is fast and never fails.
 * Only mission text is stored — no images, no secrets.
 */

import {
  action,
  query,
  internalMutation,
} from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel.js";
import { missionCoreValidator, missionProfileValidator } from "./validators.js";
import {
  parseMissionFallback,
  sanitizeMission,
  type MissionProfile,
} from "./lib/mission.js";
import { getOpenAiConfig } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";

type MissionDoc = Doc<"missionProfiles">;

const MISSION_SYSTEM = `You convert a networking attendee's free-text event goal into a structured mission JSON.

Output ONLY a JSON object with these keys:
{
  "goalType": one of "fundraising" | "hiring" | "get_hired" | "customers" | "sponsors" | "cofounder" | "founders" | "networking" | "other",
  "targetRoles": string[],       // roles of people worth meeting (e.g. ["investor","partner"])
  "targetKeywords": string[],    // signal words to look for in a headline
  "targetCompanies": string[],   // named companies if mentioned, else []
  "targetIndustries": string[],  // e.g. ["ai","infra"]
  "preferredAction": "linkedin_dm" | "cold_email" | "in_person" | "reminder",
  "tone": string                 // short tone hint, e.g. "warm, concise"
}

Rules:
- Infer goalType from intent: "looking for investors" -> fundraising; "trying to get hired" -> get_hired; "find sponsors" -> sponsors; "find founders" -> founders; "find customers" -> customers.
- Keep arrays tight and lowercase. Never invent companies that weren't mentioned.`;

/** Public projection for a stored mission. */
function toPublic(doc: MissionDoc): MissionProfile & { id: string; clientId: string } {
  return {
    id: doc._id as string,
    clientId: doc.clientId,
    rawText: doc.rawText,
    goalType: doc.goalType as MissionProfile["goalType"],
    targetRoles: doc.targetRoles,
    targetKeywords: doc.targetKeywords,
    targetCompanies: doc.targetCompanies,
    targetIndustries: doc.targetIndustries,
    preferredAction: doc.preferredAction as MissionProfile["preferredAction"],
    userContext: doc.userContext ?? null,
    tone: doc.tone,
    createdAt: doc.createdAt,
    updatedAt: doc.updatedAt,
  };
}

type PublicMission = MissionProfile & { id: string; clientId: string };

export const parse = action({
  args: { clientId: v.string(), rawText: v.string() },
  returns: missionProfileValidator,
  handler: async (ctx, args): Promise<PublicMission> => {
    const now = Date.now();
    let mission: MissionProfile = parseMissionFallback(args.rawText, now);

    const { apiKey, model } = getOpenAiConfig(process.env);
    if (apiKey && args.rawText.trim()) {
      try {
        const obj = await chatJson({
          apiKey,
          model,
          system: MISSION_SYSTEM,
          user: `Event goal: "${args.rawText}"\nReturn the mission JSON now.`,
          temperature: 0.2,
        });
        mission = sanitizeMission(obj, args.rawText, now);
      } catch {
        // Keep the deterministic fallback.
      }
    }

    return ctx.runMutation(internal.mission.upsertMission, {
      clientId: args.clientId,
      mission,
    });
  },
});

export const current = query({
  args: { clientId: v.string() },
  returns: v.union(missionProfileValidator, v.null()),
  handler: async (ctx, args) => {
    const doc = await ctx.db
      .query("missionProfiles")
      .withIndex("by_clientId", (q) => q.eq("clientId", args.clientId))
      .first();
    return doc ? toPublic(doc) : null;
  },
});

export const upsertMission = internalMutation({
  args: { clientId: v.string(), mission: missionCoreValidator },
  returns: missionProfileValidator,
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("missionProfiles")
      .withIndex("by_clientId", (q) => q.eq("clientId", args.clientId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        ...args.mission,
        createdAt: existing.createdAt, // preserve original creation time
      });
      const updated = await ctx.db.get(existing._id);
      return toPublic(updated!);
    }

    const id = await ctx.db.insert("missionProfiles", {
      clientId: args.clientId,
      ...args.mission,
    });
    const created = await ctx.db.get(id);
    return toPublic(created!);
  },
});
