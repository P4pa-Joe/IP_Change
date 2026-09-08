# IP Change

A native macOS menu bar app for switching network configurations. No Dock icon, no main window — everything lives in the menu bar.

## Features

- **Menu bar status item** showing every active network interface as `Name (hardware id)` (e.g. `Wi-Fi (en0)`), with a live-updating icon reflecting connection state:
  - `network` — connected, DHCP
  - `lock.fill` — connected, static IP
  - `network.slash` — disconnected
- **Per-interface details**: IP address, subnet mask, and router, read from `SystemConfiguration` and refreshed automatically via `SCDynamicStore` notifications (no polling).
- **Network profiles**: save named configurations (DHCP or static IP + subnet + router + DNS servers) and apply them to any interface in one click.
  - Profiles are stored as JSON in `~/Library/Application Support/IPChange/profiles.json`.
  - Import/export from the **Edit Profiles** window.
  - IP address, subnet mask, router, and DNS fields are validated before a profile can be saved, so a typo surfaces immediately instead of as an opaque `networksetup` failure later.
  - Applying a profile verifies the interface stayed reachable afterward (ping, falling back to an ARP lookup for gateways that block ICMP) and **automatically rolls back** to the previous configuration if not — skipped entirely for profiles with no gateway configured (e.g. point-to-point links), since there's nothing meaningful to check.
  - If an active SSH or screen-sharing session appears to be using the interface you're about to reconfigure, you're asked to confirm first.
- **Scan Network**: a ping/ARP sweep of the interface's subnet, with mDNS/DNS hostname resolution, shown as live-updating native submenu items (IP, MAC, hostname) — no separate window. Each discovered host is also probed on the well-known HTTP/HTTPS/SSH/Telnet ports; hovering its submenu offers quick-connect actions (open in browser, or connect via Terminal.app) only for the protocols whose port actually answered.
- **Preferences**: launch at login, toggle the "profile applied" notification, and adjust how long to wait before verifying reachability / rolling back.
- **About**: author, contact, app version, build date, and the Swift version it was built with.

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode command line tools

## Build & run

For development:

```sh
swift build
swift run
```

For a real, double-clickable app (also needed for **Launch at Login**, which requires a proper bundle identifier):

```sh
./build-app.sh
```

This builds in release mode, assembles `IP Change.app` (icon, `Info.plist`, ad-hoc code signature), quits any previously running instance, and reveals the result in Finder.

The app always runs as an accessory (menu bar only) process — it won't appear in the Dock or Cmd+Tab, whether launched via `swift run` or as a built `.app`.

## Testing

```sh
swift test
```

Unit tests live in `Tests/IPChangeTests` and currently cover `IPv4Subnet`'s CIDR math — the one piece of the app with no dependency on system state, so it's fully deterministic to test.

## How network changes are applied

Profile changes call `networksetup` directly, with **no privilege elevation**. `networksetup`'s write commands (`-setdhcp`, `-setmanual`, `-setdnsservers`) succeed without a password prompt as long as you're an admin user in the active GUI session — the same reason System Settings' Network pane never re-prompts. A non-admin account, or a non-interactive session, will see the real permissions error from `networksetup` surfaced as an alert instead of failing silently.

## Project layout

| File | Responsibility |
|---|---|
| `main.swift` | Entry point; sets the app as a menu-bar-only accessory. |
| `AppDelegate.swift` | Status item, menu construction, wiring between everything else. |
| `NetworkMonitor.swift` | Reads active interfaces, IPv4 state, and config method (DHCP/static) via `SystemConfiguration`; notifies on change. |
| `NetworkConfigurator.swift` | Runs `networksetup` to read/apply configuration; reachability checks (ping + ARP fallback). |
| `NetworkProfile.swift` / `ProfileStore.swift` | Profile model and JSON persistence/import/export. |
| `ProfileApplier.swift` | Orchestrates applying a profile: remote-session confirmation, apply, verify, auto-rollback, user-facing alerts. |
| `ProfilesWindowController.swift` | The "Edit Profiles" create/edit/delete UI. |
| `PreferencesWindowController.swift` | The "Preferences" window UI. |
| `AboutWindowController.swift` | The "About" window UI: icon, name, version/build/Swift info, author contact. |
| `AppPreferences.swift` | UserDefaults-backed settings (notification toggle, rollback delay). |
| `LoginItemManager.swift` | Launch-at-login registration via `ServiceManagement` (`SMAppService`) — only functional from a built `.app`. |
| `RemoteSessionDetector.swift` | Heuristic (`lsof`) check for active SSH/Screen Sharing sessions. |
| `NetworkScanner.swift` / `IPv4Subnet.swift` / `ScanSession.swift` / `ScanMenuController.swift` | Subnet enumeration, ping/ARP sweep, mDNS hostname resolution, and the live "Scan Network" submenu. |
| `HostConnector.swift` | Quick-connect actions (HTTP/HTTPS/SSH/Telnet) for scanned hosts — always targets the numeric IP, never the (network-supplied, untrusted) hostname. |
| `NSMenuItem+Info.swift` | Non-highlighting, non-actionable menu row helper (used for read-only info like IP/Subnet/Router). |

## Packaging

`build-app.sh` reuses `Resources/AppIcon.icns` if present and sets the bundle identifier to `com.ipchange.app`. Edit `APP_VERSION` at the top of the script to change the version stamped into `CFBundleVersion` / `CFBundleShortVersionString`. It also stamps the current date and the local `swift --version` into custom `Info.plist` keys, which the About window reads to show the build date and Swift version — both fields fall back to "unknown" under `swift run`, which has no `Info.plist` to read from.
