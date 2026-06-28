/**
 * Brain scan memory — durable "event memory" with mission-driven lead scoring.
 *
 *   scanMemories:list                     (query)    -> ScanMemory[]   ({ clientId? })
 *   scanMemories:get                      (query)    -> ScanMemory | null
 *   scanMemories:upsertFromIdentityResult (mutation) -> ScanMemory      (scores when a mission is in play)
 *   scanMemories:score                    (mutation) -> ScanMemory | null
 *   scanMemories:updateNotes              (mutation) -> ScanMemory | null
 *   scanMemories:updateFollowUpStatus     (mutation) -> ScanMemory | null
 *   scanMemories:generateOutreach         (action)   -> OutreachDraft   (mission-aware)
 *
 * Dedup is per-client: a scan updates an existing memory of the SAME client when
 * its normalized LinkedIn matches, else its normalized name+company; otherwise it
 * inserts. Only extracted text/links/scores are stored — never raw images.
 */

import {
  action,
  mutation,
  query,
  internalMutation,
  internalQuery,
} from "./_generated/server.js";
import { internal } from "./_generated/api.js";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel.js";
import {
  missionCoreValidator,
  outreachDraftValidator,
  scanMemoryValidator,
} from "./validators.js";
import {
  applyLeadFields,
  mergeMemory,
  normalizeLinkedIn,
  nameCompanyKey,
  type ScanMemoryFields,
  type ScanMemoryUpsertInput,
} from "./lib/scanMemory.js";
import {
  buildOutreachOffline,
  sanitizeOutreach,
  type OutreachDraft,
} from "./lib/outreach.js";
import { scoreLead, type ScorableMemory } from "./lib/leadScoring.js";
import type { MissionProfile } from "./lib/mission.js";
import { getOpenAiConfig } from "./lib/config.js";
import { chatJson } from "./lib/openai.js";

type ScanMemoryDoc = Doc<"scanMemories">;
type MissionDoc = Doc<"missionProfiles">;

/** Public projection: drop server-only dedup keys, expose `_id` as `id`. */
function toPublic(doc: ScanMemoryDoc) {
  return {
    id: doc._id as string,
    scanId: doc.scanId,
    personId: doc.personId ?? null,
    name: doc.name ?? null,
    headline: doc.headline ?? null,
    role: doc.role ?? null,
    company: doc.company ?? null,
    school: doc.school ?? null,
    linkedinUrl: doc.linkedinUrl ?? null,
    email: doc.email ?? null,
    confidence: doc.confidence,
    confidenceScore: doc.confidenceScore ?? null,
    sources: doc.sources,
    notes: doc.notes ?? null,
    badgeText: doc.badgeText ?? null,
    outreach: doc.outreach ?? null,
    firstScannedAt: doc.firstScannedAt,
    lastScannedAt: doc.lastScannedAt,
    scanCount: doc.scanCount,
    // Lead scoring + follow-up (older rows default to new/empty).
    clientId: doc.clientId ?? null,
    leadPriority: doc.leadPriority ?? null,
    leadScore: doc.leadScore ?? null,
    leadReasons: doc.leadReasons ?? [],
    nextAction: doc.nextAction ?? null,
    followUpStatus: doc.followUpStatus ?? "new",
    sentAt: doc.sentAt ?? null,
    editedOutreach: doc.editedOutreach ?? null,
    missionSnapshot: doc.missionSnapshot ?? null,
  };
}

/** Extract the mergeable stored fields from an existing doc. */
function fieldsOf(doc: ScanMemoryDoc): ScanMemoryFields {
  return {
    scanId: doc.scanId,
    clientId: doc.clientId ?? null,
    personId: doc.personId ?? null,
    name: doc.name ?? null,
    headline: doc.headline ?? null,
    role: doc.role ?? null,
    company: doc.company ?? null,
    school: doc.school ?? null,
    linkedinUrl: doc.linkedinUrl ?? null,
    email: doc.email ?? null,
    confidence: doc.confidence as ScanMemoryFields["confidence"],
    confidenceScore: doc.confidenceScore ?? null,
    sources: doc.sources,
    badgeText: doc.badgeText ?? null,
    linkedinKey: doc.linkedinKey ?? null,
    nameCompanyKey: doc.nameCompanyKey ?? null,
    firstScannedAt: doc.firstScannedAt,
    lastScannedAt: doc.lastScannedAt,
    scanCount: doc.scanCount,
    leadPriority: doc.leadPriority ?? null,
    leadScore: doc.leadScore ?? null,
    leadReasons: doc.leadReasons ?? [],
    nextAction: doc.nextAction ?? null,
    followUpStatus: doc.followUpStatus ?? "new",
    sentAt: doc.sentAt ?? null,
    editedOutreach: doc.editedOutreach ?? null,
    missionSnapshot: doc.missionSnapshot ?? null,
  };
}

/** A stored mission doc → the portable MissionProfile the scorer consumes. */
function toMissionCore(doc: MissionDoc): MissionProfile {
  return {
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

/** Build the scorer's input from stored fields + the live notes/transcript. */
function scorable(
  fields: ScanMemoryFields,
  notes: string | null,
  transcript: string | null,
): ScorableMemory {
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
    transcript,
    scanCount: fields.scanCount,
    sources: fields.sources,
  };
}

// --- Queries ----------------------------------------------------------------

export const list = query({
  args: { clientId: v.optional(v.union(v.string(), v.null())) },
  returns: v.array(scanMemoryValidator),
  handler: async (ctx, args) => {
    if (args.clientId) {
      const docs = await ctx.db
        .query("scanMemories")
        .withIndex("by_clientId_lastScannedAt", (q) => q.eq("clientId", args.clientId!))
        .order("desc")
        .collect();
      return docs.map(toPublic);
    }
    const docs = await ctx.db
      .query("scanMemories")
      .withIndex("by_lastScannedAt")
      .order("desc")
      .collect();
    return docs.map(toPublic);
  },
});

export const get = query({
  args: { id: v.string() },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? toPublic(doc) : null;
  },
});

// --- Mutations --------------------------------------------------------------

const upsertArgs = {
  scanId: v.string(),
  status: v.string(),
  clientId: v.optional(v.union(v.string(), v.null())),
  mission: v.optional(missionCoreValidator),
  name: v.optional(v.union(v.string(), v.null())),
  headline: v.optional(v.union(v.string(), v.null())),
  role: v.optional(v.union(v.string(), v.null())),
  company: v.optional(v.union(v.string(), v.null())),
  school: v.optional(v.union(v.string(), v.null())),
  linkedinUrl: v.optional(v.union(v.string(), v.null())),
  email: v.optional(v.union(v.string(), v.null())),
  confidenceScore: v.optional(v.union(v.number(), v.null())),
  personId: v.optional(v.union(v.string(), v.null())),
  transcript: v.optional(v.union(v.string(), v.null())),
  badgeText: v.optional(v.union(v.string(), v.null())),
  hadFaceVerification: v.optional(v.boolean()),
  candidateCount: v.optional(v.number()),
};

/** Find an existing memory of the SAME client: LinkedIn key first, then name+company. */
async function findExisting(
  ctx: { db: { query: (t: "scanMemories") => any } },
  clientId: string | null,
  linkedinKey: string | null,
  ncKey: string | null,
): Promise<ScanMemoryDoc | null> {
  const sameClient = (doc: ScanMemoryDoc) => (doc.clientId ?? null) === clientId;
  if (linkedinKey) {
    const hits: ScanMemoryDoc[] = await ctx.db
      .query("scanMemories")
      .withIndex("by_linkedinKey", (q: any) => q.eq("linkedinKey", linkedinKey))
      .collect();
    const hit = hits.find(sameClient);
    if (hit) return hit;
  }
  if (ncKey) {
    const hits: ScanMemoryDoc[] = await ctx.db
      .query("scanMemories")
      .withIndex("by_nameCompanyKey", (q: any) => q.eq("nameCompanyKey", ncKey))
      .collect();
    const hit = hits.find(sameClient);
    if (hit) return hit;
  }
  return null;
}

export const upsertFromIdentityResult = mutation({
  args: upsertArgs,
  returns: scanMemoryValidator,
  handler: async (ctx, args) => {
    const { mission, ...rest } = args;
    const input: ScanMemoryUpsertInput = rest;
    const now = Date.now();

    const linkedinKey = normalizeLinkedIn(input.linkedinUrl);
    const ncKey = nameCompanyKey(input.name, input.company);
    const existing = await findExisting(ctx, input.clientId ?? null, linkedinKey, ncKey);

    let fields = mergeMemory(existing ? fieldsOf(existing) : null, input, now);

    // Score against the supplied mission, else the client's stored mission.
    let missionToUse: MissionProfile | null = (mission as MissionProfile | undefined) ?? null;
    if (!missionToUse && input.clientId) {
      const stored = await ctx.db
        .query("missionProfiles")
        .withIndex("by_clientId", (q) => q.eq("clientId", input.clientId!))
        .first();
      if (stored) missionToUse = toMissionCore(stored);
    }
    if (missionToUse) {
      const sc = scoreLead(
        scorable(fields, existing?.notes ?? null, input.transcript ?? null),
        missionToUse,
        now,
      );
      fields = applyLeadFields(fields, sc, {
        goalType: missionToUse.goalType,
        rawText: missionToUse.rawText,
      });
    }

    if (existing) {
      await ctx.db.patch(existing._id, fields);
      return toPublic((await ctx.db.get(existing._id))!);
    }
    const id = await ctx.db.insert("scanMemories", fields);
    return toPublic((await ctx.db.get(id))!);
  },
});

export const score = mutation({
  args: {
    id: v.string(),
    clientId: v.optional(v.union(v.string(), v.null())),
    mission: missionCoreValidator,
  },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    if (!doc) return null;
    const now = Date.now();
    const sc = scoreLead(
      scorable(fieldsOf(doc), doc.notes ?? null, null),
      args.mission as MissionProfile,
      now,
    );
    await ctx.db.patch(id, {
      clientId: doc.clientId ?? args.clientId ?? null,
      leadPriority: sc.priority,
      leadScore: sc.score,
      leadReasons: sc.reasons,
      nextAction: sc.nextAction,
      missionSnapshot: { goalType: args.mission.goalType, rawText: args.mission.rawText },
    });
    return toPublic((await ctx.db.get(id))!);
  },
});

export const updateNotes = mutation({
  args: { id: v.string(), notes: v.union(v.string(), v.null()) },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    if (!doc) return null;
    const trimmed = args.notes && args.notes.trim() ? args.notes.trim() : null;
    await ctx.db.patch(id, { notes: trimmed });
    return toPublic((await ctx.db.get(id))!);
  },
});

const FOLLOW_UP_STATUSES = new Set(["new", "drafted", "edited", "sent", "archived"]);

export const updateFollowUpStatus = mutation({
  args: {
    id: v.string(),
    status: v.string(),
    editedOutreach: v.optional(v.union(outreachDraftValidator, v.null())),
    sentAt: v.optional(v.union(v.number(), v.null())),
  },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    if (!doc) return null;

    const status = FOLLOW_UP_STATUSES.has(args.status) ? args.status : "new";
    const patch: Partial<ScanMemoryDoc> = { followUpStatus: status };
    if (args.editedOutreach !== undefined) patch.editedOutreach = args.editedOutreach;
    if (status === "sent") patch.sentAt = args.sentAt ?? Date.now();
    else if (args.sentAt !== undefined) patch.sentAt = args.sentAt;

    await ctx.db.patch(id, patch);
    return toPublic((await ctx.db.get(id))!);
  },
});

// --- Outreach generation (action) -------------------------------------------

const OUTREACH_SYSTEM = `You write concise, natural, non-salesy networking outreach from one event attendee to another.

Output ONLY a JSON object: { "linkedinDm": string, "coldEmailSubject": string, "coldEmail": string, "inPersonOpener": string }.

Rules:
- Reference the person's actual role/company/work. Never invent facts.
- Tailor lightly to the sender's mission/goal when given (e.g. fundraising, getting hired, finding sponsors) — but stay human and specific, never pushy.
- "linkedinDm": 1-2 sentences, friendly, mentions Recco (an AR memory layer for event networking).
- "coldEmail": 3-5 short lines with a warm sign-off; "coldEmailSubject" is a short subject.
- "inPersonOpener": one friendly sentence to restart a conversation at the event.`;

export const generateOutreach = action({
  args: {
    id: v.string(),
    eventName: v.optional(v.union(v.string(), v.null())),
    senderName: v.optional(v.union(v.string(), v.null())),
    mission: v.optional(missionCoreValidator),
  },
  returns: outreachDraftValidator,
  handler: async (ctx, args): Promise<OutreachDraft> => {
    const now = Date.now();
    const memory = await ctx.runQuery(internal.scanMemories.getInternal, {
      id: args.id,
    });

    const goalType = args.mission?.goalType ?? null;
    const input = {
      name: memory?.name ?? null,
      role: memory?.role ?? null,
      company: memory?.company ?? null,
      school: memory?.school ?? null,
      headline: memory?.headline ?? null,
      eventName: args.eventName ?? null,
      senderName: args.senderName ?? null,
      goalType,
      priority: memory?.leadPriority ?? null,
    };

    let draft = buildOutreachOffline(input, now);

    const { apiKey, model } = getOpenAiConfig(process.env);
    if (apiKey) {
      try {
        const obj = await chatJson({
          apiKey,
          model,
          system: OUTREACH_SYSTEM,
          user:
            `Person: ${input.name ?? "Unknown"}` +
            `${input.role ? `, ${input.role}` : ""}` +
            `${input.company ? ` at ${input.company}` : ""}.\n` +
            (input.school ? `School: ${input.school}\n` : "") +
            (input.headline ? `Headline: ${input.headline}\n` : "") +
            `Event: ${input.eventName ?? "the event"}\n` +
            `My name: ${input.senderName ?? "(omit sign-off name)"}\n` +
            (goalType ? `My mission/goal: ${goalType} (${args.mission?.rawText ?? ""})\n` : "") +
            (memory?.leadReasons?.length
              ? `Why they matter: ${memory.leadReasons.join("; ")}\n`
              : "") +
            `Write the outreach now.`,
          temperature: 0.6,
        });
        draft = sanitizeOutreach(obj, draft);
      } catch {
        // Keep the deterministic draft.
      }
    }

    if (memory) {
      await ctx
        .runMutation(internal.scanMemories.saveOutreach, {
          id: args.id,
          outreach: draft,
        })
        .catch(() => {});
    }
    return draft;
  },
});

// --- Internal helpers for the action ----------------------------------------

export const getInternal = internalQuery({
  args: { id: v.string() },
  returns: v.union(scanMemoryValidator, v.null()),
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (!id) return null;
    const doc = await ctx.db.get(id);
    return doc ? toPublic(doc) : null;
  },
});

export const saveOutreach = internalMutation({
  args: { id: v.string(), outreach: outreachDraftValidator },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const id = ctx.db.normalizeId("scanMemories", args.id);
    if (id) await ctx.db.patch(id, { outreach: args.outreach });
    return null;
  },
});
