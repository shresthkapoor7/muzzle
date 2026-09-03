# <img src="assets/muzzle.svg" width="38" height="38" alt="Muzzle" valign="middle"> Muzzle

A small native macOS menu-bar app that blocks selected domains for the whole Mac.

## Run it

From this project directory:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open "dist/Muzzle.app"
```

For local testing, use debug mode:

```sh
open -n "dist/Muzzle.app" --args --debug
```

Debug mode applies real website blocks using its own saved session data, hosts-file markers, and PF anchor. It never reads or changes the normal app’s session or rules, never sends a lock key or bypass event to Poke, and lets you end protection immediately without a key — including timed sessions. `-n` runs the debug instance beside the normal menu-bar app. It is intended only for local development; launch without `--debug` for the normal protected flow.

Before starting an **Until I end it** normal-mode lock, open **Start blocking…** and save your Poke bearer token in the **Poke API key** field. Muzzle stores it in your macOS Keychain, not in the app bundle or a project `.env` file. Timed sessions do not need a Poke key. Muzzle prevents a Poke key from being removed or replaced while an untimed lock is active.

In normal mode, when a session key is created, Muzzle posts this JSON to Poke and never displays or copies the code locally. The optional one-line “What are you working on?” field adds `working_on` only when filled in. If normal Muzzle reopens an already-active block, it asks for the same optional context before sending that session’s new key. Debug mode does not require a Poke token and never sends lock keys or bypass events.

```json
{"event":"lock_key","key":"123456","date":"2026-08-24"}
```

Muzzle is a menu-bar agent. It shows an outlined muzzle mark when inactive and a filled mark when it is blocking websites. It does not appear as a regular app in the Dock or Force Quit Applications list. Click the icon and choose **Start blocking…** to add the first domain, or **Manage protected websites…** while it is active. Additional websites can be added at any time, including during a bypass; they take effect when that bypass ends. Choose **For a set time** and enter any positive whole number of minutes to end protection automatically at that deadline; timed blocks do not notify Poke. The one-time session key is required to end untimed protection early.

Use `open "dist/Muzzle.app"` to launch it. Use `open -n "dist/Muzzle.app" --args --debug` for the separate local debug sandbox. Do not use `open -n` for normal launches: that option explicitly asks macOS to create a second instance. Normal launches still focus the existing menu-bar app.

## Create a downloadable DMG

Build the app, then package it as a drag-to-Applications disk image. DMG layout generation needs Python 3.10 or later:

```sh
python3 -m pip install -r scripts/requirements-dmg.txt
scripts/build-app.sh
MUZZLE_VERSION=1.0.0 scripts/package-dmg.sh
```

This creates `dist/Muzzle-1.0.0-arm64.dmg` on an Apple Silicon Mac (or an `x86_64` filename on an Intel Mac). The disk image uses a fixed installer layout with an Applications shortcut. The app and DMG are deliberately unsigned beyond an ad-hoc local signature, so macOS will require a first-launch confirmation from people who download it.

Eject any mounted Muzzle disk image before running the package script. This lets Finder record the background image against the final volume name.

Pushing a tag such as `v1.0.0` runs the **Release DMG** GitHub Actions workflow. It builds Apple Silicon and Intel DMGs and creates a GitHub Release containing both downloads. The workflow is not triggered by normal commits, so an unpublished change never replaces a released download.

Muzzle ignores direct quit requests such as Command-Q while protection is active. When inactive, its menu includes **Quit Muzzle**. In normal mode, it sends a fresh six-digit session code to Poke each time protection starts (or when it reopens an already-active session). Choose **End protection with key…** and supply that code to remove its hosts-file entries; Muzzle then remains open as an inactive menu-bar icon, ready to start again. It does not install itself as a login item. If Poke delivery fails, protection remains active and the error explains how to fix the delivery configuration. Force-quitting it in Activity Monitor stops the app but deliberately leaves the current hosts-file blocks in place.

Before blocking the first website, choose how many bypasses the session permits: 0, 1, 2, or 3 (default: 1). While protection is active and an allowance remains, choose **Bypass…** from the menu-bar menu and enter any positive whole number of minutes. Muzzle consumes one allowance, removes the block temporarily, and restores it automatically when the bypass ends. In normal mode, untimed sessions send Poke a `bypass` event with the selected number of minutes; timed sessions keep bypasses local. Debug-mode bypasses are always local. Quit remains unavailable for the whole bypass.

## How blocking works

Muzzle adds `127.0.0.1` and `::1` entries for each domain and its `www` subdomain between clearly labeled markers in `/etc/hosts`. It never replaces the rest of that file. It also resolves the domain’s current public IPv4/IPv6 addresses and loads an isolated macOS PF anchor that blocks outgoing connections to them.

Changing protection updates both system components in one administrator-authorized operation, so adding a website or ending protection results in one macOS permission request rather than separate requests for the firewall and hosts file. When a timed block reaches its deadline, macOS may ask for approval to remove those system-level rules. A permanently authorized root helper is a separate signed, privileged-service architecture; this local ad-hoc build deliberately does not install one.

The PF layer blocks the domain’s addresses resolved through this Mac’s configured DNS. This is a best-effort local firewall because large sites can rotate addresses or resolve differently through browser Secure DNS; reopen the blocker to refresh rules after a network change. Some CDNs share IP addresses between unrelated sites, so an IP-level block can occasionally affect another site on the same address. A Network Extension would provide hostname-precise filtering, but requires Apple’s Network Extension entitlement, code signing, and an installed system extension.

### Existing browser connections

Muzzle clears matching PF connection states when a block starts, but a browser can keep an already-open HTTP/2 or HTTP/3/QUIC connection if it was established to an address that the browser resolved through Secure DNS and the Mac’s resolver did not return. In that case, the website can remain usable in an existing browser session even though a fresh session is blocked. For X, block both `x.com` and `api.x.com`: `api.x.com` covers the feed API and makes the block more complete. Closing the existing browser session also forces it to reconnect through the current rules.

## Safety and recovery

- Normal Muzzle sends the session key to Poke when protection starts; it never displays or copies the key locally. Debug mode does neither.
- Ending protection removes only the `MUZZLE` section it created and leaves Muzzle open in standby.
- If the process is force-quit, reopening the app lets you manage its prior saved list again.
- The managed hosts-file section is human-readable and can be removed manually by an administrator if needed.
- If a session key is lost, recovery requires administrator access: remove Muzzle’s marked section from the hosts file and clear Muzzle’s PF anchor. Both steps are necessary to remove the block completely.
