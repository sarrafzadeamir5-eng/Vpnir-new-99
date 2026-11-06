-- Initial VPN IR schema. Review and apply in a fresh Supabase project.
-- Never expose service_role keys in the browser.
create extension if not exists pgcrypto;

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  telegram_id bigint unique,
  username text,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  tracking_code text not null unique default upper(encode(gen_random_bytes(5),'hex')),
  user_id uuid references public.app_users(id),
  source text not null check (source in ('website','telegram','admin')),
  service text not null check (service in ('france','multi','unlimited','stars','premium','gift')),
  quantity integer,
  amount_toman bigint not null default 0 check (amount_toman >= 0),
  discount_toman bigint not null default 0 check (discount_toman >= 0),
  status text not null default 'pending' check (status in ('pending','awaiting_payment','paid','approved','rejected','cancelled','fulfilled')),
  customer_note text,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.discount_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value bigint not null check (discount_value > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  usage_limit integer,
  used_count integer not null default 0,
  min_order_toman bigint not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  actor text not null,
  event text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.app_users enable row level security;
alter table public.orders enable row level security;
alter table public.discount_codes enable row level security;
alter table public.order_events enable row level security;
-- No public policies are granted here. Add narrowly scoped policies/RPCs
-- only after the server-side authentication and authorization flow is implemented.
