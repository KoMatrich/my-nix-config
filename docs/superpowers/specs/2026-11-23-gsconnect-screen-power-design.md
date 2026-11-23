# GSConnect screen and power commands

## Intent
Provide reliable phone commands for independent panel power control, device power profiles, session lock/unlock, and system sleep/restart/shutdown. The phone must always have a working wake command and no helper may leave the user with a dark panel or a stuck background process.

## Goals, non-goals, anti-goals
- Add nine entries: **Screen off**, **Screen on**, **Lock**, **Unlock**, **Power: performance**, **Power: power saver**, **Sleep**, **Restart**, and **Shut down**.
- Power the panel off completely and restore its previous brightness when powered on.
- Return from every panel command immediately; do not require a successful idle-monitor signal or leave stateful wake watchers behind.
- Reuse power-profiles-daemon for CPU profiles and `systemctl` for system power actions.
- Do not change notification settings or backlight in the helper; remove the old dim-and-DND behavior.
- Do not alter monitor layout, lock the session, or target the Hyprland specialisation.

## Constraints
This is GNOME 50 on Wayland, configured in `desktop/gnome.nix`, with commands sent as the logged-in user. Real `gdbus` output for integer properties is `(<0>,)` / `(<3>,)`, which the helper and tests both handle. `system/power.nix` enables power-profiles-daemon and the required CPU profiles are advertised. Evaluate and build the existing NixOS flake, then apply the evaluated command list to the active session.

## Approaches
- **Chosen: Mutter `PowerSaveMode`.** Set the native D-Bus property to 3 for off and 0 for on, verify the resulting value, and return immediately. Backlight remains untouched, so its previous level is preserved. Do not use a blocking idle watcher after that approach reproduced a stuck dark screen.
- **Chosen: `powerprofilesctl`.** Call `set performance` / `set power-saver` through the installed package, keeping integration with GNOME Quick Settings and the CPU clamp service.
- **Chosen: `systemctl`.** Call `suspend`, `reboot`, and `poweroff`; the desktop's existing polkit session handles authorization without embedding sudo in commands.
- **Rejected fallback: `brightnessctl --save/--restore`.** It produces a black active display rather than completely powering the panel off.

## Implementation
`screen-power off` and `screen-power on` are independent and non-blocking. The helper parses Mutter's real integer-property representation, rejects unsupported or ineffective DPMS transitions, and holds no state. Declaratively register these commands, two direct powerprofilesctl commands, and the three direct systemctl commands; remove the old `screen-sleep` package and command. As one-time recovery only, restore the old command's minimum backlight to 50% and notification banners to true, then apply the corrected command list so the phone can wake the panel immediately.

## Session locking
Use separate direct `loginctl lock-session` and `loginctl unlock-session` commands from the systemd package. GSConnect Run Command shares the calling GNOME session, so no session ID is hardcoded and no helper is needed. This replaces GNOME's less portable ScreenSaver D-Bus alternative. Verification includes `loginctl unlock-session 1` only while session 1 is already `LockedHint=no`, confirming API/authorization support without locking the display.

## Verification
Use a mock matching GNOME's real D-Bus responses to verify prompt off/on, remote wake, repeated commands, unsupported DPMS, and ignored mode requests. Check shell syntax and invalid arguments. Evaluate all nine command definitions, confirm PPD/systemctl support without invoking destructive power actions, run the flake and full-system builds, then read back the live command list and safe on-mode transition.
