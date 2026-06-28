# Open Source Repos

These repos are cloned under `recco/open-source/`.

## Primary

| Local folder | Upstream | Role |
|---|---|---|
| `grape` | `https://github.com/SwiftGraphs/Grape` | SwiftUI force-directed graph for the Brain view. Pinned to tag `1.1.0`. |
| `insightface` | `https://github.com/deepinsight/insightface` | RetinaFace/ArcFace face embedding service. |
| `convex-templates` | `https://github.com/get-convex/templates` | Convex project reference templates. |
| `convex-helpers` | `https://github.com/get-convex/convex-helpers` | Convex helper utilities, useful for backend patterns. |
| `convex-swift` | `https://github.com/get-convex/convex-swift` | Swift client reference for reactive Convex subscriptions. |

## Voice References

| Local folder | Upstream | Role |
|---|---|---|
| `deepgram-nextjs-live-transcription` | `https://github.com/deepgram-starters/nextjs-live-transcription` | Reference for streaming transcription and temporary server-issued Deepgram keys. |
| `deepgram-live-transcripts-ios` | `https://github.com/deepgram-devs/deepgram-live-transcripts-ios` | Archived iOS reference. Use for patterns only, not as a dependency to bet the demo on. |

## Fallbacks

| Local folder | Upstream | Role |
|---|---|---|
| `directed-graph-fallback` | `https://github.com/nmandica/DirectedGraph` | Simpler Swift graph fallback if Grape breaks. |
| `spritekit-force-directed-fallback` | `https://github.com/joenot443/Spritekit-Force-Directed` | More custom SpriteKit graph fallback if visual polish becomes the fight. |

## Dependency rule

Do not copy large chunks from these repos into app code. Use package dependencies when possible, and use the cloned repos as local reference material for APIs, examples, and fallback implementation ideas.

