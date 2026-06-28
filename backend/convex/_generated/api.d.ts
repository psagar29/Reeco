/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as drafts from "../drafts.js";
import type * as http from "../http.js";
import type * as identity from "../identity.js";
import type * as lib_config from "../lib/config.js";
import type * as lib_cv from "../lib/cv.js";
import type * as lib_demoRoster from "../lib/demoRoster.js";
import type * as lib_fiber from "../lib/fiber.js";
import type * as lib_filter from "../lib/filter.js";
import type * as lib_http from "../lib/http.js";
import type * as lib_identityScoring from "../lib/identityScoring.js";
import type * as lib_mockEmbeddings from "../lib/mockEmbeddings.js";
import type * as lib_openai from "../lib/openai.js";
import type * as lib_openaiVision from "../lib/openaiVision.js";
import type * as lib_opener from "../lib/opener.js";
import type * as lib_similarity from "../lib/similarity.js";
import type * as lib_tags from "../lib/tags.js";
import type * as lib_transcriptName from "../lib/transcriptName.js";
import type * as lib_types from "../lib/types.js";
import type * as lib_voiceParser from "../lib/voiceParser.js";
import type * as people from "../people.js";
import type * as seed from "../seed.js";
import type * as state from "../state.js";
import type * as validators from "../validators.js";
import type * as vision from "../vision.js";
import type * as voice from "../voice.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  drafts: typeof drafts;
  http: typeof http;
  identity: typeof identity;
  "lib/config": typeof lib_config;
  "lib/cv": typeof lib_cv;
  "lib/demoRoster": typeof lib_demoRoster;
  "lib/fiber": typeof lib_fiber;
  "lib/filter": typeof lib_filter;
  "lib/http": typeof lib_http;
  "lib/identityScoring": typeof lib_identityScoring;
  "lib/mockEmbeddings": typeof lib_mockEmbeddings;
  "lib/openai": typeof lib_openai;
  "lib/openaiVision": typeof lib_openaiVision;
  "lib/opener": typeof lib_opener;
  "lib/similarity": typeof lib_similarity;
  "lib/tags": typeof lib_tags;
  "lib/transcriptName": typeof lib_transcriptName;
  "lib/types": typeof lib_types;
  "lib/voiceParser": typeof lib_voiceParser;
  people: typeof people;
  seed: typeof seed;
  state: typeof state;
  validators: typeof validators;
  vision: typeof vision;
  voice: typeof voice;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
