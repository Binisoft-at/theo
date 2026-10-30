# Theo

<img src="docs/icon/preview-ios.png" width="128" align="right" alt="Theo app icon">

**Your Apple Notes daily-task routine, with a lot more power.** Theo is a native SwiftUI app for iPhone, iPad, Mac and Apple Watch. It syncs through your private iCloud, like Notes does.

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
- **Apple Watch**: Today on your wrist. Tap a task to check it off, swipe for Not Today / details / delete, add tasks by voice (understands the same `tomorrow 5pm !! @group` shortcuts), plus Upcoming, Priority and every group. Change priority, deadline, group or position from the task's details. It syncs straight through iCloud, so it works without the phone nearby.
- Light / Dark / System appearance, accent colors (Notes Yellow by default), Liquid Glass on iOS 26 and macOS 26.

## Tech

- SwiftUI + SwiftData, iOS 26 / macOS 26 / watchOS 26, Swift 5 language mode. `Theo` (iPhone/iPad) and `TheoMac` build one source tree; `TheoWatch` is embedded in the iOS app and shares the model and store code in `Shared/`.
- Sync: SwiftData's CloudKit mirroring into the user's private database (`.private("iCloud.at.binisoft.theo")`). It's free and needs no server. The schema is in `cloudkit/schema.ckdb`.
- Binisoft conventions: every identifier lives in [`Config/Base.xcconfig`](Config/Base.xcconfig). Setup steps for the portal, App Store Connect and GitHub are in [`docs/setup.md`](docs/setup.md).

### Repo layout

| Path | What's in it |
| --- | --- |
| `project.yml` | XcodeGen spec. `Theo.xcodeproj` is generated, not committed |
| `Config/` | `Base.xcconfig` (identifiers, team, versions), plus Info.plist and entitlements per platform |
| `Packages/TheoCore` | Platform-independent logic (quick-entry parser, day boundaries, checklist ordering, Notes import) with unit tests |
| `App/Sources`, `App/Resources` | The app (iOS + macOS) |
| `Watch/Sources`, `Watch/Resources` | The Apple Watch app |
| `Shared/` | Models, store, sync setup and section logic shared by every target |
| `docs/` | Setup guide, app icon sources |
| `scripts/ci/` | CI helpers |
| `.github/workflows/` | `ci.yml`, `testflight.yml`, and the optional `cloudkit-schema.yml` |

### Run locally

```bash
make test
```

```bash
make open
```

To run on a device or with iCloud from Xcode, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your `DEVELOPMENT_TEAM`.

### CI / TestFlight

- `CI` runs on pushes to `main` and on PRs, and cancels superseded runs (Mac minutes count 10× on private repos). It runs the TheoCore unit tests and builds iOS (with the watch app) and macOS. It publishes its status to the `ci-output` branch. Running it manually, or `[screenshots]` in the commit message, also captures iPhone, Watch and Mac screenshots.
- `TestFlight` (manual or a `v*` tag) archives and uploads iOS and macOS builds with automatic signing through the App Store Connect API key. No certificates or profiles are in the repo, and the build number is the run number. It needs the repository secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (team key "Binisoft CI").
- `CloudKit schema` (manual, one click) imports the schema into Development, then you deploy it to Production in the CloudKit Console. It needs `CLOUDKIT_MANAGEMENT_TOKEN`.

### Icon

`docs/icon/make_icon.py` holds the vector source: an abstract butler with a HUD ring, a bow tie, and a shirt front shaped like a check mark. `make icons` regenerates every PNG.
