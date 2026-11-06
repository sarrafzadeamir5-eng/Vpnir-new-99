# Telegram bot setup

1. Install Python 3.11+ and run `pip install -r requirements.txt`.
2. Copy the root `.env.example` to a local `.env`; fill in BOT_TOKEN and Supabase server credentials.
3. Never commit `.env` or paste the bot token into source code.
4. Start the bot with `python main.py`.

The current bot menu is a starter interface. The next integration step is to add a Telegram account-link/code command backed by the `issue_site_login_code` RPC and administrator order callbacks. Do not enable real payment acceptance until that workflow has been tested.
