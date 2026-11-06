# Deployment notes

## Supabase
1. Review and apply `supabase/schema.sql`, then `supabase/migrations/0002_auth_orders_discounts.sql` in the SQL editor.
2. Deploy Edge Function `api`.
3. Set function secrets `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
4. Keep RLS enabled. Do not add public table policies for privileged tables.

## Website
The static site is in `web/`. Set only the Supabase project URL and publishable/anon key in browser configuration when the frontend API integration is completed. Never expose the service-role key.

## Telegram bot
Run `bot/main.py` on a persistent worker (for example Railway). Configure BOT_TOKEN, ADMIN_TELEGRAM_ID, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY as host secrets.

## Important
This repository currently contains a foundation, not a production-ready payment system. Test authentication, order creation, authorization, discounts, and notifications in a non-production environment first.
