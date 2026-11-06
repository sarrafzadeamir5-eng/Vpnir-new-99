-- VPN IR base schema. Fresh-project prerequisite for 0002+.
create table if not exists public.app_users (
 id uuid primary key default gen_random_uuid(),
 telegram_id bigint not null unique check (telegram_id > 0),
 telegram_username text,
 first_name text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.app_users(id) on delete restrict,
 tracking_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),
 source text not null check(source in ('website','telegram','admin')),
 service text not null check(service in ('france','multi','unlimited','stars','premium')),
 quantity integer check(quantity is null or quantity>0),
 amount_toman bigint not null default 0 check(amount_toman>=0),
 discount_toman bigint not null default 0 check(discount_toman>=0),
 status text not null default 'pending' check(status in ('pending','awaiting_payment','approved','rejected','cancelled','quoted','awaiting_customer')),
 customer_note text,payment_method text,receipt_path text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.discount_codes (
 id uuid primary key default gen_random_uuid(),code text not null,
 discount_type text not null check(discount_type in ('percent','fixed')),
 discount_value bigint not null check(discount_value>0 and (discount_type<>'percent' or discount_value<=100)),
 active boolean not null default true,starts_at timestamptz,ends_at timestamptz,
 min_order_toman bigint not null default 0 check(min_order_toman>=0),
 usage_limit integer check(usage_limit is null or usage_limit>0),
 used_count integer not null default 0 check(used_count>=0),
 applicable_services text[] not null default array['france','multi','unlimited','stars','premium']::text[],
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(length(trim(code)) between 3 and 40),
 check(ends_at is null or starts_at is null or ends_at>starts_at),
 check(applicable_services <@ array['france','multi','unlimited','stars','premium']::text[])
);
create unique index if not exists discount_codes_code_ci on public.discount_codes(upper(code));
create index if not exists discount_codes_active_idx on public.discount_codes(active,starts_at,ends_at);
create table if not exists public.order_events (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,
 actor text not null,event text not null,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create index if not exists order_events_order_created_idx on public.order_events(order_id,created_at desc);
create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);
create index if not exists orders_status_created_idx on public.orders(status,created_at desc);
create or replace function public.set_updated_at() returns trigger language plpgsql set search_path=public as $$
begin new.updated_at:=now();return new;end;$$;
drop trigger if exists app_users_set_updated_at on public.app_users;
create trigger app_users_set_updated_at before update on public.app_users for each row execute function public.set_updated_at();
drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at before update on public.orders for each row execute function public.set_updated_at();
drop trigger if exists discount_codes_set_updated_at on public.discount_codes;
create trigger discount_codes_set_updated_at before update on public.discount_codes for each row execute function public.set_updated_at();
alter table public.app_users enable row level security;
alter table public.orders enable row level security;
alter table public.discount_codes enable row level security;
alter table public.order_events enable row level security;
revoke all on all tables in schema public from anon,authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
alter default privileges for role postgres in schema public revoke all on tables from anon,authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges for role postgres in schema public grant all on tables to service_role;
alter default privileges for role postgres in schema public grant execute on functions to service_role;
