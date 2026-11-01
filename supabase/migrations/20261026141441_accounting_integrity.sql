-- Separate money ownership from the manager who records an entry.
alter table public.ledger_entries add column member_id uuid references auth.users(id) on delete restrict;
alter table public.ledger_entries add column request_id uuid;
create unique index ledger_request_id_idx on public.ledger_entries(flat_id, request_id) where request_id is not null;
create index ledger_member_id_idx on public.ledger_entries(member_id);
update public.ledger_entries l set member_id = e.requester_id
from public.expenses e where e.id = l.related_expense_id and l.entry_type = 'expense_payment';
-- Historical contributions cannot be attributed reliably. Preserve their amounts
-- and recorder, leaving member_id NULL rather than inventing a contributor.

-- Mutations go through authenticated RPCs. All cash operations take the same
-- flat row lock BEFORE expense locks, serializing balance checks for the pool.
revoke insert on public.ledger_entries from authenticated;
revoke update on public.expenses from authenticated;
revoke update(status) on public.expenses from authenticated;

create or replace function private.record_expense_payment()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare available_balance numeric(12,2);
begin
 if new.status = 'paid' and old.status is distinct from 'paid' then
   if old.status <> 'approved' then raise exception 'Only approved expenses can be paid'; end if;
   if not private.is_flat_manager(new.flat_id) then raise exception 'Only a flat manager can record payments'; end if;
   perform 1 from public.flats where id = new.flat_id for update;
   select coalesce(sum(case when l.entry_type in ('contribution','repayment') then l.amount else -l.amount end),0)
   into available_balance from public.ledger_entries l where l.flat_id = new.flat_id;
   if available_balance < new.amount then raise exception 'Insufficient pool funds'; end if;
   new.paid_at := now();
   insert into public.ledger_entries(flat_id,actor_id,member_id,entry_type,amount,description,related_expense_id)
   values(new.flat_id,auth.uid(),new.requester_id,'expense_payment',new.amount,'Reimbursement: '||new.title,new.id);
 end if;
 return new;
end;
$$;

create or replace function public.pay_flat_expense(p_flat_id uuid,p_expense_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare expense_row public.expenses%rowtype;
begin
 if auth.uid() is null or not private.is_flat_manager(p_flat_id) then raise exception 'Only a flat manager can record payments'; end if;
 perform 1 from public.flats where id=p_flat_id for update;
 select * into expense_row from public.expenses where id=p_expense_id and flat_id=p_flat_id for update;
 if not found then raise exception 'Expense not found'; end if;
 if expense_row.status='paid' then return; end if;
 if expense_row.status<>'approved' then raise exception 'Only approved requests can be paid'; end if;
 update public.expenses set status='paid' where id=p_expense_id;
end;
$$;
revoke all on function public.pay_flat_expense(uuid,uuid) from public,anon;
grant execute on function public.pay_flat_expense(uuid,uuid) to authenticated;

create or replace function public.record_pool_contribution(p_flat_id uuid,p_member_id uuid,p_amount numeric,p_description text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare entry_row public.ledger_entries%rowtype; entry_id uuid;
begin
 if auth.uid() is null or not private.is_flat_manager(p_flat_id) then raise exception 'Only a flat manager can record contributions'; end if;
 if p_request_id is null or p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0.01 or p_amount>9999999999.99 or p_amount<>round(p_amount,2) then raise exception 'Enter an amount with at most two decimal places'; end if;
 perform 1 from public.flats where id=p_flat_id for update;
 select * into entry_row from public.ledger_entries where flat_id=p_flat_id and request_id=p_request_id;
 if found then
   if entry_row.member_id is distinct from p_member_id or entry_row.amount<>p_amount or entry_row.actor_id<>auth.uid() or entry_row.description<>coalesce(nullif(trim(p_description),''),'Pool contribution') then raise exception 'Request ID already used with different details'; end if;
   return entry_row.id;
 end if;
 if not exists(select 1 from public.flat_members where flat_id=p_flat_id and user_id=p_member_id and active) then raise exception 'Contributor must be an active flatmate'; end if;
 insert into public.ledger_entries(flat_id,actor_id,member_id,entry_type,amount,description,request_id)
 values(p_flat_id,auth.uid(),p_member_id,'contribution',p_amount,coalesce(nullif(trim(p_description),''),'Pool contribution'),p_request_id) returning id into entry_id;
 return entry_id;
end;
$$;
revoke all on function public.record_pool_contribution(uuid,uuid,numeric,text,uuid) from public,anon;
grant execute on function public.record_pool_contribution(uuid,uuid,numeric,text,uuid) to authenticated;

-- Serialize votes for a request so concurrent votes cannot miss the quorum.
create or replace function private.lock_expense_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare e public.expenses%rowtype;
begin
 select * into e from public.expenses where id=new.expense_id for update;
 if not found or e.flat_id<>new.flat_id or e.status<>'pending' then raise exception 'Request is no longer pending'; end if;
 if auth.uid() is null or new.member_id<>auth.uid() or e.requester_id=auth.uid() or not private.is_flat_member(new.flat_id) then raise exception 'Not eligible to vote'; end if;
 return new;
end;
$$;
revoke all on function private.lock_expense_vote() from public,anon,authenticated;
create trigger expense_vote_lock_before_insert before insert on public.expense_votes for each row execute function private.lock_expense_vote();

-- Count only votes of currently active eligible members, matching the client.
create or replace function private.update_expense_vote_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare eligible_count integer; approval_count integer; rejection_count integer; required_votes integer;
begin
 select count(*) into eligible_count from public.flat_members m join public.expenses e on e.flat_id=m.flat_id
 where e.id=new.expense_id and m.active and m.user_id<>e.requester_id;
 required_votes:=floor(eligible_count/2.0)::integer+1;
 select count(*) filter(where v.approved),count(*) filter(where not v.approved) into approval_count,rejection_count
 from public.expense_votes v join public.flat_members m on m.flat_id=v.flat_id and m.user_id=v.member_id and m.active
 join public.expenses e on e.id=v.expense_id
 where v.expense_id=new.expense_id and v.member_id<>e.requester_id;
 if approval_count>=required_votes then update public.expenses set status='approved' where id=new.expense_id and status='pending';
 elsif rejection_count>=required_votes then update public.expenses set status='rejected' where id=new.expense_id and status='pending'; end if;
 return new;
end;
$$;

-- Fresh flat + first membership must succeed or fail together.
create or replace function public.create_flat(p_name text,p_display_name text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare flat_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 insert into public.flats(name,created_by) values(trim(p_name),auth.uid()) returning id into flat_id;
 insert into public.flat_members(flat_id,user_id,display_name,role) values(flat_id,auth.uid(),trim(p_display_name),'admin');
 return flat_id;
end;
$$;
revoke all on function public.create_flat(text,text) from public,anon;
grant execute on function public.create_flat(text,text) to authenticated;

create or replace function private.guard_expense_status_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare eligible_count integer; approval_count integer; rejection_count integer; required_votes integer;
begin
 if new.status is not distinct from old.status then return new; end if;
 if old.status='approved' and new.status='paid' then
   if not private.is_flat_manager(new.flat_id) then raise exception 'Only a flat manager can record payment'; end if;
   return new;
 end if;
 if old.status<>'pending' or new.status not in ('approved','rejected') then raise exception 'Invalid expense status transition'; end if;
 select count(*) into eligible_count from public.flat_members m where m.flat_id=new.flat_id and m.active and m.user_id<>new.requester_id;
 required_votes:=floor(eligible_count/2.0)::integer+1;
 select count(*) filter(where v.approved),count(*) filter(where not v.approved) into approval_count,rejection_count
 from public.expense_votes v join public.flat_members m on m.flat_id=v.flat_id and m.user_id=v.member_id and m.active
 where v.expense_id=new.id and v.member_id<>new.requester_id;
 if new.status='approved' and approval_count<required_votes then raise exception 'Not enough approval votes'; end if;
 if new.status='rejected' and rejection_count<required_votes then raise exception 'Not enough rejection votes'; end if;
 return new;
end;
$$;
