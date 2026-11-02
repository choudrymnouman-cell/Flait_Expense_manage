# Flait 3.0 — Data Safety worksheet

This is an implementation inventory for the developer to reconcile with the current Play Console questions and Supabase's operational logging terms. It is not an automatically submitted declaration or an assertion of Play approval.

| Data | Local use | Off-device behavior | Form review |
|---|---|---|---|
| Display names, membership, expenses, votes and ledger | Local journal; encrypted on Android | Inside end-to-end encrypted live messages to explicitly paired devices | Review Play's end-to-end encryption and user-initiated transfer exemptions. Do not simply assume “offline” means no declaration. |
| Receipt photos | Local only by default; selected with system picker | Sent to paired flatmates only if sharing is enabled, inside encrypted signed history | User-controlled photos; explain retention by recipients. |
| Device public signing IDs, flat ID, ephemeral public keys and discovery timestamps | Authenticate admitted peers | Signed discovery metadata visible to relay; private signing and exchange keys are never sent | Evaluate Device or other IDs; app functionality/security purpose. |
| IP addresses, connection/timing metadata | Not stored by app as analytics | Relay infrastructure necessarily receives connection metadata; operational retention must be checked with provider | Do not mark metadata “ephemeral” unless provider practices meet the definition. |
| PIN | Salted PBKDF2 verifier on device | Not included in sync; removed when restoring backup | Not transmitted by app. |
| Biometrics / device passcode | OS authentication prompt | App receives success/failure only, no biometric templates | No biometric collection by Flait. |
| Backup and reports | User-chosen save destination | App does not upload; user may select their own cloud/file provider | Explain identity in backup and user-controlled exports. |

Transport: WSS/TLS relay plus AES-256-GCM encrypted financial payloads. No advertising SDK, analytics SDK, location, contacts, broad media/storage permission, bank access, payment SDK or online account creation in the active UI.

No expense/ledger database requests are made by the active offline app. Supabase client-origin Broadcast is used, with no database writes, replay or server message queue. Operational server logs cannot be claimed absent solely from this client code.

User deletion: uninstall/clear local storage removes the local copy; user-created exports and records already shared with others may remain. There is no online Flait account to delete. The separate owner-private web preview has a ChatGPT access gate, unrelated to native app membership.

Before submitting, review all SDKs and current production traffic, complete App content / Data Safety / ads / content rating / target audience / financial features declarations accurately, and confirm a public privacy-policy URL and developer support email. Expense tracking is not a banking, lending or money-transfer service.

Official sources checked 2 November 2026:
- https://support.google.com/googleplay/android-developer/answer/10787469
- https://support.google.com/googleplay/android-developer/answer/10144311
- https://support.google.com/googleplay/android-developer/answer/11926878
- https://support.google.com/googleplay/android-developer/answer/14151465

Current target policy: new Android phone apps/updates target API 36 or higher. Newly created personal developer accounts (after 13 November 2023) require a closed test with at least 12 testers opted in continuously for 14 days before applying for production access. This is not satisfied by CI/unit tests.
