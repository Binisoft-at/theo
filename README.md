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
| Duplicate the note, delete what's done | **One tap.** At the start of a new day (4:00 by default) finished tasks move to **History**, and whatever is still open waits at the top of Today with **Bring Over** |

## New in v7

### Every morning

- **Nothing slips overnight.** When something you planned stays open, Today shows "↪ 3 unfinished from earlier" at the top with **Bring Over**, and "2 due by today, not planned" with **Add** (both with Undo). Tap the hint itself to open Plan; × hides it until tomorrow (on that device). The header no longer says "All done" while earlier tasks wait: it reads "All planned done · 3 left from earlier".
- **An honest header**: "3,5 PH left · 1 done · usually ~3 PH". "Usually" is your average over the last 7 days that had something done (it appears once there are two such days). When today holds about a third more than that, the line turns orange ("more than a usual day") and a tap opens Plan.
- **Swipe left → Today** on any list (orange). On a task that's already on today the same button says **Tomorrow** (indigo). On the Mac: two fingers, or ⌥⌘D.
- **Plan with all the tools**: touch and hold (iPhone) or right-click (Mac) any task in Plan for the full menu, including Quick Edit and Details. On iPhone a tap still plans or unplans; on the Mac a click shows the task in the details column, and its circle (or a double-click) plans it. Every plan and unplan has Undo. A planned task with subtasks shows once ("2 of 3 subtasks open · Σ 1,5 PH"); a subtask planned alone says "in: <parent>". Planning tomorrow offers "Still open today" with Add All; later days fold what's already planned into "Already planned earlier". An indigo sun marks today's plan, an indigo calendar check other days; the day strip shows "5 PH" and a red dot on days with something due.

### Capture

- **Dates the way you say them, in German and English**: `morgen 9 Uhr`, `übermorgen`, `bis Freitag`, `bis Fr`, `nächsten Freitag`, `nächste Woche`, `am Wochenende`, `Monatsende`, `in 3 Tagen`, `in zwei Wochen`, `am 15.12.`, `bis zum 15.01.`, `14 Uhr`, `um 9`, `14:30`, `Mi 15 Uhr`, `heute Abend um 8`, `tomorrow 5pm`, `next monday`. Words like `bis`, `am` and `um` leave the title with the date.
  - Dates count from Theo's day, not midnight: `morgen` typed at 01:30 is the day after the one you're still in.
  - **A time alone that has already passed means tomorrow**: `um 9` typed at 10:00 is due tomorrow at 9:00 (`heute um 9` keeps today).
  - Not a date, on purpose: `Morgen` as a noun (`am Morgen`, `guten Morgen`, `Morgenroutine`), `ab Montag`, `Fr. Müller`, `1.5 Liter`, and a bare `09.09` that is in the past or more than 6 months away (write `am 09.09` to mean it).
  - The date chip shows the words it took (`bis Freitag → Fri 20 Nov`). The small × next to it, or Date → No Deadline, puts them back into the title; Repeat → Don't Repeat does the same for a typed repeat.
  - New repeats: `jeden Montag` / `every Monday` (weekly, starting the next Monday), `alle 2 Wochen`, `every other week`, `zweiwöchentlich`, `every 3 weeks`, and `jeden Morgen` / `every evening` (daily). Every Repeat menu offers Every 2 Weeks.
- **Siri, Shortcuts, Spotlight and the Action button** (iPhone and Mac, English phrases, working once the new version has been opened once):
  - "Add a task to Theo" (also "New Theo task", "Add to Theo"): Siri asks for the task and answers e.g. "Added “Call Anna” to Quick Entry · due tomorrow 17:00". It understands the same marks as the bottom bar (`!!`, dates, `#tag`, `@Group`, `0,5PH`, repeats, `∞`). The task lands in Quick Entry or the group named with `@`, and goes on today's plan only when the Shortcuts action's **Plan for Today** switch is on.
  - "What's left in Theo" (also "Theo today"): "5 open today · 2,5 PH left · next: Send the offer".
  - "Quick entry in Theo" opens Theo with the cursor in the bottom bar.
  - Action button: Settings → Action Button → Shortcut → Theo → Quick Entry (or Add Task).
  - Mac Spotlight: ⌘Space, type "Add Task", type the task, Return. Theo doesn't need to be in front.
  - Share sheet: make a one-step shortcut with Theo's Add Task and switch on "Show in Share Sheet". With several lines of text, the first becomes the task and the rest its description.
- **Quick Add from any app (Mac)**: ⌃⌥⌘N brings Theo to the front with the cursor in the bottom bar (and opens a window if none is open). Change it or turn it off in Settings → Quick Add (⌃⌥⌘T or ⌥⇧Space instead); no extra permission needed. Right-click Theo's Dock icon for New Task and Today.
- **The add confirmation tells you what Theo understood**: "Added to Work · due Friday · !! · 0,5 PH · ↻ Every Week", with **Show** to jump to the task. On Today, a task due on a later day adds "· on today" and offers **Off Plan**.

### Finding and changing

- **⌘F searches every task** from any page on the Mac and iPad (the "Search all tasks" field in the toolbar; the Search tab on iPhone). Open matches come first, ranked; finished ones fold away behind "Show N finished"; logs of ongoing tasks stay out.
- **Details: a Plan row** right under the title: Today (orange), Tomorrow, Next Week, Pick… (any day) and Off Plan, each with Undo. Below it, "Planned since Mon (3 days)". The old Planned switch and its date are gone. Priority (! !! !!!) stays near the top; importance 1–10 and the matrix fold into **Ranking**; Repeat & Reminders sit right under Deadline. Switching on a deadline's **Time** picks the next full hour today, or 9:00 on another day, so the reminder can still come. Subtasks typed in details understand PH, `∞`, repeats and dates. The text field is called **Description**.
- **Quick Edit panel**: fits the iPhone (two rows of four round buttons). On a task already on today, the sun says **Off Plan**. Deadline chips are blue (the deadline colour), selected chips use dark text on bright fills like Notes Yellow. On the Mac, a selected task's details column starts with round Done, Subtask, Ongoing, Focus and Delete buttons.
- **Select many on iPhone**: **Select** on Today's toolbar (⋯ → Select Tasks on other pages), then Select All / None or the Select menu (Overdue, Due Today, Unfinished from Earlier, Not Planned). The bar has labelled buttons in the panel's colours: Done, Today, Tomorrow, Deadline, PH, Move, Priority, Delete.
- **Keyboard on the Mac**: Esc finishes editing a line and keeps it selected. After Done, Delete, Tomorrow or Move the selection moves on to the next line instead of staying on a task you can't see. → unfolds and ← folds a task's subtasks (← on a subtask jumps to its parent). ⌘I opens the details column. ⌘N stays in the bottom bar of Plan, Upcoming and Priority. While you type, ⌘⌫ deletes text and the Task menu's shortcuts leave your tasks alone. The legend under the sidebar now lists Return, Esc, ⌫, ← / →, ⌘F and the Quick Add key too.
- **Tag pages** list every open task with the tag (plus those done today), by group, with ⋯ → Plan All for Today and Save as View. Upcoming and Priority are ranked. A past day in History shows what got done first, by group with Σ PH, then a folded "N still open at day's end"; the History list reads "N done · X PH".
- **Overview and Matrix**: tiles read "PH left" and "done in 7 days" (which opens History), and every card opens its list; on iPhone it opens inside the Overview tab, and Back returns there. The Ongoing card lists the routines left alone longest first ("last yesterday", orange after a week). On the Mac, pointing at a Matrix dot shows its name, and a click shows it in the details column; on iPhone a second tap on a dot opens it.

### Reminders and repeats

- **Banner buttons**: Done, Snooze 10 min, 1 Hour, Tomorrow; "Still open" nudges after the time offer Done, Tomorrow and Next Week (on the Mac under the banner's Options). Tomorrow and Next Week move the deadline (same time) and plan the task for that day.
- **Finished means quiet**: finishing or deleting a task on any device removes its waiting reminders, snoozes and banners (on the other device once it has synced). Tasks in switched-off groups don't remind. Snoozing again replaces the earlier snooze. Clicking a banner on the Mac opens the main window on that task.
- **App icon badge** (Settings → App icon badge → Open today, off by default): the number of open tasks on Today, on the iPhone icon and the Mac Dock icon. On iPhone it asks for notification permission.
- **Repeats keep their rhythm**: see "Works differently now" below.

### Safety

- If Theo can't open your tasks, a red banner says so (instead of an empty app that forgets everything) and backups pause. If it can't reach iCloud, an orange "Not syncing with your other devices" banner shows. A failed save shows "Couldn't save: …".
- Backups also run when you switch back to Theo on the Mac and when a new day starts; an empty copy never pushes good backups out; "Last backup" turns orange after two days. The Mac saves on quit.
- More Undo: Delete Group → Keep Tasks, Move to… (it also takes back what the new group's traits added), Complete All, every plan change. Restoring from Recently Deleted brings back the subtasks deleted with a task.

### Works differently now

- **Repeats**: checking off an overdue repeating task brings it back **tomorrow** at the earliest (a daily task due 3 days ago is next due tomorrow; a weekly one keeps its weekday). Monthly and yearly repeats keep their day (31 Jan → 28 Feb → 31 Mar; 29 Feb comes back in leap years). A repeat added without a date starts today (repeating tasks that have no date get today's date once, when v7 first starts). The next copy gets fresh, unchecked subtasks. Unchecking a task you just checked off takes the next copy back (if nobody changed it) and reopens the subtasks the check closed.
- **Ongoing tasks** with a repeat and a deadline move to the next date when checked off and land on that day's plan. Their logs go to the end of the group.
- **"Not Today" is now "Tomorrow"** everywhere (swipes, menus, the panel, the Watch); ⌥⌘L is "Plan for Tomorrow". **Subprojects are Subgroups** ("New Subgroup…").
- **Dragging on Today (Ranked)** only changes a task's rank ("Moved up · importance 7", with Undo); it never moves a task into another group.
- **Complete All** on a heading finishes only what it shows ("Complete 3 Shown"); a group page's "Complete All Open" leaves ongoing routines alone. Both have Undo, and so does checking off a single task when it does more than tick that line (closes subtasks, files the next repeat, logs an ongoing task).
- **Today's toolbar**: Focus and Select on iPhone, Focus on the Mac. New Group moved into ⋯ (with Settings… on iPhone). Today's own search field is gone (⌘F on Mac and iPad, the Search tab on iPhone).
- **The carried-over badge** counts the days since a task was first planned (not since it was created), so it starts fresh with this version.
- ⌘↩ no longer adds from the composer (Return does); it marks the selected task done. The Mac menu bar puts a typed task on today's plan only when it has no date, today's or an earlier one.
- Lines typed straight into a list understand `0,5PH`, `∞`, `laufend` and ` // description`, and `!!` raises the importance too. Duplicate copies subtasks, the repeat, reminders and Power Hours.

## What's extra

- **Natural-language entry**: `Call mom tomorrow 5pm !! #family @home` sets a deadline, priority, tag and group, in English or German (`Mama anrufen morgen 17 Uhr`). Live chips show what Theo understood; tap a chip to undo that part.
- **One-tap composer**: buttons above the entry bar set priority (tap to raise, hold to pick), deadline and group. Start a line with `- ` to add it as a subtask of the task you just added. Pasting an indented list keeps the nesting (ticked lines like `- [x]` are skipped, and the chips show only what applies to every line). Every add can be undone from the confirmation line.
- **Subtasks**: Add Subtask from the menu, the keyboard bar or the details sheet. Return creates the next line, and Return on an empty subtask steps back out (like Notes). Tab / Shift-Tab indent and outdent. Parents show a `2/5` badge that folds their subtasks away.
- **Priority in one tap**: a `! !! !!!` row in the context menu and the Quick Edit panel, the keyboard-bar button, `!!` typed at the end of a line, or ⌥⌘1–3 / ⌥⌘P on the Mac.
- **Power Hours**: estimate tasks in PH (1 PH = 50 focused minutes): type `0,5ph`, tap the PH chip (0,25 · 0,5 · 0,75 · 1 · 2 · custom), or use the menu. Today shows what's left and what's done, headings show what's open, History shows what got done. A parent's estimate only counts when its subtasks have none.
- **Focus timer**: start focus on a task: one Power Hour of focus (50 min, adjustable), then a break. The time is booked on the task (on that day's log for an ongoing task you check off meanwhile), the timer survives app restarts, notifies when a phase ends and moves on to the break by itself.
- **Reminders & repeats**: tasks with a time notify you (at the time by default). Add earlier reminders, custom offsets and follow-ups after the time, and repeats (daily, weekdays, weekly, every 2 weeks, monthly, yearly, every N days; typed as `daily`, `weekly`, `täglich`, `jeden Montag`, `alle 2 Wochen` …). Checking off a repeating task schedules the next one. Banners offer Done, Snooze 10 min, 1 Hour and Tomorrow.
- **Plan your days**: Today only shows what you planned for it. The Plan tab picks tasks for any of the next 14 days, suggesting unfinished tasks from earlier days, tasks due by then and the most important ones first, with Power Hours per day. Leftovers and unplanned deadlines also wait at the top of Today (Bring Over / Add).
- **Ranked everywhere**: every list is ordered by importance (10 levels) and urgency (days until the deadline, today → 14 days, or none). Drag the grid handle in the entry bar onto the full-screen grid and it snaps to a day and an importance level; Place in Matrix… does the same for existing tasks. `!` / `!!` / `!!!` are a coarse view of importance. Dragging a task to a new spot raises or lowers its importance so it stays there. Overdue tasks rise to the top with a calm "was due yesterday" and a quick menu to move the date.
- **Hold and point**: hold the send button and the Power Hours (0,1 … 4, or custom) fan out on an arc above it, always above the keyboard; slide toward one and let go. The ! chip does the same for importance 1–10.
- **Drop a task in between**: drag the + up between two tasks (no hold needed; a ghost follows the finger). The new line lands right there and ranks between its neighbours without inventing a deadline; right under a task with subtasks it becomes the first subtask.
- **Default Power Hours**: every new task starts with 0,25 PH (Settings → Tasks; remove it per task any time).
- **Groups pass things on**: a group can give its tasks an importance, Power Hours, tags and a deadline N days out; subgroups inherit them unless they set their own. New tasks take them where nothing was typed. A task moved in keeps its own values and shows a **Suggested** chip (Apply All, one part, or Keep Mine). A group page's header says what new tasks get ("New tasks get 1 PH · #work"); tap it to edit.
- **Switch groups off**: a group or subgroup that's off keeps its tasks out of Today, Plan, Upcoming, Priority, the Matrix, the menu bar, reminders and the watch. Tap a subgroup on its parent's page, swipe a group in the sidebar, or use the group editor. A saved view that names a group still shows it; its switched-off subgroups stay hidden unless ticked.
- **Day review**: tap the ring on Today (⌘9 on the Mac), or open a day in History: Power Hours worked and what they went into, a comparison with the 7/14/30 days before (weekday names, or a date every 7 days), a quiet share of the page done, and every finished task. Export finished tasks as CSV (this day, 7 days, 30 days, everything). Settings → Day Review → What it shows picks what's shown.
- **Ongoing tasks** (∞, "laufend"): work that never ends. Checking one off logs a finished copy for the day (it counts in History and the day review, with its Power Hours) and the task stays. Plan offers them under Ongoing; unchecking the logged copy takes it back. Give one a deadline and a repeat too, and it comes back on its own.
- **Import that starts over**: Import from Notes can replace everything (the old tasks go to Recently Deleted for 30 days, with Undo). `> lines` become notes of the task above, `∞` marks ongoing tasks, and subtasks under a line with its own estimate don't add default Power Hours on top.
- **All Tasks**: every task, filtered by status, group, tag, importance, deadline, planned day, size or ongoing, grouped by group, top group, priority, deadline, tag, size or planned day, and sorted by priority and deadline, rank, deadline, Power Hours, newest or title. Ready-made views (Due This Week, Important, Quick Wins, Ongoing, Not Planned, Done) and saved ones switch in one tap. **Save as View** keeps a combination in the sidebar (synced, with its open count), and views and groups can be **favourites** at the top of the sidebar.
- **Overview tab**: totals, today, the deadlines of the next two weeks, a card per group (open, Power Hours, overdue, next deadline, subgroups, switched-off ones dimmed), priorities, ongoing work and the biggest open blocks. Every card opens the list behind it.
- **Plan browser**: Browse All Tasks by group, priority, deadline or size, sections that open on tap, search, top-level tasks with their subtasks counted and their Power Hours added up.
- **Tasks with subtasks**: the parent shows the open Power Hours of everything under it (Σ) and a progress bar; subtasks are simply indented, with no guide lines, and don't repeat their parent's group. A subtask planned without its parent shows on its own instead of under another task. On the Mac, two fingers swipe right to indent and left to outdent, and hovering between lines shows a + to add a task there. Crowded Matrix cells become one bubble with a count.
- **Stats on every list**: groups and All Tasks show what's open, the Power Hours left, overdue, due within a week and done today. Headings of computed lists (Upcoming, Priority, tags, search) show their Σ PH too.
- **Backups**: besides iCloud, a full JSON copy every day (the last 30 kept), Back Up Now, export, and restore (Settings → Backups; on iPhone also in Files → On My iPhone → Theo).
- **Descriptions in passing**: `Call bank // ask about the fee` puts everything after ` // ` into the description (the Description chip adds the separator); while editing a line its description field sits right under the title (⇧Return or the ≡ keyboard button jumps there). Settings → Show description under the title.
- **Text size**: Settings → Appearance → Text Size (Small to Huge; System follows Dynamic Type on iPhone). On the Mac, where text styles don't follow Dynamic Type, lists, rows, headers, the sidebar and the entry bar scale with it; ⌘+ / ⌘− / ⌘0. The Mac starts at Large.
- **Precise insert line**: rows sit flush, so the divider is the row edge; the insert line (drag on iPhone, hover on the Mac) lights up exactly that divider, from where the text starts, with a small + tab.
- **Quick actions in colour**: right-click a task on the Mac (Quick Edit from the long-press menu on iPhone) and a panel opens right above it: done, Today (Off Plan when it's already on today) and Tomorrow, subtask, ongoing, focus, details, delete, plus one-tap priority, deadline, Power Hours and group. With several selected it acts on all of them.
- **Mac layout**: lists and the entry bar keep a readable width; the space to the right holds an inspector with the selected task's quick actions and full details, editable in place (⌥⌘I), or the day at a glance when nothing is selected.
- **Group Today your way**: ranked, by group, by group and subgroup, priority, deadline, tag or size (Power Hours). Expand All and Collapse All work in every layout.
- **Swipe right = subtask** of the line above (again to take it back out); swipe left for Delete, Today (or Tomorrow when it's already on today) and +1 Day / Deadline.
- **Navigation**: Liquid Glass tab bar on iPhone (Today, Plan, Overview, Lists, Search); sidebar on iPad and Mac with the shortcuts in grey, and ⌘F search on every page. The sidebar's Plan count is what's planned for tomorrow.
- **Subgroups**: groups can sit inside groups (New Subgroup…, or "Inside" in the group editor). They appear nested on Today, in the sidebar and on the parent's page, and fold away with the parent. Import understands `#` groups and `##` subgroups, `(0,25PH)` estimates and `📅 2026-11-04` deadlines.
- **Forgiving**: shake to undo (⌘Z on Mac) for any change, Undo on deletes, moves, plan changes, completions and adds, and empty lines vanish on their own.
- **Interactive tour**: shown on first launch (later versions show a short "What's new"), replayable from Settings (Take the Tour, or What's New for just the latest steps), Today's ⋯ menu or Help → Theo Tour. You practise on a sample page, and each step ticks itself off once you've done it.
- **Gestures**:
  - swipe right → Subtask (Outdent on a subtask)
  - swipe left → Delete, Today or Tomorrow, +1 Day (overdue) or Deadline; a full swipe deletes on iPhone, never on the Mac
  - tap the circle → done (with Undo when it does more than tick the line)
  - long-press → full menu (Quick Edit, priority, deadline, move, tags, arrange, duplicate, details)
  - drag → re-rank (on Today's Ranked layout) or move across groups (on group headings)
  - Select (iPhone) or ⌘-click (Mac) → bulk actions
- **Views**: Today (ranked or grouped, filter chips), Upcoming (day by day), Priority, Quick Entry, every group as its own page, Tags, History (per-day pages with a streak), Recently Deleted (30 days), and full-text search across everything.
- **Tomorrow** moves a task onto tomorrow's plan. A small badge shows for how many days a task has been on the plan without getting done.
- **Import from Notes**: paste a daily note and Theo turns its checklists into tasks and its headings into groups.
- **Mac**: keyboard-first (⌘N, ⌘1–9, ⇧⌘O Overview, ⇧⌘A All Tasks, ⌘F, Space to complete, Return to edit, Esc to finish, ← / → to fold, ⌘[ / ⌘], ⌥⌘1–3 priority, ⌥⌘D Today, ⌥⌘L Tomorrow), ⌃⌥⌘N from any app, a menu-bar list in Today's order with quick entry, a Dock menu and a Settings window.
- **Apple Watch**: Today on your wrist. Tap a task to check it off, swipe for Tomorrow (Today on tasks that aren't on today) / details / delete, add tasks by voice (understands the same `morgen 17 Uhr !! @group` shortcuts, counted from Theo's day), plus Upcoming, Priority and every group. Ongoing tasks show "✓ logged today". Change priority, deadline, group or position from the task's details. It syncs straight through iCloud, so it works without the phone nearby.
- Light / Dark / System appearance, accent colors (Notes Yellow by default), Liquid Glass on iOS 26 and macOS 26.

## Tech

- SwiftUI + SwiftData, iOS 26 / macOS 26 / watchOS 26, Swift 5 language mode. `Theo` (iPhone/iPad) and `TheoMac` build one source tree; `TheoWatch` is embedded in the iOS app and shares the model and store code in `Shared/`.
- Sync: SwiftData's CloudKit mirroring into the user's private database (`.private("iCloud.at.binisoft.theo")`). It's free and needs no server. The schema is in `cloudkit/schema.ckdb`.
- Siri, Shortcuts and Spotlight use App Intents in the app itself (`App/Sources/Application/TheoIntents.swift`), on the same store as the app: no extension, entitlement or schema change.
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

- The repository is public, so GitHub's Mac runners are free, and Theo's workflows always use them (`runs-on: macos-26`): a public repository must never run on a self-hosted Mac. Private Binisoft apps can use one, see [docs/self-hosted-runner.md](docs/self-hosted-runner.md).
- `CI` runs on pushes to `main` and on PRs, and cancels superseded runs. It runs the TheoCore unit tests and builds iOS (with the watch app) and macOS. It publishes its status to the `ci-output` branch. Running it manually, or `[screenshots]` in the commit message, also captures iPhone and Watch screenshots, plus a Mac screenshot on GitHub's Macs.
- `TestFlight` (manual or a `v*` tag) archives and uploads iOS and macOS builds with automatic signing through the App Store Connect API key. No certificates or profiles are in the repo, and the build number is the run number. It needs the repository secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (team key "Binisoft CI").
- `CloudKit schema` (manual, one click) imports the schema into Development, then you deploy it to Production in the CloudKit Console. It needs `CLOUDKIT_MANAGEMENT_TOKEN`.

### Tour

The steps live in [`Packages/TheoCore/Sources/TheoCore/Tutorial.swift`](Packages/TheoCore/Sources/TheoCore/Tutorial.swift). Each step has text for touch and for the Mac, plus a goal the practice page has to reach. To teach a new feature, add a step with `since: N + 1` and bump `TutorialCatalog.version` to `N + 1`. People who already took the tour then see just the new steps as "What's new"; first-time users get everything. `make test` checks the catalog and the goals. The practice page (`App/Sources/Views/Tutorial/TutorialView.swift`) shows group headings during the group steps, and opens Plan in place for the Plan steps.

### Icon

`docs/icon/make_icon.py` holds the vector source: an abstract butler with a HUD ring, a bow tie, and a shirt front shaped like a check mark. `make icons` regenerates every PNG.
