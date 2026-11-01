# Flait — Offline Flat Expenses (Flutter)

Flait stores its device identity, flat journal, local claims, votes and ledger in a local embedded database. Android uses Sembast in app support storage; Web uses Sembast over IndexedDB. Normal expense entry, contributions, approvals and ledger viewing need no network connection or cloud account.

## Internet sharing

Open **Settings → Open internet sync**. One person creates a private code; the other enters it. Keep both screens open until **Sync complete**. New members connect to the owner, who explicitly confirms admission before sending the history.

Sharing uses client-origin Supabase Realtime Broadcast as a live relay. Messages are AES-256-GCM encrypted on-device with a random 256-bit session key before transmission. The relay gets a hash-derived channel name and ciphertext, never the key or plaintext ledger. The app uses no database writes, triggers, presence, broadcast replay or offline server queue for sync. A relay/provider can still observe operational connection metadata; this is not a claim about all provider logging. Both devices must be online. Close the screen to disconnect. Codes expire after ten minutes and pair one session with one device.

This design uses **an encrypted live relay**, not a guaranteed direct peer-to-peer socket. It avoids NAT/TURN setup and never uses the server database as the source of financial truth.

## Financial authority and conflict handling

Every device has a local Ed25519 identity. The owner signs a linear hash-linked journal. Members sign their own proposals. Peers verify signatures, sequence, ancestry and membership before merging. Replayed IDs are ignored; divergent owner histories are rejected rather than silently overwritten.

The owner can finalize entries offline. Member requests and votes, and treasurer contributions/payments, stay in the device queue until exchanged with the owner. Only confirmed journal entries affect the shared balance and majority decisions. This single-writer model prevents independent offline treasurers from spending the same pool balance. There must be **one active owner device**. Restore an owner backup only as a replacement for the original device.

The default vote rule remains a strict majority of other members. Self-votes, duplicate votes, duplicate payments and insufficient-funds payments are rejected. Money is recorded in integer cents. Member activity is contributions minus reimbursements received, not a cost-allocation settlement.

## Backups and web installation

Export a `.flait` backup in Settings. Backups include the device signing identity and are encrypted on-device with a 12+ character password, PBKDF2-HMAC-SHA256 (210,000 iterations), a random salt and AES-256-GCM. There is no server recovery key. Restore on a fresh installation; current flat records are never silently replaced. The local database itself relies on device/browser protection and is not presented as a password-encrypted vault.

Android cloud auto-backup/device transfer is disabled for the app's data; use explicit encrypted exports. A browser/OS may have its own backup behavior outside the app's control.

For Web, open online once and wait for **Offline app ready**, then install/bookmark it. The custom service worker caches only app assets, never API responses, sync messages or credentials. The hosted Site retains its existing owner-private ChatGPT access gate. Clearing app/browser storage removes the local copy; a different browser or site origin is a separate device.

## Previous online version

The historical SQL migrations are retained for reference, not used by offline operation. One existing cloud expense was observed before conversion. It was not deleted or copied into source code. The owner can explicitly use **Settings → Import previous cloud records** to sign in to the old Flait account once and download the single flat they administer. This stores old history as a read-only archive and carries over a nonnegative pool balance. It never uploads local changes or deletes the original. Verify the archive and export an encrypted backup before requesting any cloud deletion.

Receipt uploads, notifications and allocation-based settlement remain outside this release.

## Build and verify

Flutter 3.47.8; dependencies are pinned/resolved in `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test
flutter test --dart-define=FLAIT_LIVE_TEST=true test/live_sync_test.dart
flutter build web --release --base-href / --no-web-resources-cdn
python3 scripts/offline_cache.py
```

Android:

```sh
flutter create . --project-name flait_expense_manage --platforms=android --no-pub
python3 scripts/remove_generated_test.py
python3 scripts/prepare_android.py
flutter build apk --debug
```

A debug APK is for device testing, not a Play Store release. Configure your own application ID and release signing for publication. Never check signing keys, database passwords or service-role credentials into source.

Tests cover persistence without a network client, stale-tab protection, queued proposals and idempotent merges, majority decisions, overdraft rejection, signature tampering, forks, encrypted backup recovery, UI widgets and an opt-in two-device live relay exchange. The live test uses synthetic in-memory records and creates no database rows.
