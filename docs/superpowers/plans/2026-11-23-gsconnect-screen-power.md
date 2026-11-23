# GSConnect Screen Power Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stuck dim-and-DND command with reliable panel off/on controls, session lock/unlock, power-profile selection, and system sleep/restart/shutdown commands.

**Architecture:** One small `screen-power` helper uses Mutter `PowerSaveMode`, validates real GNOME replies, and exits without creating a wake watcher or persistent state. Direct `loginctl` commands control session locking, `powerprofilesctl` entries reuse the existing CPU profile stack, and `systemctl` entries handle system actions. Nine declarative dconf entries replace the old screen-sleep entry.

**Tech Stack:** NixOS, Home Manager dconf/GVariant, Bash, GLib `gdbus`, power-profiles-daemon, systemd

**Spec:** `docs/superpowers/specs/2026-11-23-gsconnect-screen-power-design.md`

## Global Constraints

- Change only GNOME configuration; do not add this behavior to Hyprland.
- Never modify backlight or notification settings in the helper.
- Off/on must return immediately and must not rely on an idle-monitor signal.
- Parse GNOME 50's actual `(<0>,)` / `(<3>,)` integer-property responses.
- Do not invoke destructive power actions during verification.
- Do not claim a full-system activation when sudo is unavailable.
- Commit and merge only after explicit user authorization.

## Review Focus

- A correct mode response must not be rejected because its D-Bus representation lacks an `int32` label.
- Unsupported or ineffective DPMS must fail promptly rather than hanging or claiming success.
- Screen on must always be available and harmless without a prior screen off.
- Repeated off/on commands must not accumulate processes or change brightness/DND.
- Registered system actions must remain declarative and match their labels without being executed in tests.
- Lock/unlock must use the calling GSConnect session, with no agent-session dependency or hardcoded ID in production commands.

---

### Task 1: Screen power helper and nine GSConnect entries

**Files:**
- Modify: `desktop/gnome.nix`
- Create: `docs/superpowers/specs/2026-11-23-gsconnect-screen-power-design.md`
- Create: `docs/superpowers/plans/2026-11-23-gsconnect-screen-power.md`

**Interfaces:**
- Consumes: Mutter `PowerSaveMode` values 0 (on), 3 (off), and -1 (unsupported); power-profiles-daemon profiles `performance` and `power-saver`; systemctl actions `suspend`, `reboot`, and `poweroff`.
- Produces: `screen-power off|on` and GSConnect IDs `screen-off`, `screen-on`, `session-lock`, `session-unlock`, `power-performance`, `power-saver`, `system-sleep`, `system-restart`, and `system-shutdown`, with their corresponding user-facing labels.

- [x] **Step 1: Reproduce missing commands and incorrect behavior**

Verify the initial source lacks the new helper and system command entries. After live recovery reports arrive, change the D-Bus fixture to its actual `(<0>,)` representation and watch `on-only` reject a successful wake. Require `off-returns` to finish successfully and watch it time out while an idle watcher exists.

- [x] **Step 2: Implement the bounded, non-blocking helper**

Replace `screenSleep` with `screenPower`. Accept exactly one `off` or `on` argument; print usage and exit 2 otherwise. Parse the numeric property value, reject mode -1 before off, set the requested mode, read it back, and fail on mismatch. Never inspect or set backlight or notification settings and never register an idle watch.

- [x] **Step 3: Register all requested commands**

Install `screenPower` instead of `screenSleep`. Add screen off/on through absolute helper paths, performance/power-saver through the PPD package, and Sleep/Restart/Shut down through the systemd package. Remove the old screen-sleep entry.

- [x] **Step 4: Verify isolated behavior**

Run `off-returns`, `remote-on`, `replace-off`, `unsupported-dpms`, `reverted-dpms-set`, and `on-only` against the real built helper with only its D-Bus tool redirected to a controlled executable. Expected: all six pass, without touching the live display. Also pass shell syntax and invalid-argument checks.

- [x] **Step 5: Evaluate, build, and activate command settings**

Run `nix flake check --override-input local-ci path:./ci/local-ci-stub` and `nh os build .`; expected success for BLACK-BOX. Evaluate all nine dconf entries, write that exact value to the current session, and read it back. Run only the safe `screen-power on` (already mode 0) against real Mutter and confirm mode 0.

- [x] **Step 6: Review final state**

`git diff --check` passes. No screen or idle-monitor processes remain. One-time recovery restored mode 0, 50% backlight, and notification banners; these are not actions retained in the helper. No destructive sleep, restart, shutdown, or profile-change command was run during testing.

- [x] **Step 7: Add session lock and unlock**

First require evaluated dconf to include `session-lock`, `session-unlock`, `/bin/loginctl lock-session`, and `/bin/loginctl unlock-session`; watch it fail on the original seven-command list. Add those direct commands with labels Lock and Unlock, so loginctl selects its calling GSConnect session. Re-run the evaluated check successfully. Confirm `loginctl` supports both verbs, invoke unlock only against session 1 while `LockedHint=no`, and confirm it stays no without executing a real lock. Commit and push directly to main only at the user's explicit request.
