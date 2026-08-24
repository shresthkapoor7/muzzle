# Website Blocker

A small native macOS menu-bar app that blocks selected domains for the whole Mac.

## Run it

From this project directory:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open "dist/Website Blocker.app"
```

Website Blocker is a menu-bar agent. It adds a small outlined circle to the macOS menu bar when inactive and a raised-hand icon when it is blocking websites. It does not appear as a regular app in the Dock or Force Quit Applications list. Click the icon and choose **Start blocking…** to add the first domain, or **Manage protected websites…** while it is active. The protected list is read-only during a session; the one-time session key is required to end protection and remove its hosts-file entries.

Use `open "dist/Website Blocker.app"` to launch it. Do not use `open -n`: that option explicitly asks macOS to create a second instance. The bundle also declares itself single-instance, so a normal launch focuses the existing menu-bar app.

The app has no ordinary Quit item and ignores direct quit requests such as Command-Q. It displays a pasteable one-time six-digit session code only when protection becomes active (or when it reopens an already-active session). Choose **End protection with key…** and supply that code to remove this app’s hosts-file entries and exit normally. Force-quitting it in Activity Monitor stops the app but deliberately leaves the current hosts-file blocks in place.

## How blocking works

Website Blocker adds `127.0.0.1` and `::1` entries for each domain and its `www` subdomain between clearly labeled markers in `/etc/hosts`. It never replaces the rest of that file. It also resolves the domain’s current public IPv4/IPv6 addresses and loads an isolated macOS PF anchor that blocks outgoing connections to them.

Changing protection updates both system components in one administrator-authorized operation, so adding a website or ending protection results in one macOS permission request rather than separate requests for the firewall and hosts file. A permanently authorized root helper is a separate signed, privileged-service architecture; this local ad-hoc build deliberately does not install one.

The PF layer means Chrome’s Secure DNS/DoH cannot bypass the block: Chrome may resolve a domain privately, but it cannot connect to that domain’s resolved addresses. This is still a best-effort local firewall because large sites can rotate addresses; reopen the blocker to refresh rules after a network change. Some CDNs share IP addresses between unrelated sites, so an IP-level block can occasionally affect another site on the same address. A Network Extension would provide hostname-precise filtering, but requires Apple’s Network Extension entitlement, code signing, and an installed system extension.

## Safety and recovery

- The app shows the session key at startup and lets you reveal it again while it is running.
- Normal exit removes only the `WEBSITE_BLOCKER` section it created.
- If the process is force-quit, reopening the app lets you manage its prior saved list again.
- The managed hosts-file section is human-readable and can be removed manually by an administrator if needed.
- If a running session’s code is lost, run `"dist/Website Blocker.app/Contents/MacOS/WebsiteBlocker" --remove-website-blocker-hosts` to remove only Website Blocker’s marked entries. macOS will request administrator approval.
