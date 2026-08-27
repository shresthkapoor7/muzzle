# <img src="assets/muzzle.svg" width="38" height="38" alt="Muzzle" valign="middle"> Muzzle

A small native macOS menu-bar app that blocks selected domains for the whole Mac.

## Run it

From this project directory:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open "dist/Muzzle.app"
```

Before starting protection, put your Poke bearer token in the project’s local `.env` file:

```sh
POKE_API_KEY=your-token-here
```

The file is ignored by Git. When a session key is created, Muzzle posts this JSON to Poke and never displays or copies the code locally. The optional one-line “What are you working on?” field adds `working_on` only when filled in. If Muzzle reopens an already-active block, it asks for the same optional context before sending that session’s new key:

```json
{"event":"lock_key","key":"123456","date":"2026-08-24"}
```

Muzzle is a menu-bar agent. It shows an outlined muzzle mark when inactive and a filled mark when it is blocking websites. It does not appear as a regular app in the Dock or Force Quit Applications list. Click the icon and choose **Start blocking…** to add the first domain, or **Manage protected websites…** while it is active. Choose a 30-, 40-, or 60-minute block to end protection automatically at that deadline; timed blocks do not notify Poke. The protected list is read-only during a session; the one-time session key is required to end untimed protection early.

Use `open "dist/Muzzle.app"` to launch it. Do not use `open -n`: that option explicitly asks macOS to create a second instance. The bundle also declares itself single-instance, so a normal launch focuses the existing menu-bar app.

Muzzle ignores direct quit requests such as Command-Q while protection is active. When inactive, its menu includes **Quit Muzzle**. It sends a fresh six-digit session code to Poke each time protection starts (or when it reopens an already-active session). Choose **End protection with key…** and supply that code to remove its hosts-file entries; Muzzle then remains open as an inactive menu-bar icon, ready to start again. It does not install itself as a login item. If Poke delivery fails, protection remains active and the error explains how to fix the delivery configuration. Force-quitting it in Activity Monitor stops the app but deliberately leaves the current hosts-file blocks in place.

While protection is active, choose **Bypass…** from the menu-bar menu and select 5, 10, or 15 minutes. Muzzle removes the block temporarily, restores it automatically when the bypass ends, and sends Poke a `bypass` event with the selected number of minutes. Quit remains unavailable for the whole bypass.

## How blocking works

Muzzle adds `127.0.0.1` and `::1` entries for each domain and its `www` subdomain between clearly labeled markers in `/etc/hosts`. It never replaces the rest of that file. It also resolves the domain’s current public IPv4/IPv6 addresses and loads an isolated macOS PF anchor that blocks outgoing connections to them.

Changing protection updates both system components in one administrator-authorized operation, so adding a website or ending protection results in one macOS permission request rather than separate requests for the firewall and hosts file. When a timed block reaches its deadline, macOS may ask for approval to remove those system-level rules. A permanently authorized root helper is a separate signed, privileged-service architecture; this local ad-hoc build deliberately does not install one.

The PF layer means Chrome’s Secure DNS/DoH cannot bypass the block: Chrome may resolve a domain privately, but it cannot connect to that domain’s resolved addresses. This is still a best-effort local firewall because large sites can rotate addresses; reopen the blocker to refresh rules after a network change. Some CDNs share IP addresses between unrelated sites, so an IP-level block can occasionally affect another site on the same address. A Network Extension would provide hostname-precise filtering, but requires Apple’s Network Extension entitlement, code signing, and an installed system extension.

## Safety and recovery

- Muzzle sends the session key to Poke when protection starts; it never displays or copies the key locally.
- Ending protection removes only the `MUZZLE` section it created and leaves Muzzle open in standby.
- If the process is force-quit, reopening the app lets you manage its prior saved list again.
- The managed hosts-file section is human-readable and can be removed manually by an administrator if needed.
- If a session key is lost, recovery requires administrator access: remove Muzzle’s marked section from the hosts file and clear Muzzle’s PF anchor. Both steps are necessary to remove the block completely.
