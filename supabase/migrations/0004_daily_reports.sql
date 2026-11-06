-- Persistent deduplication for the automatic 21:00 Tehran daily report.
create table if not exists public.bot_daily_reports (
  report_date date primary key,
  sent_at timestamptz not null default now()
);
alter table public.bot_daily_reports enable row level security;
-- No anon/authenticated policies. Access is server-side only through the bot service-role client.
