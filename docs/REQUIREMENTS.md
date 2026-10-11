# Flait Product Requirements

## 1. Product goal
Flait helps roommates manage shared pool money and personal purchases with transparent approvals and a trustworthy transaction ledger. Android and Web should share one Flutter codebase.

## 2. Roles and permissions
- **Flat admin:** manages the flat, membership, invitations, and policy.
- **Treasurer:** records pool contributions, withdrawals, and approved reimbursement payments.
- **Member:** submits expense requests, reviews eligible requests, and sees the flat ledger.
- Members must not vote on their own reimbursement.
- Production authorization must be enforced by the backend, never only by hiding buttons in the client.

## 3. Expense request lifecycle
1. Member submits title, category, amount, purchase date, description, and optional receipt.
2. Request becomes **Pending** and is visible to eligible flatmates.
3. Eligible members vote approve/reject once each, with optional comments.
4. Policy engine evaluates quorum and records the decision history.
5. An approved request becomes **Approved · unpaid**.
6. Treasurer verifies the receipt and records an actual payment.
7. Only then does the ledger record a pool outflow and the request become **Paid**.
8. Rejected requests remain visible in history and never change the pool balance.

## 4. Money and ledger rules
- Pool balance is calculated as opening balance + contributions + repayments - paid reimbursements - withdrawals.
- Never edit a calculated balance directly.
- Approval is not payment and must not change cash balance.
- Every ledger entry has a stable ID, amount, type, actor, timestamp, description, and optional related request.
- Use database transactions and server-side idempotency keys for financial mutations.
- Prevent duplicate payment records for the same expense.
- Never allow a payment larger than the available pool balance unless an explicit overdraft policy is introduced.
- Define the individual balance formula before production: record each member's contributions, their allocated share of common costs, and any personal reimbursements/settlements. The demo currently shows a simplified contribution-minus-paid-purchase view, not a legally binding settlement statement.

## 5. Approval policy
- Default demo rule: strict majority of active eligible flatmates, excluding the requester.
- Store votes and decision timestamps immutably.
- Production policy must define tie handling, minimum quorum, abstentions, inactive members, treasurer conflicts, and whether policy changes affect existing requests.
- Requesters must not create alternate accounts or cast votes on their own requests; identity controls are required server-side.

## 6. Screens
- Dashboard: available pool balance, pending request count, roommate overview, recent requests.
- Expense entry: validation, category, description, amount, and future receipt upload.
- Approvals: vote, show prior votes, decision status, and record payment for approved claims (treasurer/admin only).
- Ledger: chronological incoming/outgoing entries and contribution recording.
- Settings: profile, flat policy, and demo member switching.
- Future screens: invite/membership management, settlement workflow, reports, notifications, and account/security settings.

## 7. Reliability, privacy, and security
- Validate positive finite amounts and required text.
- Prevent duplicate submissions and duplicate payments.
- Use server timestamps for production audit records.
- Restrict flat data by authenticated membership using row-level security or equivalent.
- Store receipt images in private object storage and use expiring signed URLs.
- Do not put database passwords, service-role keys, signing secrets, or API credentials in Flutter source.
- Back up data and provide account deletion/export flows consistent with the applicable privacy requirements.

## 8. Reporting and usability
- Monthly and category-based summaries.
- Export transactions as CSV; filter by date, category, member, and status.
- Show empty, loading, validation, and failure states clearly.
- Support small mobile screens, keyboard navigation, and accessible contrast.
- Currency is configurable; demo defaults to PKR.

## 9. Future production milestones
1. Authentication, flat creation, invite acceptance, and role management.
2. PostgreSQL schema, secure policies, migrations, and transactional RPC/API actions.
3. Private receipt uploads and notifications.
4. Settlement calculations and verified CSV exports.
5. CI, automated tests, security review, backup/restore rehearsal, and Android/Web release pipelines.

## 10. Current scaffold limitations
This repository is an initial client-side demo. Its sample data is in memory and resets on restart. Demo member switching is not authentication. There is no live multi-user sync, cloud database, receipt upload, push notification, or production settlement engine until a backend is configured and the corresponding features are implemented and tested.
