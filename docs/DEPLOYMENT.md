# VPN IR deployment status

## Supabase
Project ref: `qsgnkjiqiwvpnrekyofk`.
The initial database schema and auth/order functions have been provisioned. Tables have RLS enabled and no public table policies; privileged operations run only through server-side service-role code. Never place `SUPABASE_SERVICE_ROLE_KEY` in frontend code.

Edge Function `vpnir-api` is deployed at:
`https://qsgnkjiqiwvpnrekyofk.supabase.co/functions/v1/vpnir-api`

The function implements Telegram-code login verification, order creation, discount preview and the user's order list. The login code is issued by the Telegram bot, expires after five minutes, and is single-use. The browser keeps the opaque session token in sessionStorage; only its SHA-256 hash is stored in the database.

## Website
Static frontend is in `web/`. It can be deployed to Netlify with the publish directory set to `web`. The frontend uses the Edge Function above. It does not contain a service-role key.

## Telegram bot
Run `bot/main.py` on one persistent worker (Railway is one option). Set these host secrets:
- `BOT_TOKEN`
- `SUPABASE_URL=https://qsgnkjiqiwvpnrekyofk.supabase.co`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMIN_TELEGRAM_ID=8356825459`
- `SUPPORT_USERNAME=Vpn_IRan1400`

The bot needs to be started by the user before it can send that user direct messages. Run one worker instance to avoid duplicate polling. The bot has not yet been deployed or tested against a live Telegram token.

## Current limitations
- A real bot username/deep link has not been supplied, so the website tells customers to open the bot and press Start without an automatic bot link.
- Payment receipts and online payment processing are not connected. Orders remain subject to manual review; the UI must not claim payment was verified.
- Premium pricing/quotation workflow and full admin dashboard are not implemented yet.
- Do not treat the service as production-ready until end-to-end tests are complete.
