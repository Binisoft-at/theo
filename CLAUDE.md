# Working on Theo

Theo is a Notes-style daily task manager for iPhone, iPad, Mac and Apple Watch (SwiftUI,
SwiftData + CloudKit, Liquid Glass, iOS/macOS/watchOS 26). The owner sends lists of
corrections and features, often titled "Theo Korrekturen vN", in German and English. The job:
build them, verify them, and get them onto TestFlight without the owner touching anything
except the one CloudKit step below.

## Layout

- `App/Sources`: iPhone/iPad/Mac app. `Shared`: models, store and logic shared with the watch.
  `Watch/Sources`: watch app. `Packages/TheoCore`: platform-free logic with Swift Testing
  tests (`make test`). Put anything testable there.
- `project.yml` (XcodeGen) generates the Xcode project; it's never committed.
- `cloudkit/schema.ckdb`: the CloudKit schema; every synced model field is listed there as
  `CD_<name>`.
- Docs for the owner: `README.md` (features), `docs/setup.md` (accounts, release),
  `docs/self-hosted-runner.md` (only for private Binisoft repos).

## The loop (no Mac in the session)

1. Change code, commit to `main` and push. Put `[screenshots]` in the message to get
   simulator screenshots.
2. CI (`.github/workflows/ci.yml`, GitHub's free Macs, as the repo is public) runs the
   TheoCore tests and builds iOS + watchOS + macOS. About 25 minutes.
3. Read the result with git, no API needed:
   `git fetch origin ci-output && git show FETCH_HEAD:status.txt` (it names the commit SHA),
   `errors.txt` (compiler errors), `test-tail.txt`, `shots/*.png` (screenshots) and logs.
   Poll in the background until `status.txt` contains the pushed SHA.
4. Fix and repeat until green. Look at the screenshots of whatever changed visibly.
   Screenshot launch arguments are in `AppModel.applyLaunchArguments` and the
   "Simulator screenshots" step of `ci.yml`. Add new ones for new screens.
5. Ship: once the last commit is green, push an empty commit to `main` whose message
   contains `[testflight]`. That starts TestFlight (`testflight.yml`, iOS with the watch app
   and macOS, build number = run number):
   `git commit --allow-empty -m "Release: <what's in it> [testflight]" && git push -u origin main`.
   (A `v*` tag works too, but this session's git access refuses tag pushes.)
   The result lands on the `ci-testflight` branch (`status.txt`: `success build N <sha>`).
   Builds reach the owner's TestFlight 10 to 20 minutes after a successful run.
6. Tell the owner briefly what changed and anything they have to do.

## CloudKit schema: the one manual step

TestFlight builds sync through CloudKit **Production**, and Apple only lets a person deploy the
schema there (CloudKit Console, signed in). So:

- Avoid schema changes. Put a new small synced value into `extrasRaw` (see
  `Shared/Model/Extras.swift`) with a typed accessor. That needs no deploy.
- When a real field is needed, add it to the model and to `cloudkit/schema.ckdb`.
  `cloudkit-schema.yml` imports it into Development on its own when that file changes on
  `main`. `ci-cloudkit/status.txt` then says `deploy-needed` (with
  `production-missing.txt`) or `in-sync`.
- Before shipping a build with new fields, ask the owner to click **Deploy Schema Changes**:
  https://icloud.developer.apple.com → CloudKit Database → `iCloud.at.binisoft.theo` →
  Development → Deploy Schema Changes… → Deploy.
- TestFlight refuses to upload while Production is missing fields (step "CloudKit Production
  has every field"), so a build can't break sync. If it stops there, ask for the deploy,
  then ship again.

## Conventions and pitfalls

- Swift 5 language mode. A `switch` or `if` expression can be returned or assigned, but not
  passed as an argument. `#expect` can't take mutating calls. Test helper type names must be
  unique across test files.
- `TheoColor` has no `.gray` (use `.graphite`). Glass: `.glassEffect`, `.glass` /
  `.glassProminent` button styles.
- Lists are ranked by `Matrix` score (importance 0.6, urgency 0.4). Equal scores keep a fixed
  order. New tasks get 0,25 PH by default (`PowerHours.defaultForNewTasks`).
- New gestures or features go into the tour: add `TutorialStep`s with `since: N + 1` and bump
  `TutorialCatalog.version`. Existing users then get a "What's new".
- Ongoing tasks (`isOngoing`, stored in `extrasRaw`) never finish: checking one off logs a
  finished copy (`loggedFor`) and the task stays.
- The repository is public: no secrets, personal task data or tester emails in commits, tests
  or CI output. Use made-up sample text in tests and demo data, never lines from the owner's
  notes. Never point it at a self-hosted runner.
- The owner's own tasks are imported in the app (Today → ⋯ → Import from Notes, "Replace
  everything"). Prepare that file in the scratchpad and send it to the owner; never commit it.
- No model names or identifiers in commits or code. Commits end with the attribution lines
  the session gives.
- Write for the owner in plain words: exact links and clicks, no jargon.
