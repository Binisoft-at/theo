# Building on our own Mac (self-hosted runner)

GitHub Free gives the Binisoft organisation one shared allowance of Actions minutes per month,
and Mac minutes count 10×. Once it's used up, GitHub stops starting jobs ("recent account
payments have failed or your spending limit needs to be increased"). So the Mac jobs of every
Binisoft app run on one of our own Macs instead. That costs nothing, and the code stays
private.

The Mac is set up **once for the whole organisation**. Every private Binisoft repository can
then use it. Each app only needs the small workflow changes listed under
[Per app](#per-app-workflow-changes).

**Public repositories don't need this.** GitHub's Macs are free for them, so Theo (which is
public) stays on `macos-26`. Never point a public repository at the self-hosted Mac: anyone's
pull request could then run code on it.

## What the Mac needs

- macOS with the current **Xcode** from the Mac App Store (26 or newer), opened once.
- The **iOS** and **watchOS** simulators: Xcode → Settings → Components → Get.
- About 40 GB free for Xcode, the simulators and builds.
- It has to be awake for builds to run. Jobs wait in the queue for up to 24 hours, so a sleeping
  Mac only delays them.

## One-time setup

### 1. A separate Mac account for builds

Anyone who can push to a Binisoft repository can run code on the runner. A separate account
keeps that code away from your own files, browser and keychain. The signing certificates the
TestFlight workflow creates also land in that account's keychain, not yours.

1. System Settings → **Users & Groups** → **Add User…**
   - New User: **Standard**
   - Full Name: `GitHub Runner`
   - Account Name: `runner`
   - Set a password and keep it in your password manager.
2. System Settings → **Control Center** → **Fast User Switching** → **Show in Menu Bar**.
3. Keep the Mac awake on power:
   - MacBook: System Settings → **Battery** → **Options…** → turn on **Prevent automatic sleeping
     on power adapter when the display is off**. Closing the lid still sleeps it unless an
     external display is connected.
   - Desktop Mac: System Settings → **Energy** → turn on **Prevent automatic sleeping when the
     display is off**.

### 2. Get the runner commands (in **your** account)

1. Open https://github.com/organizations/Binisoft-at/settings/actions/runners/new
2. Choose **macOS**, and the architecture of your Mac: **ARM64** for Apple silicon (M1 or
   later), **x64** for Intel.
3. Hand the commands to the runner account through the Shared folder. The clipboard isn't
   shared between Mac accounts, and the runner account shouldn't sign in to GitHub. In Terminal:
   - Click the copy button of the **Download** box, then run:
     ```bash
     { pbpaste; echo; } > /Users/Shared/runner-setup.sh
     ```
   - In the **Configure** box, select only the line that starts with `./config.sh`, copy it,
     then run:
     ```bash
     { pbpaste; echo; } >> /Users/Shared/runner-setup.sh
     ```

   The token in that line works for one hour and can only register a runner.

### 3. Install the runner (in the **runner** account)

1. Menu bar → user switcher → **GitHub Runner**, and log in. Skip the Apple Account sign-in
   and the other setup screens.
2. Open Terminal and run:
   ```bash
   cd ~ && bash /Users/Shared/runner-setup.sh
   ```
   Press **Return** at every question. That keeps the Default group, the computer's name,
   the labels `self-hosted, macOS, ARM64` (or `X64`) and `_work`.
3. Install it as a service so it starts whenever this account is logged in:
   ```bash
   cd ~/actions-runner && ./svc.sh install && ./svc.sh start
   ```
4. Switch back to your own account (menu bar → your name). The runner account stays logged in
   in the background, and that's what keeps the runner running.
5. In your account, delete the file with the token:
   ```bash
   rm /Users/Shared/runner-setup.sh
   ```

### 4. Check

- https://github.com/organizations/Binisoft-at/settings/actions/runners should list the Mac
  as **Idle**.
- https://github.com/organizations/Binisoft-at/settings/actions/runner-groups → **Default**:
  leave **Allow public repositories** off. A public repository would let anyone's pull request
  run code on this Mac.

### After a restart

The runner only runs while the runner account is logged in. After a restart, log in to
**GitHub Runner** once, then switch back to your account. Queued jobs start by themselves.

### Updating, removing

- The runner updates itself.
- After a big Xcode update, open Xcode once in your own account so it can finish installing its
  components. Also check Settings → Components for the matching iOS and watchOS simulators.
- To remove the runner: in the runner account, run
  `cd ~/actions-runner && ./svc.sh stop && ./svc.sh uninstall`, then delete the runner on the
  Runners page.

## Switching back to GitHub's Macs

Each private repository can go back to GitHub-hosted Macs for a while, for example when the
allowance has reset and your Mac is away. Set the repository variable `MAC_RUNNER` to
`"macos-26"`, including the quotes: Settings → Secrets and variables → Actions →
**Variables**. Delete the variable to use your own Mac again. (Theo's workflows default to
`"macos-26"` because it's public.)

## Per app: workflow changes

Every Binisoft app's Mac workflows need these changes to run on the runner. Theo's
[`.github/workflows`](../.github/workflows) and [`scripts/ci`](../scripts/ci) are the reference.

1. **Runner.** Replace `runs-on: macos-26` with:
   ```yaml
   runs-on: ${{ fromJSON(vars.MAC_RUNNER || '["self-hosted", "macOS"]') }}
   ```
2. **Xcode without sudo.** The runner account isn't an admin, so `sudo xcode-select` fails.
   Copy [`scripts/ci/select-xcode.sh`](../scripts/ci/select-xcode.sh) and replace the
   "Select Xcode" step with `run: scripts/ci/select-xcode.sh`. It exports `DEVELOPER_DIR` and
   `XCBEAUTIFY`.
3. **No hard dependency on Homebrew tools.** Pipe builds through `$XCBEAUTIFY` (it falls back
   to `cat`) instead of calling `xcbeautify` directly.
4. **No screen captures on the Mac itself.** Guard steps that use `screencapture`, `osascript`
   or `open` on the Mac app with `runner.environment == 'github-hosted'`. On the runner they
   would capture that Mac's screen. Simulator screenshots (`simctl io … screenshot`) are fine.
5. **Simulators.**
   - Use `xcrun simctl boot "$UDID" || true`, since a simulator may still be booted.
   - Create a simulator when none matches; a new account has none.
   - Shut them down at the end:
     ```yaml
     - name: Clean up (self-hosted)
       if: always() && runner.environment == 'self-hosted'
       continue-on-error: true
       run: xcrun simctl shutdown all || true
     ```
6. **Signing.**
   - Keep the "revoke this run's development certificate" step for GitHub's runners only:
     `if: always() && runner.environment == 'github-hosted'`.
   - The runner keeps its keychain, so it reuses a single certificate.
7. **No leftovers.**
   - Give `xcodebuild archive` a `-derivedDataPath` inside `$RUNNER_TEMP`, which is emptied
     after every job.
   - Write secrets (API keys) only to `$RUNNER_TEMP`, and delete them in an `if: always()` step.
   - Remove a saved `cktool` management token at the end:
     `xcrun cktool remove-token --type management || true`.

Linux jobs (`runs-on: ubuntu-latest`) can stay on GitHub. They're cheap and fit easily in the
free allowance once it resets. Move them to the Mac only if they're plain scripts that don't need
Docker or Linux.
