# VPN IR Telegram Worker

This is a Cloudflare Workers webhook runtime for the Telegram bot. It replaces the Python long-polling process with an HTTPS webhook and a one-minute scheduled task.

## Cloudflare setup

1. In Cloudflare, open **Workers & Pages** and choose **Create application → Worker**.
2. Connect the GitHub repository `sarrafzadeamir5-eng/Vpnir-new-99`.
3. Set the root directory to `cloudflare-worker` and deploy using the checked-in `wrangler.toml`.
4. In Worker **Settings → Variables and Secrets**, add these as encrypted secrets:
   - `BOT_TOKEN`: Telegram bot token (never put it in GitHub)
   - `SUPABASE_SERVICE_ROLE_KEY`: service-role key for the Vpnir Supabase project (never expose it in browser code)
   - `WEBHOOK_SECRET`: random string of 32+ characters using letters, digits, underscore, or hyphen
   - `SETUP_SECRET`: a separate random string used only to protect webhook setup
5. Add these as ordinary variables:
   - `SUPABASE_URL`: `https://qsgnkjiqiwvpnrekyofk.supabase.co`
   - `ADMIN_TELEGRAM_ID`: `8356825459`
   - `SUPPORT_USERNAME`: `Vpn_IRan1400`
6. Deploy again after saving variables.
7. Set the Telegram webhook once by sending an authenticated POST request to:
   `https://YOUR-WORKER-DOMAIN/setup-webhook`
   with header `Authorization: Bearer YOUR_SETUP_SECRET`.
   Example:
   `curl -X POST https://YOUR-WORKER-DOMAIN/setup-webhook -H "Authorization: Bearer YOUR_SETUP_SECRET"`
8. Open `https://YOUR-WORKER-DOMAIN/`. It should return JSON with status `ok`.

## Supabase assumptions

The Worker uses the existing `app_users`, `orders`, `order_events`, and `bot_daily_reports` tables and the `issue_site_login_code` RPC. It expects the migrations already applied to project `qsgnkjiqiwvpnrekyofk`.

## Important

- Do not commit bot tokens or Supabase service-role keys.
- Keep the service-role key only in Worker secrets.
- Telegram users must press Start before the bot can message them.
- The Worker handles login codes, admin order notifications/actions, and daily reports. It does not provision or deliver any third-party service.
