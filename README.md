# Flait — Shared Flat Expense Manager

A Flutter app for Android and Web to manage shared flat expenses, treasurer pool money, reimbursement requests, roommate approvals, and a transparent ledger.

## Core accounting rules

- An expense request is a claim, not a payment.
- An approval creates an approved liability; it does not reduce the pool balance.
- Only a recorded pool payment reduces the pool balance.
- Contributions increase the pool balance.
- Every money-changing event must have a unique ID, actor, timestamp, and audit entry.
- Balances should be derived from ledger entries rather than independently edited totals.

## Planned features

- Flat setup, roommate membership, role-based permissions (treasurer, member, flat admin).
- Pool contributions and withdrawals with reason and audit trail.
- Expense and reimbursement requests with category, date, description, receipt attachment, and payer.
- Configurable approval quorum, conflict-of-interest protection, approve/reject comments, and status history.
- Treasurer payment recording and reimbursement status tracking.
- Ledger, pool balance, individual balances, settlement suggestions, reports, CSV export, and notifications.
- Input validation, duplicate-submit protection, tests, and responsive Android/Web layouts.

## Tech stack

- Flutter / Dart (single Android and Web codebase).
- Initial local/demo repository scaffold uses an in-memory repository so the UI and accounting rules can be explored without credentials.
- Production deployment should connect an authenticated backend (for example Supabase/PostgreSQL or a secured REST API). Do not put service-role keys or database passwords in the Flutter client.

## Prerequisites

Install Flutter stable and enable web support. Verify installation:

```bash
flutter doctor
flutter config --enable-web
```

## Run

This repository contains the app source scaffold. From the repository root, create platform runner files if they are not present, then fetch packages and run:

```bash
flutter create . --platforms=android,web
flutter pub get
flutter run -d chrome
# or select an Android emulator/device
flutter run
```

## Tests

```bash
flutter test
```

## Project structure

```text
lib/
  main.dart
  app.dart
  models/       # flat, member, expense, ledger entry
  services/     # repository and accounting calculations
  state/        # app state / actions
  screens/      # dashboard, expense entry, approvals, ledger, settings
  widgets/      # shared UI
 test/
  accounting_service_test.dart
```

## Approval policy

The default demo policy requires a majority of eligible flatmates, excluding the requester from voting on their own reimbursement. The policy is configurable in code; a production system should store policy on the server and enforce it server-side. A rejected request keeps its decision history. An approved request is still unpaid until the treasurer records the payment.

## Production checklist

- Add authentication and invitation flow.
- Enforce flat-level row access on the backend (RLS or equivalent).
- Upload receipts to private storage with signed access URLs.
- Store immutable ledger entries and run balance changes in database transactions.
- Add server-side idempotency keys and authorization checks.
- Configure notifications and backups.
- Run tests and review privacy/security before release.

## Status

Initial source scaffold. The demo repository does not yet include production authentication, cloud persistence, receipt storage, or push notifications; these require backend configuration and credentials supplied securely outside source control.
