# Recco — Vibe Apps Submission

## App Title

Recco

## App / Project Tagline

An iPhone AR networking assistant that identifies people, scores leads, and drafts follow-ups in real time.

## Description

### Problem we're solving

Events are full of high-value people, but it is hard to know who to talk to, what to say, and how to follow up before the moment is gone. Name tags are noisy, LinkedIn search is slow, and most networking notes die in your camera roll or memory.

Recco turns the iPhone camera into a live networking lens.

### How it works

You open Recco, tell it your goal for the event, then point your phone at someone. Recco locks onto the person closest to the center of the camera, reads their badge/context, searches for profile data, verifies the face when possible, and shows a lightweight AR result card with their name, LinkedIn, confidence, and a suggested opener.

Every scan is saved into a Brain graph, where people are scored as hot/warm/cold leads based on your goal. From there, Recco drafts a LinkedIn DM, cold email, or in-person opener.

There is also a Lazy GTM mode: ask for something like "find 8 Swift engineers" or "find investors," and Recco creates a separate prospect graph with outreach drafts.

### Notable features

- Fullscreen iPhone camera with AR-style face brackets and target lock
- Voice command flow: "find info on him"
- Deepgram-powered live speech capture
- OpenAI Vision badge/context reading
- Fiber / Orange Slice style profile lookup for LinkedIn and people data
- CV face verification service using InsightFace embeddings
- Convex backend with HTTP Actions, persistent Brain memories, mission profiles, and GTM runs
- Mission setup: "I'm looking for investors," "I'm hiring," "I want to get hired," etc.
- Lead scoring: hot/warm/cold based on your event goal
- Brain graph of people scanned at the event
- Generated LinkedIn DM, cold email, and in-person opener
- Lazy GTM scout mode for finding outbound prospects without scanning manually
- iPhone-first UX with glassy, minimal AR interface

### Why we built this

Networking should feel less like awkward guessing and more like having a real-time chief of staff in your pocket. At a hackathon or conference, the highest-leverage moments happen in seconds: seeing someone, recognizing why they matter, saying the right thing, and following up before you forget.

We built Recco to make that moment instant.

### Tech stack

- SwiftUI / AVFoundation / Vision for the iPhone app
- Convex for backend, persistence, HTTP Actions, and live app state
- OpenAI for badge/context understanding, mission parsing, and outreach writing
- Deepgram for streaming speech-to-text
- Fiber / Orange Slice APIs for people and profile lookup
- FastAPI + InsightFace for face embeddings and verification
- TypeScript + Vitest for backend logic and tests
- Xcode + physical iPhone deployment for live demo

### Challenges we ran into

- Making a camera-first iOS app feel reliable enough for a live demo
- Keeping face brackets, target lock, and hologram cards aligned as the camera moves
- Separating known enrolled face matching from identity lookup from badge/name
- Making the identity pipeline fast enough: OCR -> profile lookup -> face verification
- Avoiding false positives: unknown or low-confidence faces should not get a wrong name
- Keeping API keys off the phone and only in Convex
- Designing the Brain graph so it feels useful, not like a dashboard
- Handling unreliable event Wi-Fi and physical-device install issues

### Success so far

- Live Convex backend deployed
- CV service deployed and returning real 512-d face embeddings
- iPhone app installed and tested on device
- Identity endpoint tested with physical-device event photos
- Brain memories, mission scoring, and Lazy GTM flow implemented
- Backend test suite passing: 167 tests

## App Website Link

https://github.com/psagar29/Reeco

## Video Demo

TODO: Add YouTube/Vimeo/unlisted video link.

## Your Name

Pranav Sagar

## Email

TODO: Add hackathon notification email if desired.

## GitHub Repo URL

https://github.com/psagar29/Reeco

## LinkedIn Share Or Profile Link

TODO: Add LinkedIn launch post or profile link.

## X / Twitter Share Or Profile Link

TODO: Add X post/profile link, or leave blank.

## Team Info

Built by the Recco hackathon team.

Team focus areas:

- iOS camera + AR interface
- Convex backend + Brain memory graph
- CV face embedding service
- Voice, identity lookup, and GTM/outreach flow

## Tags

Select:

- convex
- OpenAI
- YCGrowthHackathon
- OrangeSlice

Also add if available:

- Deepgram
- iOS
- AI
- Networking
- Computer Vision
- GTM
- LinkedIn

## Screenshot Upload

Recommended screenshot:

- iPhone camera AR view with target lock and hologram result card

Additional image ideas:

- Mission setup glass prompt
- Brain graph with scanned person nodes
- Lazy GTM prospect graph
- Outreach draft/detail screen
