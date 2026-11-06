# Deployment notes

## Important schema prerequisite
The repository currently does not contain the original `0001` base schema (nor a standalone `schema.sql`). Migration `0002_auth_orders_discounts.sql` assumes that `app_users`, `orders`, `discount_codes` and `order_events` already exist with the expected columns. The Supabase project may contain older production data. Do not run migrations blindly and do not drop or recreate existing tables. First inspect the current database schema and reconcile the missing base migration.

## Supabase
1. Back up the existing project and inspect the current tables/columns.
2. Confirm the base tables and columns required by migration `0002`.
3. Apply only the missing, reviewed migrations in order: `0002_auth_orders_discounts.sql`, `0003_bot_admin_workflow.sql`, then `0004_daily_reports.sql`.
4. Deploy Edge Function `api`.
5. Set function secrets `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
6. Keep RLS enabled. Do not add public table policies for privileged tables.

## Telegram bot
Run `bot/main.py` on a persistent worker (for example Railway). Configure `BOT_TOKEN`, `ADMIN_TELEGRAM_ID=8356825459`, `SUPPORT_USERNAME=Vpn_IRan1400`, `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` as host secrets. Apply migrations `0003` and `0004` before starting the bot. Run a single worker instance.

## Website
The current branch does not yet contain the website frontend. The Edge Function is backend-only. Add the frontend only after the API and database contracts are verified. The service-role key must never be included in browser code.

## Operational notes
- Customers must press Start in the Telegram bot before the bot can DM them.
- Login codes expire after five minutes and are single-use.
- Admin approval/rejection is manual; no receipt is automatically verified.
- Daily report is sent to the admin at 21:00 Asia/Tehran and can also be requested with `/report`.
- Test authentication, order creation, admin authorization, discounts and notifications in a non-production environment first.
