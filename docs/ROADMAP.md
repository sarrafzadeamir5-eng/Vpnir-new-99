# VPN IR implementation roadmap

## Phase 1 — repository foundation
- [x] Website starter and responsive service catalog
- [x] Telegram bot starter with service menu
- [x] Initial database schema
- [ ] Secure website login using one-time Telegram code
- [ ] Server-side order creation, tracking and status notifications
- [ ] Atomic discount validation/redemption shared by site and bot

## Phase 2 — operations
- [ ] Admin approval/rejection workflow with audit trail
- [ ] Receipt upload to private Supabase Storage bucket
- [ ] Premium quote flow and gift request/catalog management
- [ ] Daily Tehran-time report
- [ ] Admin web dashboard and role checks

## Phase 3 — deployment and verification
- [ ] Configure environment variables in hosting providers
- [ ] Deploy website and bot
- [ ] End-to-end tests for login, orders, discounts and admin actions

Prices currently configured in the UI/bot are starting display values. Before accepting payments, centralize them in server-side configuration and verify every calculation on the server.
