# Flait 3.0 implementation requirements

Implemented:
- Offline Android/Web local journal; no expense/ledger persistence on a server.
- Signed member proposals and hash-linked owner journal; automatic encrypted live exchange for admitted devices. Paired peers also relay verified owner transitions so a handoff reaches members with an older owner view.
- Equal, percentage and custom integer-cent splits with deterministic remainder allocation.
- Member dues reconcile shared costs, pool contributions/reimbursements and recorded personal settlements. Suggestions are accounting records, not money transfers.
- Expense corrections preserve history, reset votes and reject stale revision votes. Cancellation preserves the signed record; paid expenses cannot be cancelled.
- Reports/search by date range/member/category/status, monthly shortcut, confirmed category charts, CSV formula-injection protection and PDF export.
- Device-local monthly bill templates; explicit monthly submission with duplicate period protection, normal approval/payment flow.
- JPEG/PNG receipts capped at 500 KB and 16 megapixels. Local-only by default; explicit encrypted history sharing. Local-only receipts never enter sync packets.
- Active/revoked membership, immediate lost-device revocation preserving all dues, signed leave requests, owner-approved membership removal after open claims and balances are resolved, two-party owner handoff via recipient-signed acceptance.
- Phone replacement/recovery guide, encrypted backups, weekly in-app backup reminder, local receipts/preferences in backup, app PIN removed on restore.
- Android local document encryption with AES-256-GCM/device key in secure storage; safe plaintext migration with compaction. Browser relies on origin/device protection.
- PIN lock, optional OS fingerprint/device passcode, relock on background, retry cooldown; no biometric templates accessible to app. Backups remain password-encrypted.
- Dark theme, Urdu core labels/RTL and English technical fallback, bundled offline English/Arabic fonts.
- Visible per-device sync history, queue and foreground limitations; privacy policy and support route.
- Play identity/signing configuration, APK/AAB build workflow, policy/listing/graphics/checklist handoff.

Capacity: 6 MB signed shared history, 1.5 MB pending queue and 5 MB device-only receipts prevent creating a history too large for the live transport/backup envelope. Export backups and start a fresh accounting period before reaching the journal limit. No automatic history deletion or new-period reset is performed.

Release-owner actions: real-device testing/screenshots, Play account verification/declarations, provider metadata review and required closed testing. These cannot be represented as completed by unit tests or a local build. See release/play/release-checklist.md.

Old histories are readable; v2 records without split data remain unallocated. New v3 journals require updated peers. The prior cloud importer is not exposed in the active production UI; no historical cloud records are imported or deleted.
