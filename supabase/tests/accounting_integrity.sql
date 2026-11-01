-- Run against a test database or via a trusted SQL connection. All fixtures
-- are rolled back; no production records are modified.
begin;
do $$
#variable_conflict use_variable
declare
 manager_id uuid:=gen_random_uuid(); member_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
 flat_id uuid; expense_id uuid; second_expense_id uuid; req_id uuid:=gen_random_uuid(); first_entry uuid; retry_entry uuid;
 balance numeric; rejected boolean;
begin
 insert into auth.users(id) values(manager_id),(member_id),(outsider_id);
 perform set_config('request.jwt.claim.sub',manager_id::text,true);
 flat_id:=public.create_flat('Accounting regression test','Manager');
 insert into public.flat_members(flat_id,user_id,display_name,role) values(flat_id,member_id,'Member','member');
 first_entry:=public.record_pool_contribution(flat_id,member_id,100.25,'Test funds',req_id);
 retry_entry:=public.record_pool_contribution(flat_id,member_id,100.25,'Test funds',req_id);
 if first_entry<>retry_entry then raise exception 'Idempotency failure'; end if;
 if (select count(*) from public.ledger_entries l where l.flat_id=flat_id)<>1 then raise exception 'Duplicate contribution'; end if;
 perform set_config('request.jwt.claim.sub',member_id::text,true);
 rejected:=false;
 begin perform public.record_pool_contribution(flat_id,member_id,1,'Unauthorized',gen_random_uuid());
 exception when raise_exception then rejected:=true; end;
 if not rejected then raise exception 'Ordinary member recorded funds'; end if;
 insert into public.expenses(flat_id,requester_id,title,amount) values(flat_id,member_id,'Test reimbursement',60.10) returning id into expense_id;
 rejected:=false;
 begin insert into public.expense_votes(flat_id,expense_id,member_id,approved) values(flat_id,expense_id,member_id,true);
 exception when raise_exception then rejected:=true; end;
 if not rejected then raise exception 'Self vote accepted'; end if;
 perform set_config('request.jwt.claim.sub',manager_id::text,true);
 insert into public.expense_votes(flat_id,expense_id,member_id,approved) values(flat_id,expense_id,manager_id,true);
 if (select e.status from public.expenses e where e.id=expense_id)<>'approved' then raise exception 'Quorum did not approve'; end if;
 perform public.pay_flat_expense(flat_id,expense_id);
 perform public.pay_flat_expense(flat_id,expense_id);
 if (select count(*) from public.ledger_entries where related_expense_id=expense_id)<>1 then raise exception 'Duplicate payment'; end if;
 if not exists(select 1 from public.ledger_entries where related_expense_id=expense_id and actor_id=manager_id and ledger_entries.member_id=member_id) then raise exception 'Incorrect attribution'; end if;
 select sum(case when entry_type in ('contribution','repayment') then amount else -amount end) into balance from public.ledger_entries l where l.flat_id=flat_id;
 if balance<>40.15 then raise exception 'Incorrect pool balance: %',balance; end if;
 insert into public.expenses(flat_id,requester_id,title,amount) values(flat_id,member_id,'Overdraft attempt',50) returning id into second_expense_id;
 insert into public.expense_votes(flat_id,expense_id,member_id,approved) values(flat_id,second_expense_id,manager_id,true);
 rejected:=false;
 begin perform public.pay_flat_expense(flat_id,second_expense_id); exception when raise_exception then rejected:=true; end;
 if not rejected then raise exception 'Overdraft accepted'; end if;
 if (select e.status from public.expenses e where e.id=second_expense_id)<>'approved' then raise exception 'Failed payment changed status'; end if;
 perform set_config('request.jwt.claim.sub',outsider_id::text,true);
 rejected:=false;
 begin perform public.pay_flat_expense(flat_id,expense_id); exception when raise_exception then rejected:=true; end;
 if not rejected then raise exception 'Outsider accepted'; end if;
end;
$$;
rollback;
