-- Telegram bot delivery marker for website orders.
-- Apply only after the base schema and 0002_auth_orders_discounts.sql.
alter table public.orders
  add column if not exists bot_notified_at timestamptz;

create index if not exists orders_website_bot_queue
  on public.orders(created_at)
  where source = 'website' and bot_notified_at is null;

-- The bot uses the service-role key on its private worker only.
-- Never expose service-role credentials in the website bundle.
