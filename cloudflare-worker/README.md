# VPN IR Telegram Worker

Cloudflare Worker webhook runtime for the Telegram bot. It uses Telegram webhooks and a one-minute scheduled task to notify the administrator about new website orders.

## Existing Cloudflare Worker

Use the Worker already created in Cloudflare: `vpnirnew99`.

- GitHub repository: `sarrafzadeamir5-eng/Vpnir-new-99`
- Root directory: `cloudflare-worker`
- Configuration: `wrangler.toml`
- Main file: `src/index.js`

The Worker configuration now uses the same name as the existing Cloudflare Worker.

## Required Cloudflare variables and secrets

In **Workers & Pages → vpnirnew99 → Settings → Variables and Secrets**, add the following.

Encrypted secrets:
- `BOT_TOKEN`: Telegram bot token
- `SUPABASE_SERVICE_ROLE_KEY`: service-role key for the Vpnir Supabase project
- `WEBHOOK_SECRET`: random secret string (32+ characters)
- `SETUP_SECRET`: a different random secret used only for webhook setup

Ordinary variables:
- `SUPABASE_URL`: `https://qsgnkjiqiwvpnrekyofk.supabase.co`
- `ADMIN_TELEGRAM_ID`: `8356825459`
- `SUPPORT_USERNAME`: `Vpn_IRan1400`

Never paste these secrets into chat, website JavaScript, or GitHub files. If a bot token was previously posted publicly or in a chat, rotate it with BotFather before using it.

## Deploy and connect Telegram

1. Confirm the GitHub integration points to the repository above and root directory `cloudflare-worker`.
2. Save the variables and encrypted secrets, then deploy the Worker.
3. Set the webhook once by sending an authenticated POST request to:
   `https://YOUR-WORKER-DOMAIN/setup-webhook`
   with header `Authorization: Bearer YOUR_SETUP_SECRET`.
4. Open `https://YOUR-WORKER-DOMAIN/`. It should return JSON with status `ok`.

Do not send the setup secret or bot token to anyone. The webhook URL is `/telegram/webhook`.

## Order notification flow

1. A customer signs in to the website using a one-time code from the Telegram bot.
2. The website creates an order through the existing Supabase Edge Function.
3. The scheduled Worker checks for website orders that have not yet been sent to the administrator.
4. The bot sends the administrator the tracking code, customer Telegram ID, service details, amount, status, and customer note.
5. After the administrator personally completes the order, they press **تحویل انجام شد**. The order is marked approved and the bot messages the customer's Telegram account.
6. The administrator can reject a request; the bot notifies the customer of that result as well.

The customer must have pressed Start in the Telegram bot before Telegram can message them.

## Supabase assumptions

The Worker uses the existing `app_users`, `orders`, `order_events`, and `bot_daily_reports` tables and the `issue_site_login_code` RPC. It expects migrations through `0005_site_dashboard.sql` to be applied to project `qsgnkjiqiwvpnrekyofk`, including `bot_notified_at` from migration `0003_bot_admin_workflow.sql`.

The service-role key stays exclusively in the Cloudflare Worker secret store. It must never be added to the website bundle.
