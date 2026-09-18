# Muzzle

A native macOS menu-bar website blocker with a privileged background service.

## Build and setup

```sh
swift test
scripts/build-app.sh
open dist/Muzzle.app
```

Move the app to its permanent location, then choose **Set Up Blocking Service…** and approve administrator access. Building or opening the app does not install the daemon. End any legacy session first; setup refuses existing legacy protection. Terminal alternative: `sudo scripts/install-helper.sh /Applications/Muzzle.app`.

Normal mode requires the service. It starts at boot and owns normal-mode hosts/PF rules, session state, keys, bypass allowances, and deadlines. Routine blocking changes and bypass expiry do not request administrator permission. Quitting the menu-bar app leaves protection running.

This ad-hoc build uses a manually installed launch daemon, not SMAppService. No paid developer certificate is needed. Installation pins the exact hardened app signature and user ID, so replacing/rebuilding the app requires **Set Up Blocking Service…** again with administrator approval. A distributed Developer ID build could use SMAppService and a stable signing requirement as a separate packaging change. This is not “zero prompts forever.”

## Sessions and Poke

Choose **Start blocking…**, add a domain, select timed or untimed protection, and choose 0–3 daily bypasses. Additional domains can be added while blocking or bypassing. Timed sessions end automatically and cannot be ended early. Untimed sessions require the code delivered to Poke through **End protection with key…**.

Save your Poke bearer token before starting untimed protection. The app stores it in Keychain and caches authorized reads. For background restoration notifications, the service also retains the session's token in root-only state; ending the session removes that copy. The reusable Keychain token remains. Token changes/removal are disabled during untimed protection.

The service generates the unlock key and sends a `lock_key` event with `key` and `date` to Poke; it never returns the key to the UI. Optional work context adds `working_on`. Reopening resends the existing session key. Incorrect unlock attempts are rate-limited across restarts. Failed Poke delivery does not end protection.

**Bypass…** consumes an allowance and temporarily removes rules. The service checks saved deadlines at startup and every second while awake, catches up after sleep, and restores protection even with the UI closed. Failed system updates retry automatically; **Retry service update…** also requests a retry. A timed bypass cannot outlast its session. Untimed sessions send bypass notifications; background restoration sends best-effort `bypass_restoration` events with `restored` or `failed`. Network delivery never gates enforcement and is not guaranteed offline. There is no restoration authorization prompt to ignore.

The original allowance renews every 24 hours from session creation. Missed days do not accumulate; approved extras do not change the daily limit. Zero remains zero. Renewal does not interrupt protection or bypasses.

**Request extra bypass from Poke…** sends a service-generated approval code. Redeem through **Enter bypass approval code…**. Codes require confirmed delivery, expire after 15 minutes, permit five attempts, and work once. A new request replaces the previous code; restarts preserve it. Grants are saved before consuming codes. Allowance is capped at three.

## Debug mode

```sh
open -n dist/Muzzle.app --args --debug
```

Debug mode uses separate saved data, hosts markers, and PF rules, never normal service state. It applies real system rules with administrator prompts, sends nothing to Poke, and allows immediate ending without a key. Avoid `open -n` for normal launches.

## Service security

- Executable: `/Library/PrivilegedHelperTools/local.muzzle.helper`.
- Launch daemon: `/Library/LaunchDaemons/local.muzzle.helper.plist`.
- Authoritative state: `/Library/Application Support/MuzzleService` (root-owned directory 0700, files 0600).
- IPC: `/var/run/local.muzzle/control.sock`, restricted to the installed user inside a root-controlled directory.

The helper verifies UID and the pinned code signature using the peer's audit token; a bundle identifier alone is insufficient. The app verifies that the server is root. Hardened runtime is required without debugging/library-injection entitlements.

IPC accepts defined Muzzle actions, not arbitrary shell commands, paths, replacement state, or unconditional unlock/grant operations. System commands use fixed executables and argument arrays. Messages and connection waits are bounded; Poke networking runs outside the deadline queue. Installation preserves saved state and attempts rollback on replacement failure.

This prevents ordinary unprivileged clients from controlling the helper. It does not prevent an administrator intentionally removing protection.

## Blocking limitations

Muzzle inserts localhost IPv4/IPv6 mappings for each domain and its www subdomain inside its marked hosts section, preserving unrelated entries. An isolated `com.apple/muzzle` PF anchor blocks resolved IPs and clears matching connections. Hosts blocking is installed before PF updates; partial failures are reported and retried.

Root-owned cached DNS results support offline restoration. Addresses are not continuously refreshed. Rotating IPs, browser Secure DNS, existing connections to unknown IPs, and shared CDNs limit accuracy. Blocking shared IPs can affect unrelated sites. This is best-effort blocking, not hostname-aware filtering. For X, consider both x.com and api.x.com.

## Releases

The app checks stable GitHub Releases at launch and daily; **Check for Updates…** checks manually. Debug checks are manual. Downloads never end protection. Install updates after ending the session, then update the service's approved build.

```sh
python3 -m pip install -r scripts/requirements-dmg.txt
MUZZLE_VERSION=v1.2.3 scripts/build-app.sh
MUZZLE_VERSION=1.2.3 scripts/package-dmg.sh
```

Packaging requires Python 3.10+ and creates an architecture-specific DMG in dist. Builds are ad-hoc signed, not notarized; downloaded apps may require first-launch approval. Eject old Muzzle DMGs before packaging. Version tags trigger the release workflow; ordinary commits do not publish releases.

## Validation and recovery

`swift test` covers deadlines/restart, failed writes and rule updates, approvals, renewal, Keychain caching, and IPC rejection. Tests do not install the daemon or modify live system rules.

Privileged acceptance testing remains a separate step on a disposable Mac/VM: install; start a timed session and bypass; quit the UI; verify restoration at expiry; restart/reboot during bypass; verify saved deadlines; test sleep/wake, offline restoration, and denied setup approval. End protection and uninstall. Unit tests do not replace this test.

To uninstall after ending protection: `sudo scripts/uninstall-helper.sh`. It refuses active sessions/rules and archives service files in a root-only temporary directory.

Lost-key recovery requires an administrator: stop the launch daemon first, archive its root-owned session state, remove only Muzzle's marked hosts section, and clear only its PF anchor and rule file. Otherwise the service restores saved protection. Preserve unrelated hosts/PF entries. Restart the service only after recovery is complete. Legacy/debug state is separate.
