# Flait — Shared Flat Expense Manager

Flutter app for Android and Web to manage shared-flat expense claims, flatmate approvals, treasurer pool money and a transparent ledger.

## Connected services

- **Flutter**: one responsive app for Android and Web.
- **Supabase Auth**: email/password account creation and sign-in.
- **Supabase PostgreSQL**: persistent flat, member, expense, vote and ledger records.
- **Row Level Security (RLS)**: flat membership policies are enforced by PostgreSQL; the publishable key is the only key included in the client.

## Core accounting rules

- An expense request is a claim, not a payment.
- A majority of eligible flatmates (excluding the requester) must approve or reject.
- Approval does not change the pool balance.
- A treasurer or flat admin can record contributions and pay approved expenses.
- Paid expenses create a ledger entry and reduce the pool balance.
- Pool balances are derived from ledger entries.

## Database setup

The schema is in `supabase/migrations/20261011000000_flait_expense_schema_rls.sql`. It creates the tables, constraints, indexes, policies and database triggers used by the app.

The migration has been applied to the configured Supabase project. If you create a fresh project, apply the migration in the Supabase SQL Editor or with the Supabase CLI before launching the app.

## Run locally

Install Flutter stable and enable Web support. Then run:

```bash
flutter create . --platforms=android,web
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

To run on Android, connect an emulator/device and use `flutter run`.

## Current scope / next work

The current version supports account signup/sign-in, first-flat creation, member list, expense submission, voting, contributions, recording approved payments, and the ledger. Flatmate invitations, receipt uploads, push notifications, CSV export, password reset UI, and full automated integration tests are not yet implemented.

Never put a Supabase secret/service-role key or database password in this Flutter repository.
