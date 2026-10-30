# Theo – Binisoft setup

| | |
| --- | --- |
| App Store name | **Theo - Your Task Buddy** |
| Home-screen name | Theo |
| GitHub repo | `Binisoft-at/theo` (private) |
| Bundle ID (iOS + macOS) / SKU | `at.binisoft.theo` |
| Own iCloud container | `iCloud.at.binisoft.theo` |
| Shared iCloud container | `iCloud.at.binisoft.shared` (already exists, just tick it) |
| Shared App Group | `group.at.binisoft.shared` (already exists, just tick it) |
| Shared keychain group | `$(AppIdentifierPrefix)at.binisoft.shared` (no portal step) |

Theo has no watch app or extensions yet. Future ones follow `at.binisoft.theo.watchkitapp` and
`at.binisoft.theo.<extension>`, each needs App Groups ticked. All identifiers are defined in
[`Config/Base.xcconfig`](../Config/Base.xcconfig).

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

TestFlight builds use the Production environment, so it needs the schema first:

1. Create the Development schema with **one** of these:
   - Run the app once from Xcode (`make open`, set your team in `Config/Local.xcconfig`, ⌘R) and add a task.
   - Or add a `CLOUDKIT_MANAGEMENT_TOKEN` repository secret and run **Actions → CloudKit schema**.
2. https://icloud.developer.apple.com → **CloudKit Database** → container `iCloud.at.binisoft.theo`
   → environment **Development** → **Deploy Schema Changes…** → **Deploy**.

## 5. Release

- **Actions → TestFlight → Run workflow** (or push a `v*` tag). Signing is automatic through the
  API key, and the build number is the workflow run number.
- **Actions → CI** runs on every push to `main` and on PRs: TheoCore unit tests plus iOS and
  macOS builds.

## Data rules

- Theo's data lives only in `iCloud.at.binisoft.theo` (SwiftData `.private(...)`,
  `groupContainer: .none`). The shared container is for small cross-app events and summaries,
  never Theo's schema.
- Data in the old `iCloud.com.erblinkastrati.theo` container doesn't move. To carry open tasks
  over: old app → Today → ⋯ → Share as Text, then new app → Today → ⋯ → Import from Notes.
