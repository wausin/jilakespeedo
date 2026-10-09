# Jilake Speedo — Speedo Redesign + Analytics Design Spec

Date: 2026-10-09
Status: Approved design, pending implementation plan
Builds on: `2026-10-08-jilake-speedo-design.md`

## 1. Summary

Restructure the app's information architecture: move session control onto the
Speedo home screen, replace the standalone Session screen with an Analytics
screen for detailed trip data, and change the speed display from an analog
needle gauge to a digital readout with a racing arc ring.

## 2. Navigation

Tabs: **Speedo · Analytics · Timeline · Settings** (4, unchanged count).
The Session screen is removed; its configuration moves to Speedo and its
session history becomes Analytics.

## 3. Speedo Screen (home)

- **Digital meter**: a large speed number, unit-aware (km/h ↔ mph), centered.
  Around it, a thin colored arc/progress ring shows current speed as a
  fraction of the active vehicle's `gaugeMax` (same 240 km/h default). Peak
  speed marker retained (a tick on the ring at the peak fraction).
- **Weak-signal dot**: pulsing amber dot retained when accuracy > 50 m.
- **Session bar** (collapsible):
  - Idle: `[Distance | Duration]` segmented control + value preset stepper
    (distance: 0.5/1/2/5/10 km or mi; duration: 1/3/5/10/30 min) + **Start**.
  - Running: shows live progress (target vs covered/elapsed) + **Stop**.
  - Finished: summary card (top/avg speed, distance, elapsed) + dismiss.
- **Vehicle switcher**: top-3 pinned bar retained (portrait bottom, landscape
  side), tap to switch, long-press/manage → Settings vehicles.

## 4. Analytics Screen (new; replaces Session)

- **Aggregate header**: total sessions, total distance, best top speed
  (unit-aware), for the active vehicle.
- **Per-session cards** grouped by date: each shows top speed, average speed,
  distance, elapsed. Tap a card to expand its **speed-over-time line chart**.
- **Top-speed bar chart** across recent sessions.
- Reads existing `Session` records and their `TrackPoint`s from storage; no
  data-model changes.
- Charts via **fl_chart** (MIT).

## 5. Decisions

| Decision | Choice |
| --- | --- |
| Meter style | Digital number + thin colored arc ring (racing accent kept) |
| Old Session screen | Removed; config → Speedo, history → Analytics |
| Analytics scope | Summary cards + charts (speed-over-time line, top-speed bars) |
| Charting | fl_chart package |
| Session bar | Collapsible (idle config ↔ running progress) |

## 6. Out of Scope

No storage/schema changes, no new data captured, no changes to Timeline or
recording, no changes to the update checker beyond the manual button already
shipped.

## 7. Testing

- Unit/widget tests for the digital meter (ring fraction math), the
  collapsible session bar (idle → running → finished transitions), and the
  Analytics screen (empty state, cards from seeded sessions, chart data
  mapping).
- Reuse existing SessionEngine/SessionController tests unchanged.
