# Theo

<img src="design/icon/preview-ios.png" width="128" align="right" alt="Theo app icon">

**Your Apple Notes daily-task routine, with a lot more power.** Theo is a native SwiftUI app for iPhone, iPad and Mac. It syncs through your private iCloud, like Notes does.

## The flow (same as your Notes routine)

| In Apple Notes | In Theo |
| --- | --- |
| A new note for each day | **Today**: one daily page, titled with the date |
| Throw things in a "quick entry" area | The **Quick Entry** section on top, plus a floating Liquid Glass entry bar |
| Higher = more important | Drag to reorder. Position *is* priority (⌥⌘↑/↓ on Mac) |
| Headings for projects and groups | **Groups** are headings on the page: collapsible, colored, optionally a **project** with a progress bar and deadline |
| Checked items move down | Checked tasks sink to the bottom after a short beat, like Notes |
| Duplicate the note, delete what's done | **Automatic.** At the start of a new day (4:00 by default), open tasks roll over and finished ones move to **History** |

## What's extra

- **Natural-language entry**: `Call mom tomorrow 5pm !! #family @home` sets a deadline, priority, tag and group. Live chips show what Theo understood; tap a chip to undo that part.
- **Return creates the next line**, pasting several lines creates several tasks, and Tab / Shift-Tab (or the keyboard bar) indents tasks into subtasks.
- **Gestures**:
  - swipe right → Done / Not Today
  - swipe left → Delete / Move / Deadline
  - long-press → full menu (priority, deadline, move, tags, arrange, duplicate)
  - drag across groups
  - multi-select for bulk actions
- **Views**: Today (group by Groups / Priority / Deadline, filter chips), Upcoming (day by day), Priority, Quick Entry, every group as its own page, Tags, History (per-day pages with a streak), Recently Deleted (30 days), and full-text search across everything.
- **"Not Today"** hides a task until tomorrow. A small badge shows how many days a task has been carried over.
- **Import from Notes**: paste a daily note and Theo turns its checklists into tasks and its headings into groups.
- **Mac**: keyboard-first (⌘N, ⌘1–6, Space to complete, Return to edit, ⌘[ / ⌘], ⌥⌘1–3 priority), a menu-bar quick entry, and a Settings window.
- Light / Dark / System appearance, accent colors (Notes Yellow by default), Liquid Glass on iOS 26 and macOS 26.

## Tech

- SwiftUI + SwiftData, iOS 26 / macOS 26, with two targets (`Theo`, `TheoMac`) sharing all code in `Theo/Shared`.
- Sync: SwiftData's CloudKit mirroring into the user's private database. It's free and needs no server. The schema is in `cloudkit/schema.ckdb`.
- The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

### Run locally

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Theo.xcodeproj
```

### CI / TestFlight

- `Build` (every push) compiles both apps. Running it manually also captures simulator screenshots.
- `TestFlight` (manual or a `v*` tag) creates the signing certificates and profiles through the App Store Connect API, then archives and uploads iOS and macOS builds. Required repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (Admin key) and optionally `APPLE_TEAM_ID`.
- `CloudKit schema` (manual) imports `cloudkit/schema.ckdb` into the Development environment. It needs `CLOUDKIT_MANAGEMENT_TOKEN` and `APPLE_TEAM_ID`. After it runs, click **Deploy Schema Changes** once in the CloudKit Console so TestFlight builds can sync.

### Icon

`design/icon/make_icon.py` holds the vector source: an abstract butler with a HUD ring, a bow tie, and a shirt front shaped like a check mark. `design/icon/export.sh` regenerates every PNG.
