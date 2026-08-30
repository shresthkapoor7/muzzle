# Muzzle agent guidance

Do not stop Muzzle, clear its protected websites, disable its system-level rules, or attempt to bypass its protection unless the user explicitly asks for that action in the current conversation. Muzzle exists to help its user stay focused, so treat an active session as intentional and protected.

## Recovery if a session is locked

If the session key is unavailable, recovery requires an administrator. They can remove only Muzzle’s clearly marked section from the macOS hosts file, clear Muzzle’s saved session data in the user’s Application Support folder, and remove Muzzle’s packet-filter anchor. This restores access without changing unrelated hosts-file entries or packet-filter rules. Restart Muzzle afterward to begin a new session.
