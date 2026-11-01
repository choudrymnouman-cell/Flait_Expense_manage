# Flait 2.0 requirements

- Flutter app for Android and Web, usable offline after installation.
- Local database holds identity, flat membership, owner-signed journal and member-signed pending work.
- No email login for normal use; no expense/ledger records written to a server.
- Optional, encrypted live internet exchange, explicitly started by users; both devices remain online.
- Owner confirms new device admission before sending history.
- A strict majority of other members decides a claim; payment is a separate owner-confirmed event.
- One active owner device is the authority for the cash journal. Other members queue changes until owner sync.
- Verify signatures and history ancestry; reject forks and stale local writes.
- Integer-cent money, duplicate-operation protection, contributor/recipient separate from recorder, no pool overdraft.
- Password-encrypted export and fresh-install restore; Android automatic cloud backup disabled.
- Web asset cache for offline launch; no service-worker caching of financial/network API responses.
- Existing cloud data is imported only on explicit request, archived locally and never silently deleted.
- Keep existing Site audience; the hosted preview's ChatGPT gate is separate from the offline app identity.
