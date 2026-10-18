-- Run this SQL in the Supabase SQL Editor before enabling real checkout.
-- Purchases are applied only by the signed payment webhook using the service-role key.
create table if not exists public.credit_purchase_events (
  stripe_session_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  package_code text not null check (package_code in ('starter','trader','pro')),
  credits integer not null check (credits > 0),
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default now()
);
alter table public.credit_purchase_events enable row level security;
revoke all on public.credit_purchase_events from anon, authenticated;

create or replace function public.apply_credit_purchase(
  p_user_id uuid,
  p_session_id text,
  p_package_code text,
  p_credits integer,
  p_amount_cents integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_credits integer;
  expected_amount integer;
  inserted_count integer;
begin
  if p_package_code = 'starter' then expected_credits := 500; expected_amount := 499;
  elsif p_package_code = 'trader' then expected_credits := 1200; expected_amount := 999;
  elsif p_package_code = 'pro' then expected_credits := 2600; expected_amount := 1999;
  else raise exception 'Invalid package';
  end if;
  if p_credits <> expected_credits or p_amount_cents <> expected_amount then
    raise exception 'Credit package details mismatch';
  end if;

  insert into public.credit_purchase_events(stripe_session_id,user_id,package_code,credits,amount_cents)
  values(p_session_id,p_user_id,p_package_code,p_credits,p_amount_cents)
  on conflict (stripe_session_id) do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then return; end if;

  update public.trading_accounts
  set cash = coalesce(cash,0) + p_credits,
      account_state = jsonb_set(
        coalesce(account_state, '{}'::jsonb),
        '{cash}',
        to_jsonb(coalesce(nullif(account_state->>'cash','')::numeric, cash, 0) + p_credits),
        true
      ),
      updated_at = now()
  where user_id = p_user_id;

  if not found then
    insert into public.trading_accounts(user_id,cash,holdings,open_orders,transactions,account_state,updated_at)
    values(p_user_id,p_credits,'[]'::jsonb,'[]'::jsonb,'[]'::jsonb,jsonb_build_object(
      'cash',p_credits,'realized',0,'positions','[]'::jsonb,'orders','[]'::jsonb,
      'transactions','[]'::jsonb,'balances','[]'::jsonb,'activity','[]'::jsonb,
      'quotes',jsonb_build_object('lch',135.75,'landscaping',75,'onyx',4.5,'enclosure',57),
      'priceModelVersion',3
    ),now());
  end if;
end;
$$;
revoke all on function public.apply_credit_purchase(uuid,text,text,integer,integer) from public, anon, authenticated;
grant execute on function public.apply_credit_purchase(uuid,text,text,integer,integer) to service_role;
