# Theo – Binisoft setup

| | |
| --- | --- |
| App Store name | **Theo - Your Task Buddy** |
| Home-screen name | Theo |
| GitHub repo | `Binisoft-at/theo` (private) |
| Bundle ID (iOS + macOS) / SKU | `at.binisoft.theo` |
| Watch app bundle ID | `at.binisoft.theo.watchkitapp` (ships inside the iOS app, no extra App Store record) |
| Own iCloud container | `iCloud.at.binisoft.theo` |
| Shared iCloud container | `iCloud.at.binisoft.shared` (already exists, just tick it) |
| Shared App Group | `group.at.binisoft.shared` (already exists, just tick it) |
| Shared keychain group | `$(AppIdentifierPrefix)at.binisoft.shared` (no portal step) |

Future extensions follow `at.binisoft.theo.<extension>`, each with App Groups ticked. All
identifiers are defined in [`Config/Base.xcconfig`](../Config/Base.xcconfig).

## 1. Apple Developer portal

1. https://developer.apple.com/account/resources/identifiers/list → blue **+** → **iCloud Containers**
   → **Continue** → Description `Theo`, Identifier `iCloud.at.binisoft.theo` → **Continue** → **Register**.
2. **+** → **App IDs** → **Continue** → **App** → **Continue** → Description `Theo`, Bundle ID
   **Explicit** `at.binisoft.theo` → tick **App Groups**, **iCloud** (with CloudKit) and
   **Push Notifications** (used by CloudKit sync) → **Continue** → **Register**.
3. Click **Theo** (`at.binisoft.theo`) in the list:
   - **App Groups** → **Configure** → tick `group.at.binisoft.shared` → **Continue**
   - **iCloud** → **Configure** → tick `iCloud.at.binisoft.theo` **and** `iCloud.at.binisoft.shared` → **Continue**
   - **Save** (top right) → **Confirm**
4. Watch app: back to the list → **+** → **App IDs** → **Continue** → **App** → **Continue** →
   Description `Theo Watch`, Bundle ID **Explicit** `at.binisoft.theo.watchkitapp` → tick
   **App Groups**, **iCloud** (with CloudKit) and **Push Notifications** → **Continue** → **Register**.
   Then click **Theo Watch** in the list and configure it exactly like step 3 (same App Group,
   same two containers) → **Save** → **Confirm**.

## 2. App Store Connect

1. Old record first: https://appstoreconnect.apple.com/apps → old Theo (`com.erblinkastrati.theo`)
   → **App Information** → Name `Theo Legacy` → **Save**. This frees the real name.
2. **Apps** → **+** → **New App** → platforms **iOS** + **macOS** → Name `Theo - Your Task Buddy`
   → Bundle ID `at.binisoft.theo` → SKU `at.binisoft.theo` → User Access **Full Access** → **Create**.
3. New app → **TestFlight** → **Internal Testing** → **+** → group `Binisoft Team` → **Create**
   → turn **Automatic Distribution** on → add the testers.
4. Once the first `at.binisoft.theo` build is on TestFlight, delete the old record
   (old app → **App Information** → scroll down → **Remove App**).

## 3. GitHub

1. Repo: `Binisoft-at/theo`, private. If you're moving the existing repo: Settings → **Transfer
   ownership** → `Binisoft-at`, name `theo`.
2. **Repository** secrets (Settings → Secrets and variables → Actions → **New repository secret**),
   all from the team key "Binisoft CI" (Admin). Org secrets don't reach private repos on GitHub Free.
   - `APPLE_TEAM_ID`
   - `ASC_KEY_ID`
   - `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: the whole `.p8` file, including the BEGIN/END lines

## 4. CloudKit schema (before the first syncing TestFlight build)

TestFlight builds use the Production environment, so it needs the schema first.

1. Needs the repository secret `CLOUDKIT_MANAGEMENT_TOKEN` once. If it's missing:
   https://icloud.developer.apple.com → pick the Binisoft team → **Settings** → **Tokens & Keys**
   → **+** next to *Management Tokens* → name `Theo CI` → **Create** → copy it → GitHub repo →
   Settings → Secrets and variables → Actions → **New repository secret**.
2. https://github.com/Binisoft-at/theo/actions/workflows/cloudkit-schema.yml → **Run workflow**
   → **Run workflow**. It imports `cloudkit/schema.ckdb` into Development (about a minute).
3. https://icloud.developer.apple.com → **CloudKit Database** → container `iCloud.at.binisoft.theo`
   → environment **Development** → **Deploy Schema Changes…** → **Deploy**. The run's summary
   repeats this step.

Running a Debug build from Xcode once also works instead of step 2: it pushes the full schema
on first launch (`Persistence.initializeCloudKitSchemaIfNeeded`).

### Schema changes

Whenever `cloudkit/schema.ckdb` gains fields (like the estimates, matrix, reminders,
subprojects and planned-day fields), run step 4 again (CloudKit schema workflow → Deploy Schema Changes) before
installing a build that uses them. Otherwise the new fields can't sync in Production.

## 5. Release

- https://github.com/Binisoft-at/theo/actions/workflows/testflight.yml → **Run workflow** →
  **Run workflow** (or push a `v*` tag). Signing is automatic through the API key, the build
  number is the workflow run number, and the iOS build carries the watch app. The builds show up
  in TestFlight about 10–20 minutes after the run finishes.
- Once they're there, delete the old record (section 2, step 4).
- Each run revokes the throwaway development certificate it created (fresh runners can't keep
  one). If a run still fails with "maximum number of certificates", revoke the leftover CI
  certificates once: https://developer.apple.com/account/resources/certificates/list → each
  **Development** certificate created by the API key (not your personal ones) → **Revoke**.
- **Actions → CI** runs on every push to `main` and on PRs: TheoCore unit tests plus iOS,
  watchOS and macOS builds. Add `[screenshots]` to a commit message to also get screenshots.

## Data rules

- Theo's data lives only in `iCloud.at.binisoft.theo` (SwiftData `.private(...)`,
  `groupContainer: .none`), on every device including the watch, which syncs on its own. The shared container is for small cross-app events and summaries,
  never Theo's schema.
- Data in the old `iCloud.com.erblinkastrati.theo` container doesn't move. To carry open tasks
  over: old app → Today → ⋯ → Share as Text, then new app → Today → ⋯ → Import from Notes.
