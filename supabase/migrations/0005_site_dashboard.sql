-- Admin/support/catalog/wallet tables and authenticated website dashboard API.
create table if not exists public.admin_audit_log (
 id uuid primary key default gen_random_uuid(), admin_telegram_id bigint not null,
 action text not null, entity_type text, entity_id text,
 details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created_idx on public.admin_audit_log(created_at desc);
create table if not exists public.support_tickets (
 id uuid primary key default gen_random_uuid(), user_id uuid references public.app_users(id) on delete set null,
 telegram_id bigint, subject text not null, message text not null,
 status text not null default 'open' check(status in ('open','in_progress','closed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.gift_catalog (
 id uuid primary key default gen_random_uuid(), title text not null, description text,
 price_toman bigint not null default 0 check(price_toman>=0), image_path text,
 active boolean not null default true, sort_order integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.wallet_transactions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.app_users(id) on delete restrict,
 amount_toman bigint not null check(amount_toman<>0),
 transaction_type text not null check(transaction_type in ('credit','debit','refund','adjustment')),
 description text, reference_order_id uuid references public.orders(id) on delete set null,
 created_at timestamptz not null default now()
);
create index if not exists wallet_transactions_user_created_idx on public.wallet_transactions(user_id,created_at desc);
alter table public.admin_audit_log enable row level security;
alter table public.support_tickets enable row level security;
alter table public.gift_catalog enable row level security;
alter table public.wallet_transactions enable row level security;
revoke all on public.admin_audit_log,public.support_tickets,public.gift_catalog,public.wallet_transactions from anon,authenticated;
grant all on public.admin_audit_log,public.support_tickets,public.gift_catalog,public.wallet_transactions to service_role;
drop trigger if exists support_tickets_set_updated_at on public.support_tickets;
create trigger support_tickets_set_updated_at before update on public.support_tickets for each row execute function public.set_updated_at();
drop trigger if exists gift_catalog_set_updated_at on public.gift_catalog;
create trigger gift_catalog_set_updated_at before update on public.gift_catalog for each row execute function public.set_updated_at();

-- Dashboard order history: raw session token is never stored; callers send its SHA-256 hash.
create or replace function public.get_site_orders(p_session_hash text)
returns table(tracking_code text,service text,quantity integer,amount_toman bigint,discount_toman bigint,status text,created_at timestamptz,customer_note text)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid;
begin
 if p_session_hash !~ '^[a-f0-9]{64}$' then return; end if;
 select user_id into v_user from public.site_sessions where token_hash=p_session_hash and revoked_at is null and expires_at>now();
 if v_user is null then return; end if;
 return query select o.tracking_code,o.service,o.quantity,o.amount_toman,o.discount_toman,o.status,o.created_at,o.customer_note
 from public.orders o where o.user_id=v_user order by o.created_at desc limit 50;
end; $$;

create or replace function public.revoke_site_session(p_session_hash text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_session_hash !~ '^[a-f0-9]{64}$' then return; end if;
 update public.site_sessions set revoked_at=now() where token_hash=p_session_hash and revoked_at is null;
end; $$;

-- Hardened login-code issuance and verification.
create or replace function public.issue_site_login_code(p_telegram_id bigint,p_code_hash text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_recent integer;
begin
 if p_telegram_id is null or p_telegram_id<=0 or p_code_hash !~ '^[a-f0-9]{64}$' then raise exception 'invalid_input'; end if;
 select count(*) into v_recent from public.login_codes where telegram_id=p_telegram_id and created_at>now()-interval '1 hour';
 if v_recent>=5 then raise exception 'rate_limited'; end if;
 update public.login_codes set consumed_at=now() where telegram_id=p_telegram_id and consumed_at is null;
 insert into public.login_codes(telegram_id,code_hash,expires_at) values(p_telegram_id,p_code_hash,now()+interval '5 minutes');
end; $$;

create or replace function public.verify_site_login_code(p_telegram_id bigint,p_code_hash text,p_token_hash text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_code public.login_codes%rowtype; v_user_id uuid;
begin
 if p_telegram_id is null or p_telegram_id<=0 or p_code_hash !~ '^[a-f0-9]{64}$' or p_token_hash !~ '^[a-f0-9]{64}$' then return null; end if;
 select * into v_code from public.login_codes where telegram_id=p_telegram_id and consumed_at is null and expires_at>now()
 order by created_at desc limit 1 for update;
 if not found or v_code.attempts>=5 then return null; end if;
 if v_code.code_hash<>p_code_hash then update public.login_codes set attempts=attempts+1 where id=v_code.id; return null; end if;
 update public.login_codes set consumed_at=now() where id=v_code.id;
 insert into public.app_users(telegram_id) values(p_telegram_id)
 on conflict(telegram_id) do update set telegram_id=excluded.telegram_id returning id into v_user_id;
 insert into public.site_sessions(user_id,token_hash,expires_at) values(v_user_id,p_token_hash,now()+interval '7 days');
 return v_user_id;
end; $$;

create or replace function public.create_site_order(
 p_session_hash text,p_service text,p_quantity integer default null,p_discount_code text default null,p_note text default null
) returns table(order_id uuid,tracking_code text,amount_toman bigint,discount_toman bigint)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_unit bigint; v_base bigint; v_discount public.discount_codes%rowtype; v_cut bigint:=0; v_order uuid; v_track text;
begin
 if p_session_hash !~ '^[a-f0-9]{64}$' then raise exception 'unauthorized'; end if;
 select user_id into v_user from public.site_sessions where token_hash=p_session_hash and revoked_at is null and expires_at>now();
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
  select * into v_discount from public.discount_codes where upper(code)=upper(trim(p_discount_code)) for update;
  if not found or not v_discount.active or (v_discount.starts_at is not null and now()<v_discount.starts_at)
   or (v_discount.ends_at is not null and now()>v_discount.ends_at)
   or (v_discount.usage_limit is not null and v_discount.used_count>=v_discount.usage_limit)
   or v_base<v_discount.min_order_toman or not(p_service=any(v_discount.applicable_services)) then raise exception 'invalid_discount'; end if;
  v_cut:=case when v_discount.discount_type='percent' then floor(v_base*least(v_discount.discount_value,100)/100.0)::bigint else least(v_base,v_discount.discount_value) end;
 end if;
 insert into public.orders(user_id,source,service,quantity,amount_toman,discount_toman,status,customer_note)
 values(v_user,'website',p_service,p_quantity,v_base-v_cut,v_cut,case when p_service='premium' then 'pending' else 'awaiting_payment' end,left(p_note,500))
 returning id,orders.tracking_code into v_order,v_track;
 if p_discount_code is not null and v_cut>0 then
  insert into public.discount_redemptions(discount_id,order_id,user_id,amount_toman) values(v_discount.id,v_order,v_user,v_cut);
  update public.discount_codes set used_count=used_count+1 where id=v_discount.id;
 end if;
 insert into public.order_events(order_id,actor,event,details) values(v_order,'customer','created',jsonb_build_object('source','website'));
 return query select v_order,v_track,v_base-v_cut,v_cut;
end; $$;

create or replace function public.preview_site_discount(p_session_hash text,p_service text,p_quantity integer,p_discount_code text)
returns table(valid boolean,discount_toman bigint,final_amount_toman bigint,reason text)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_unit bigint; v_base bigint; v_d public.discount_codes%rowtype; v_cut bigint:=0;
begin
 select user_id into v_user from public.site_sessions where token_hash=p_session_hash and revoked_at is null and expires_at>now();
 if v_user is null then return query select false,0::bigint,0::bigint,'unauthorized'; return; end if;
 if p_service='france' and p_quantity between 5 and 100 then v_unit:=6000;
 elsif p_service='multi' and p_quantity between 15 and 100 then v_unit:=15000;
 elsif p_service='stars' and p_quantity between 50 and 1000 then v_unit:=4750;
 elsif p_service='unlimited' and p_quantity is null then v_unit:=399000;
 else return query select false,0::bigint,0::bigint,'invalid_service_or_quantity'; return; end if;
 v_base:=case when p_service='unlimited' then v_unit else v_unit*p_quantity end;
 select * into v_d from public.discount_codes where upper(code)=upper(trim(p_discount_code));
 if not found or not v_d.active or (v_d.starts_at is not null and now()<v_d.starts_at)
  or (v_d.ends_at is not null and now()>v_d.ends_at)
  or (v_d.usage_limit is not null and v_d.used_count>=v_d.usage_limit)
  or v_base<v_d.min_order_toman or not(p_service=any(v_d.applicable_services)) then
  return query select false,0::bigint,v_base,'invalid_discount'; return;
 end if;
 v_cut:=case when v_d.discount_type='percent' then floor(v_base*least(v_d.discount_value,100)/100.0)::bigint else least(v_base,v_d.discount_value) end;
 return query select true,v_cut,v_base-v_cut,'ok';
end; $$;

revoke all on function public.get_site_orders(text) from public,anon,authenticated;
revoke all on function public.revoke_site_session(text) from public,anon,authenticated;
revoke all on function public.issue_site_login_code(bigint,text) from public,anon,authenticated;
revoke all on function public.verify_site_login_code(bigint,text,text) from public,anon,authenticated;
revoke all on function public.create_site_order(text,text,integer,text,text) from public,anon,authenticated;
revoke all on function public.preview_site_discount(text,text,integer,text) from public,anon,authenticated;
grant execute on function public.get_site_orders(text) to service_role;
grant execute on function public.revoke_site_session(text) to service_role;
grant execute on function public.issue_site_login_code(bigint,text) to service_role;
grant execute on function public.verify_site_login_code(bigint,text,text) to service_role;
grant execute on function public.create_site_order(text,text,integer,text,text) to service_role;
grant execute on function public.preview_site_discount(text,text,integer,text) to service_role;
grant all on public.admin_audit_log,public.support_tickets,public.gift_catalog,public.wallet_transactions to service_role;

-- Admin RPCs are reachable only through the Edge Function using service_role.
create or replace function public.is_admin_session(p_session_hash text)
returns boolean language sql security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.site_sessions s join public.app_users u on u.id=s.user_id
  where s.token_hash=p_session_hash and s.revoked_at is null and s.expires_at>now() and u.telegram_id=8356825459);
$$;
create or replace function public.admin_list_orders(p_session_hash text)
returns table(order_id uuid,tracking_code text,telegram_id bigint,service text,quantity integer,amount_toman bigint,discount_toman bigint,status text,created_at timestamptz,customer_note text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_admin_session(p_session_hash) then raise exception 'forbidden'; end if;
 return query select o.id,o.tracking_code,u.telegram_id,o.service,o.quantity,o.amount_toman,o.discount_toman,o.status,o.created_at,o.customer_note
 from public.orders o join public.app_users u on u.id=o.user_id order by o.created_at desc limit 200;
end; $$;
create or replace function public.admin_list_discounts(p_session_hash text)
returns table(id uuid,code text,discount_type text,discount_value bigint,active boolean,starts_at timestamptz,ends_at timestamptz,min_order_toman bigint,usage_limit integer,used_count integer,applicable_services text[])
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_admin_session(p_session_hash) then raise exception 'forbidden'; end if;
 return query select d.id,d.code,d.discount_type,d.discount_value,d.active,d.starts_at,d.ends_at,d.min_order_toman,d.usage_limit,d.used_count,d.applicable_services from public.discount_codes d order by d.created_at desc;
end; $$;
create or replace function public.admin_save_discount(p_session_hash text,p_code text,p_type text,p_value bigint,p_active boolean default true,p_starts_at timestamptz default null,p_ends_at timestamptz default null,p_min_order bigint default 0,p_usage_limit integer default null,p_services text[] default array['france','multi','unlimited','stars','premium']::text[])
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;v_code text:=upper(trim(p_code));
begin
 if not public.is_admin_session(p_session_hash) then raise exception 'forbidden'; end if;
 if length(v_code)<3 or length(v_code)>40 or p_type not in ('percent','fixed') or p_value<=0 or (p_type='percent' and p_value>100)
 or p_min_order<0 or (p_usage_limit is not null and p_usage_limit<1) or (p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at)
 or cardinality(p_services)=0 or not(p_services <@ array['france','multi','unlimited','stars','premium']::text[]) then raise exception 'invalid_discount_data'; end if;
 select id into v_id from public.discount_codes where upper(code)=v_code for update;
 if v_id is null then
  insert into public.discount_codes(code,discount_type,discount_value,active,starts_at,ends_at,min_order_toman,usage_limit,applicable_services)
  values(v_code,p_type,p_value,p_active,p_starts_at,p_ends_at,p_min_order,p_usage_limit,p_services) returning id into v_id;
 else
  update public.discount_codes set discount_type=p_type,discount_value=p_value,active=p_active,starts_at=p_starts_at,ends_at=p_ends_at,min_order_toman=p_min_order,usage_limit=p_usage_limit,applicable_services=p_services where id=v_id;
 end if;
 insert into public.admin_audit_log(admin_telegram_id,action,entity_type,entity_id,details) values(8356825459,'save_discount','discount_code',v_id::text,jsonb_build_object('code',v_code,'type',p_type,'value',p_value));
 return v_id;
end; $$;
create or replace function public.admin_toggle_discount(p_session_hash text,p_discount_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not public.is_admin_session(p_session_hash) then raise exception 'forbidden'; end if;
 update public.discount_codes set active=p_active where id=p_discount_id;
 insert into public.admin_audit_log(admin_telegram_id,action,entity_type,entity_id,details) values(8356825459,'toggle_discount','discount_code',p_discount_id::text,jsonb_build_object('active',p_active));
end; $$;
revoke all on function public.is_admin_session(text) from public,anon,authenticated;
revoke all on function public.admin_list_orders(text) from public,anon,authenticated;
revoke all on function public.admin_list_discounts(text) from public,anon,authenticated;
revoke all on function public.admin_save_discount(text,text,text,bigint,boolean,timestamptz,timestamptz,bigint,integer,text[]) from public,anon,authenticated;
revoke all on function public.admin_toggle_discount(text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.is_admin_session(text) to service_role;
grant execute on function public.admin_list_orders(text) to service_role;
grant execute on function public.admin_list_discounts(text) to service_role;
grant execute on function public.admin_save_discount(text,text,text,bigint,boolean,timestamptz,timestamptz,bigint,integer,text[]) to service_role;
grant execute on function public.admin_toggle_discount(text,uuid,boolean) to service_role;
