# Flait 3.0 release handoff

## Prepared in source

- Application ID: `com.flait.expenses` (confirm ownership/availability in Play Console before the first publication).
- Version 3.0.0, versionCode 6; minimum Android API 24, target API 36 via pinned Flutter SDK.
- Production Gradle signing uses explicit environment variables and refuses an implicit debug-signed production release.
- CI sets `FLAIT_TEST_BUILD=true` for device-test APK/AAB artifacts. A CI test-signed bundle must NOT be uploaded as the final production bundle; use the re-signed handoff bundle or build with the production upload key.
- Local financial engine, encrypted native storage, signed journal and owner transition tests.
- Privacy policy (Markdown/HTML), listing copy, Data Safety worksheet, icon and feature graphic.
- Offline fonts pinned to upstream commit + SHA-256; no runtime font download.

## Developer actions still required

1. Verify Play developer identity, payment/account details and support email. Decide countries, price and audience.
2. Enroll in Play App Signing. Use the private upload certificate supplied with the release key kit; never publish the private key or its password. Back up keys securely.
3. Upload the production upload-key-signed `.aab` to internal testing first. The native standalone test APK and Play-installed APK may have different signing certificates; use an encrypted backup to migrate if needed.
4. Review the Data Safety worksheet against provider logs and the exact production SDK behavior; complete all Play Console forms.
5. Provide an active publicly readable privacy policy URL. The repository Markdown policy can be viewed publicly; HTML is also ready for the developer's website. Do not use the owner-private app preview as a public privacy-policy URL.
6. Run the physical-device matrix below, capture actual Android screenshots for the store, and run Play's pre-launch report.
7. If the personal-account requirement applies, run closed testing with at least 12 testers opted in for 14 consecutive days, gather meaningful feedback, then apply for production access. Production acceptance is Google's decision.

## Physical-device acceptance matrix (not claimed completed by CI)

- Android 7/API24 low-memory phone; recent Android 15/16 phone; small and large displays; 200% text scale; dark mode and Urdu RTL.
- Owner + two member phones: pair, offline queue, reconnect, interrupted transfer, corrections/votes, settlement, member revocation and accepted owner handoff reaching every member.
- Process kill/reopen; force-stop is not an always-background sync guarantee. Both apps active online for live exchange.
- Android biometric setup unavailable/cancelled/success; app PIN cold launch/background relock; five wrong attempts and cooldown.
- Encrypted export, fresh-install restore, wrong password, missing device key, lost phone without backup, app update preserving identity and journal.
- Local-only versus shared photo, receipt dimension/size limits, JPEG/PNG picker cancellation, PDF/CSV save and cancellation.
- Review that no plaintext expenses/receipts/private keys reach the relay; confirm no financial database persistence and review operational metadata logging.

## Build

```
python3 scripts/prepare_assets.py
python3 scripts/prepare_android.py
flutter pub get
flutter analyze
flutter test
flutter test --dart-define=FLAIT_LIVE_TEST=true test/live_sync_test.dart
```

For production signing set `FLAIT_KEYSTORE_PATH`, `FLAIT_KEYSTORE_PASSWORD`, `FLAIT_KEY_ALIAS` and optionally `FLAIT_KEY_PASSWORD` privately, then `flutter build appbundle --release`. Keep keys/passwords out of Git, logs and public issues. Do not rename the application ID after the first Play publication.

The app does not execute bank transfers. Monthly templates require review/submission; they are not automatic bank payments. Owner recovery without a backup is intentionally unavailable. Records already shared to another device cannot be remotely erased.
