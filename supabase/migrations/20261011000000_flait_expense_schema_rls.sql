-- Flait Expense Manage schema for Supabase PostgreSQL
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.flats (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 80),
  currency text not null default 'PKR' check (currency ~ '^[A-Z]{3}$'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table public.flat_members (
  id uuid primary key default gen_random_uuid(),
  flat_id uuid not null references public.flats(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  role text not null default 'member' check (role in ('admin','treasurer','member')),
  active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (flat_id, user_id)
);
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  flat_id uuid not null references public.flats(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 2 and 120),
  description text not null default '',
  category text not null default 'Other',
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  receipt_path text,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  unique (id, flat_id)
);
create table public.expense_votes (
  id uuid primary key default gen_random_uuid(),
  flat_id uuid not null references public.flats(id) on delete cascade,
  expense_id uuid not null references public.expenses(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete restrict,
  approved boolean not null,
  comment text not null default '',
  created_at timestamptz not null default now(),
  unique (expense_id, member_id)
);
create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  flat_id uuid not null references public.flats(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  entry_type text not null check (entry_type in ('contribution','expense_payment','withdrawal','repayment')),
  amount numeric(12,2) not null check (amount > 0),
  description text not null,
  related_expense_id uuid references public.expenses(id) on delete restrict,
  created_at timestamptz not null default now()
);
create unique index ledger_one_payment_per_expense on public.ledger_entries(related_expense_id)
where entry_type = 'expense_payment' and related_expense_id is not null;
create index flat_members_user_id_idx on public.flat_members(user_id);
create index expenses_flat_created_idx on public.expenses(flat_id, created_at desc);
create index ledger_flat_created_idx on public.ledger_entries(flat_id, created_at desc);
create index votes_expense_idx on public.expense_votes(expense_id);

create or replace function private.is_flat_member(p_flat_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists (select 1 from public.flat_members m where m.flat_id = p_flat_id and m.user_id = (select auth.uid()) and m.active);
$$;
create or replace function private.is_flat_manager(p_flat_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
 select exists (select 1 from public.flat_members m where m.flat_id = p_flat_id and m.user_id = (select auth.uid()) and m.active and m.role in ('admin','treasurer'));
$$;
revoke all on function private.is_flat_member(uuid) from public, anon;
revoke all on function private.is_flat_manager(uuid) from public, anon;
grant execute on function private.is_flat_member(uuid) to authenticated;
grant execute on function private.is_flat_manager(uuid) to authenticated;

alter table public.flats enable row level security;
alter table public.flat_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_votes enable row level security;
alter table public.ledger_entries enable row level security;

create policy "flat members can read their flats" on public.flats for select to authenticated
using (created_by = (select auth.uid()) or private.is_flat_member(id));
create policy "users create their own flats" on public.flats for insert to authenticated
with check (created_by = (select auth.uid()));
create policy "flat members can read membership" on public.flat_members for select to authenticated
using (user_id = (select auth.uid()) or private.is_flat_member(flat_id));
create policy "authorized flat membership creation" on public.flat_members for insert to authenticated
with check (
  (user_id = (select auth.uid()) and role = 'admin'
   and exists (select 1 from public.flats f where f.id = flat_id and f.created_by = (select auth.uid())))
  or private.is_flat_manager(flat_id)
);

create policy "flat members read expenses" on public.expenses for select to authenticated
using (private.is_flat_member(flat_id));
create policy "members create their own expenses" on public.expenses for insert to authenticated
with check (private.is_flat_member(flat_id) and requester_id = (select auth.uid()) and status = 'pending' and paid_at is null);
create policy "managers update expense status" on public.expenses for update to authenticated
using (private.is_flat_manager(flat_id)) with check (private.is_flat_manager(flat_id));

create policy "flat members read votes" on public.expense_votes for select to authenticated
using (private.is_flat_member(flat_id));
create policy "members vote on others requests once" on public.expense_votes for insert to authenticated
with check (private.is_flat_member(flat_id) and member_id = (select auth.uid()) and exists (
 select 1 from public.expenses e where e.id = expense_id and e.flat_id = flat_id and e.requester_id <> (select auth.uid()) and e.status = 'pending'
));
create policy "flat members read ledger" on public.ledger_entries for select to authenticated
using (private.is_flat_member(flat_id));
create policy "managers record contributions and withdrawals" on public.ledger_entries for insert to authenticated
with check (private.is_flat_manager(flat_id) and actor_id = (select auth.uid()) and entry_type in ('contribution','withdrawal','repayment'));

create or replace function private.update_expense_vote_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare eligible_count integer; approval_count integer; rejection_count integer; required_votes integer;
begin
 select count(*) into eligible_count from public.flat_members m join public.expenses e on e.flat_id = m.flat_id
 where e.id = new.expense_id and m.active and m.user_id <> e.requester_id;
 required_votes := floor(eligible_count / 2.0)::integer + 1;
 select count(*) filter (where v.approved), count(*) filter (where not v.approved)
 into approval_count, rejection_count from public.expense_votes v where v.expense_id = new.expense_id;
 if approval_count >= required_votes then
   update public.expenses set status = 'approved' where id = new.expense_id and status = 'pending';
 elsif rejection_count >= required_votes then
   update public.expenses set status = 'rejected' where id = new.expense_id and status = 'pending';
 end if;
 return new;
end;
$$;
revoke all on function private.update_expense_vote_status() from public, anon, authenticated;
create trigger expense_vote_status_after_insert after insert on public.expense_votes
for each row execute function private.update_expense_vote_status();

create or replace function private.record_expense_payment()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare available_balance numeric(12,2);
begin
 if new.status = 'paid' and old.status is distinct from 'paid' then
   if old.status <> 'approved' then raise exception 'Only approved expenses can be paid'; end if;
   if not private.is_flat_manager(new.flat_id) then raise exception 'Only the treasurer or flat admin can record payments'; end if;
   select coalesce(sum(case when l.entry_type in ('contribution','repayment') then l.amount when l.entry_type in ('expense_payment','withdrawal') then -l.amount else 0 end),0)
   into available_balance from public.ledger_entries l where l.flat_id = new.flat_id;
   if available_balance < new.amount then raise exception 'The flat pool does not have enough money for this payment'; end if;
   new.paid_at := now();
   insert into public.ledger_entries (flat_id, actor_id, entry_type, amount, description, related_expense_id)
   values (new.flat_id, (select auth.uid()), 'expense_payment', new.amount, 'Reimbursement: ' || new.title, new.id);
 end if;
 return new;
end;
$$;
revoke all on function private.record_expense_payment() from public, anon, authenticated;
create trigger expense_payment_before_update before update of status on public.expenses
for each row execute function private.record_expense_payment();

grant usage on schema public to authenticated;
grant select, insert on public.flats to authenticated;
grant select, insert on public.flat_members to authenticated;
grant select, insert on public.expenses to authenticated;
grant select, insert on public.expense_votes to authenticated;
grant select, insert on public.ledger_entries to authenticated;
grant update (status) on public.expenses to authenticated;

-- Single-use invitations: a flat manager creates a code, then a signed-in roommate redeems it.
create table public.flat_invites (
  id uuid primary key default gen_random_uuid(),
  flat_id uuid not null references public.flats(id) on delete cascade,
  invite_code text not null unique default encode(gen_random_bytes(12), 'hex'),
  created_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index flat_invites_flat_id_idx on public.flat_invites(flat_id);
alter table public.flat_invites enable row level security;
create policy "flat managers create invites" on public.flat_invites for insert to authenticated
with check (private.is_flat_manager(flat_id) and created_by = (select auth.uid()) and accepted_by is null);
create policy "flat managers view invites" on public.flat_invites for select to authenticated
using (private.is_flat_manager(flat_id));

create or replace function public.accept_flat_invite(p_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare invite_row public.flat_invites%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sign in before accepting an invite'; end if;
  if char_length(trim(coalesce(p_display_name,''))) < 1 or char_length(trim(p_display_name)) > 80 then
    raise exception 'Enter a valid display name';
  end if;
  select * into invite_row from public.flat_invites
    where invite_code = trim(p_code) and accepted_by is null and expires_at > now()
    for update;
  if not found then raise exception 'Invite code is invalid, expired, or already used'; end if;
  insert into public.flat_members(flat_id, user_id, display_name, role, active)
    values (invite_row.flat_id, (select auth.uid()), trim(p_display_name), 'member', true)
    on conflict (flat_id, user_id) do update set active = true;
  update public.flat_invites set accepted_by = (select auth.uid()), accepted_at = now()
    where id = invite_row.id;
  return invite_row.flat_id;
end;
$$;
revoke all on function public.accept_flat_invite(text,text) from public, anon;
grant execute on function public.accept_flat_invite(text,text) to authenticated;

-- Prevent privileged clients from bypassing the vote quorum by editing expense status directly.
create or replace function private.guard_expense_status_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare eligible_count integer; approval_count integer; rejection_count integer; required_votes integer;
begin
  if new.status is not distinct from old.status then return new; end if;
  if old.status = 'approved' and new.status = 'paid' then
    if not private.is_flat_manager(new.flat_id) then raise exception 'Only a flat manager can record payment'; end if;
    return new;
  end if;
  if old.status <> 'pending' or new.status not in ('approved','rejected') then raise exception 'Invalid expense status transition'; end if;
  select count(*) into eligible_count from public.flat_members m where m.flat_id = new.flat_id and m.active and m.user_id <> new.requester_id;
  required_votes := floor(eligible_count / 2.0)::integer + 1;
  select count(*) filter (where v.approved), count(*) filter (where not v.approved)
    into approval_count, rejection_count from public.expense_votes v where v.expense_id = new.id;
  if new.status = 'approved' and approval_count < required_votes then raise exception 'Not enough approval votes'; end if;
  if new.status = 'rejected' and rejection_count < required_votes then raise exception 'Not enough rejection votes'; end if;
  return new;
end;
$$;
revoke all on function private.guard_expense_status_change() from public, anon, authenticated;
create trigger expense_status_guard_before_update before update of status on public.expenses
for each row execute function private.guard_expense_status_change();

-- Supporting indexes for foreign keys and common membership/ledger lookups.
create index if not exists flats_created_by_idx on public.flats(created_by);
create index if not exists expense_votes_flat_id_idx on public.expense_votes(flat_id);
create index if not exists expense_votes_member_id_idx on public.expense_votes(member_id);
create index if not exists expenses_requester_id_idx on public.expenses(requester_id);
create index if not exists ledger_entries_actor_id_idx on public.ledger_entries(actor_id);

create index if not exists flat_invites_created_by_idx on public.flat_invites(created_by);
create index if not exists flat_invites_accepted_by_idx on public.flat_invites(accepted_by);
