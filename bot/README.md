# VPN IR Telegram bot

## What is implemented
- `/start` and the menu.
- One-time website login code (6 digits, 5-minute expiry) through the `issue_site_login_code` Supabase RPC.
- Polling for website orders and sending the order details to the configured admin.
- Admin-only approve/reject buttons for orders awaiting review/payment confirmation.
- Customer notification after an admin decision.
- Automatic daily report at 21:00 Tehran time, plus the manual `/report` command.

## Setup
1. Use Python 3.11 or newer.
2. Install dependencies: `pip install -r requirements.txt`.
3. Set these environment variables in the hosting provider:
   - `BOT_TOKEN`
   - `ADMIN_TELEGRAM_ID` (default: `8356825459`)
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `SUPPORT_USERNAME` (default: `Vpn_IRan1400`)
   - `ORDER_POLL_SECONDS` (optional; default: 12)
   - `TIMEZONE` (optional; default: `Asia/Tehran`)
4. Apply the verified base schema first, then migrations `0002`, `0003` and `0004` in order. The repository currently does not include the original `0001` base schema; inspect the existing Supabase project and reconcile it before applying migrations.
5. Start with `python main.py` on a persistent worker.

## Important
- A customer must press Start in the bot before Telegram can send them a private message.
- The admin ID is checked on every callback; other users cannot approve or reject orders.
- Approval is a manual admin action. The bot does not verify bank receipts or automatically mark payments as paid.
- Premium requests are sent to the admin for manual handling; quote/acceptance flow is a later step.
- Keep the service-role key and bot token in hosting secrets only. Never commit a real `.env`.
- Run a single bot worker so the polling loop does not send duplicate admin notifications.
