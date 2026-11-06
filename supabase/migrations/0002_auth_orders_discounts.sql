-- VPN IR secure auth, orders and shared discounts.
-- Apply after 0001 schema.sql. Uses pgcrypto for hashes and random tokens.
create table if not exists public.login_codes (
  id uuid primary key default gen_random_uuid(),
  telegram_id bigint not null,
  code_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  attempts integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists login_codes_lookup on public.login_codes(telegram_id, created_at desc);

create table if not exists public.site_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists site_sessions_token on public.site_sessions(token_hash);

create table if not exists public.discount_redemptions (
  id uuid primary key default gen_random_uuid(),
  discount_id uuid not null references public.discount_codes(id),
  order_id uuid not null unique references public.orders(id),
  user_id uuid references public.app_users(id),
  amount_toman bigint not null check (amount_toman >= 0),
  created_at timestamptz not null default now()
);

alter table public.login_codes enable row level security;
alter table public.site_sessions enable row level security;
alter table public.discount_redemptions enable row level security;
-- No anon/authenticated table policies. All privileged actions use Edge Functions
-- and the service-role key, which must never be exposed to the browser.

create or replace function public.issue_site_login_code(p_telegram_id bigint, p_code_hash text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if p_telegram_id is null or p_telegram_id <= 0 or length(p_code_hash) < 32 then
    raise exception 'invalid_input';
  end if;
  update public.login_codes set consumed_at=now()
   where telegram_id=p_telegram_id and consumed_at is null;
  insert into public.login_codes(telegram_id,code_hash,expires_at)
  values(p_telegram_id,p_code_hash,now()+interval '5 minutes');
end; $$;

create or replace function public.verify_site_login_code(p_telegram_id bigint, p_code_hash text, p_token_hash text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_code public.login_codes%rowtype; v_user_id uuid;
begin
  select * into v_code from public.login_codes
   where telegram_id=p_telegram_id and consumed_at is null and expires_at>now()
   order by created_at desc limit 1 for update;
  if not found then raise exception 'code_expired'; end if;
  if v_code.attempts >= 5 then raise exception 'too_many_attempts'; end if;
  if v_code.code_hash <> p_code_hash then
    update public.login_codes set attempts=attempts+1 where id=v_code.id;
    raise exception 'invalid_code';
  end if;
  update public.login_codes set consumed_at=now() where id=v_code.id;
  insert into public.app_users(telegram_id) values(p_telegram_id)
    on conflict(telegram_id) do update set telegram_id=excluded.telegram_id
    returning id into v_user_id;
  insert into public.site_sessions(user_id,token_hash,expires_at)
    values(v_user_id,p_token_hash,now()+interval '7 days');
  return v_user_id;
end; $$;

create or replace function public.create_site_order(
 p_session_hash text, p_service text, p_quantity integer, p_discount_code text default null, p_note text default null
) returns table(order_id uuid, tracking_code text, amount_toman bigint, discount_toman bigint)
language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_unit bigint; v_base bigint; v_discount public.discount_codes%rowtype;
        v_cut bigint:=0; v_order uuid; v_track text;
begin
 select user_id into v_user from public.site_sessions
  where token_hash=p_session_hash and revoked_at is null and expires_at>now();
 if v_user is null then raise exception 'unauthorized'; end if;
 if p_service='france' then
   if p_quantity not between 5 and 100 then raise exception 'invalid_quantity'; end if; v_unit:=6000;
 elsif p_service='multi' then
   if p_quantity not between 15 and 100 then raise exception 'invalid_quantity'; end if; v_unit:=15000;
 elsif p_service='unlimited' then
   if p_quantity is not null then raise exception 'invalid_quantity'; end if; v_unit:=399000;
 elsif p_service='stars' then
   if p_quantity not between 50 and 1000 then raise exception 'invalid_quantity'; end if; v_unit:=4750;
 elsif p_service='premium' then
   if p_quantity is not null then raise exception 'invalid_quantity'; end if; v_unit:=0;
 else raise exception 'invalid_service'; end if;
 v_base:=case when p_service in ('unlimited','premium') then v_unit else v_unit*p_quantity end;
 if p_discount_code is not null and length(trim(p_discount_code))>0 then
   select * into v_discount from public.discount_codes
    where upper(code)=upper(trim(p_discount_code)) for update;
   if not found or not v_discount.active or (v_discount.starts_at is not null and now()<v_discount.starts_at)
      or (v_discount.ends_at is not null and now()>v_discount.ends_at)
      or (v_discount.usage_limit is not null and v_discount.used_count>=v_discount.usage_limit)
      or v_base<v_discount.min_order_toman then raise exception 'invalid_discount'; end if;
   v_cut:=case when v_discount.discount_type='percent'
      then floor(v_base*least(v_discount.discount_value,100)/100.0)::bigint
      else least(v_base,v_discount.discount_value) end;
 end if;
 insert into public.orders(user_id,source,service,quantity,amount_toman,discount_toman,status,customer_note)
 values(v_user,'website',p_service,p_quantity,v_base-v_cut,v_cut,
        case when p_service='premium' then 'pending' else 'awaiting_payment' end,p_note)
 returning id,orders.tracking_code into v_order,v_track;
 if p_discount_code is not null and v_cut>0 then
   insert into public.discount_redemptions(discount_id,order_id,user_id,amount_toman)
   values(v_discount.id,v_order,v_user,v_cut);
   update public.discount_codes set used_count=used_count+1 where id=v_discount.id;
 end if;
 insert into public.order_events(order_id,actor,event,details)
 values(v_order,'customer','created',jsonb_build_object('source','website'));
 return query select v_order,v_track,v_base-v_cut,v_cut;
end; $$;

revoke all on function public.issue_site_login_code(bigint,text) from public, anon, authenticated;
revoke all on function public.verify_site_login_code(bigint,text,text) from public, anon, authenticated;
revoke all on function public.create_site_order(text,text,integer,text,text) from public, anon, authenticated;
grant execute on function public.issue_site_login_code(bigint,text) to service_role;
grant execute on function public.verify_site_login_code(bigint,text,text) to service_role;
grant execute on function public.create_site_order(text,text,integer,text,text) to service_role;
