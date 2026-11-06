import hashlib
import logging
import os
import secrets
import threading
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import telebot
from telebot import types
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

BOT_TOKEN = os.getenv("BOT_TOKEN", "").strip()
SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
ADMIN_TELEGRAM_ID = int(os.getenv("ADMIN_TELEGRAM_ID", "8356825459"))
SUPPORT_USERNAME = os.getenv("SUPPORT_USERNAME", "Vpn_IRan1400").lstrip("@")
POLL_SECONDS = max(5, int(os.getenv("ORDER_POLL_SECONDS", "12")))
TEHRAN = ZoneInfo(os.getenv("TIMEZONE", "Asia/Tehran"))

if not BOT_TOKEN or not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    raise RuntimeError("Set BOT_TOKEN, SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the host environment.")

bot = telebot.TeleBot(BOT_TOKEN, parse_mode="HTML")
db = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("vpnir-bot")

def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def is_admin(user_id: int) -> bool:
    return user_id == ADMIN_TELEGRAM_ID

def home_keyboard():
    keyboard = types.ReplyKeyboardMarkup(resize_keyboard=True)
    keyboard.row("🔐 کد ورود سایت", "📦 راهنمای سفارش")
    keyboard.row("🛟 پشتیبانی")
    return keyboard

@bot.message_handler(commands=["start"])
def start(message):
    name = (message.from_user.first_name or "دوست عزیز").replace("<", "").replace(">", "")
    bot.send_message(
        message.chat.id,
        f"سلام {name}، به ربات VPN IR خوش اومدی.\nبرای ورود به سایت، دکمه «کد ورود سایت» رو بزن.",
        reply_markup=home_keyboard(),
    )

@bot.message_handler(commands=["login", "code"])
def send_login_code(message):
    issue_login_code(message)

@bot.message_handler(func=lambda m: m.text == "🔐 کد ورود سایت")
def login_button(message):
    issue_login_code(message)

def issue_login_code(message):
    telegram_id = message.from_user.id
    code = f"{secrets.randbelow(1_000_000):06d}"
    try:
        db.rpc("issue_site_login_code", {
            "p_telegram_id": telegram_id,
            "p_code_hash": digest(code),
        }).execute()
        bot.send_message(
            message.chat.id,
            "کد ورود سایت VPN IR شما:\n"
            f"<code>{code}</code>\n\n"
            "این کد فقط ۵ دقیقه معتبره و فقط یک‌بار قابل استفاده‌ست. "
            "کد رو در اختیار هیچ‌کس قرار نده.",
        )
    except Exception:
        log.exception("Could not issue login code")
        bot.send_message(message.chat.id, "فعلاً صدور کد انجام نشد. چند دقیقه دیگه دوباره تلاش کن.")

@bot.message_handler(func=lambda m: m.text == "📦 راهنمای سفارش")
def order_help(message):
    bot.send_message(
        message.chat.id,
        "برای ثبت سفارش وارد سایت VPN IR شو، با کد همین ربات وارد حساب شو و سفارش رو ثبت کن.\n"
        "بعد از ثبت، کد پیگیری و وضعیت سفارش در پنل نمایش داده می‌شه.",
    )

@bot.message_handler(func=lambda m: m.text == "🛟 پشتیبانی")
def support(message):
    bot.send_message(message.chat.id, f"پشتیبانی: @{SUPPORT_USERNAME}")

def order_keyboard(order_id: str, service: str):
    keyboard = types.InlineKeyboardMarkup()
    if service != "premium":
        keyboard.row(
            types.InlineKeyboardButton("✅ تأیید پرداخت", callback_data=f"order:approve:{order_id}"),
            types.InlineKeyboardButton("❌ رد سفارش", callback_data=f"order:reject:{order_id}"),
        )
    else:
        keyboard.row(types.InlineKeyboardButton("❌ رد درخواست", callback_data=f"order:reject:{order_id}"))
    return keyboard

def service_label(service: str) -> str:
    return {
        "france": "VPN فرانسه",
        "multi": "VPN چندکشور",
        "unlimited": "VPN نامحدود",
        "stars": "تلگرام استارز",
        "premium": "درخواست تلگرام پریمیوم",
    }.get(service, service)

def format_order(order: dict, telegram_id: int | None) -> str:
    service = service_label(str(order.get("service", "")))
    quantity = order.get("quantity")
    amount = int(order.get("amount_toman") or 0)
    discount = int(order.get("discount_toman") or 0)
    track = order.get("tracking_code") or "—"
    note = (order.get("customer_note") or "—")
    return (
        "🧾 <b>سفارش جدید سایت VPN IR</b>\n"
        f"شناسه: <code>{order.get('id')}</code>\n"
        f"پیگیری: <code>{track}</code>\n"
        f"کاربر تلگرام: <code>{telegram_id or 'نامشخص'}</code>\n"
        f"سرویس: {service}\n"
        f"تعداد/حجم: {quantity if quantity is not None else '—'}\n"
        f"مبلغ نهایی: {amount:,} تومان\n"
        f"تخفیف: {discount:,} تومان\n"
        f"وضعیت: {order.get('status')}\n"
        f"توضیحات: {telebot.util.escape_html(str(note)[:500])}"
    )

def notify_new_orders():
    while True:
        try:
            response = (
                db.table("orders")
                .select("id,user_id,tracking_code,service,quantity,amount_toman,discount_toman,status,customer_note,source,created_at")
                .eq("source", "website")
                .is_("bot_notified_at", "null")
                .order("created_at")
                .limit(20)
                .execute()
            )
            for order in response.data or []:
                user_response = (
                    db.table("app_users")
                    .select("telegram_id")
                    .eq("id", order["user_id"])
                    .maybe_single()
                    .execute()
                )
                telegram_id = (user_response.data or {}).get("telegram_id")
                try:
                    bot.send_message(
                        ADMIN_TELEGRAM_ID,
                        format_order(order, telegram_id),
                        reply_markup=order_keyboard(order["id"], order.get("service", "")),
                    )
                    db.table("orders").update({"bot_notified_at": datetime.now(timezone.utc).isoformat()}).eq("id", order["id"]).is_("bot_notified_at", "null").execute()
                except Exception:
                    log.exception("Failed to deliver order %s to admin", order.get("id"))
        except Exception:
            log.exception("Order polling failed")
        time.sleep(POLL_SECONDS)

@bot.callback_query_handler(func=lambda call: call.data.startswith("order:"))
def handle_order_action(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "اجازه انجام این کار رو نداری.", show_alert=True)
        return
    try:
        _, action, order_id = call.data.split(":", 2)
        if action not in {"approve", "reject"}:
            raise ValueError("invalid action")
        new_status = "approved" if action == "approve" else "rejected"
        result = (
            db.table("orders")
            .update({"status": new_status})
            .eq("id", order_id)
            .in_("status", ["awaiting_payment", "pending"])
            .execute()
        )
        if not result.data:
            bot.answer_callback_query(call.id, "این سفارش قبلاً بررسی شده یا وجود نداره.", show_alert=True)
            return

        order = result.data[0]
        db.table("order_events").insert({
            "order_id": order_id,
            "actor": f"admin:{ADMIN_TELEGRAM_ID}",
            "event": new_status,
            "details": {"via": "telegram_admin_bot"},
        }).execute()

        user_response = (
            db.table("app_users")
            .select("telegram_id")
            .eq("id", order["user_id"])
            .maybe_single()
            .execute()
        )
        telegram_id = (user_response.data or {}).get("telegram_id")
        if telegram_id:
            customer_text = (
                f"سفارش <code>{order.get('tracking_code') or order_id}</code> "
                + ("تأیید شد ✅" if new_status == "approved" else "رد شد ❌")
            )
            bot.send_message(telegram_id, customer_text)

        label = "تأیید شد ✅" if new_status == "approved" else "رد شد ❌"
        bot.edit_message_reply_markup(call.message.chat.id, call.message.message_id, reply_markup=None)
        bot.answer_callback_query(call.id, label)
        bot.send_message(ADMIN_TELEGRAM_ID, f"وضعیت سفارش {order.get('tracking_code') or order_id}: {label}")
    except Exception:
        log.exception("Admin order action failed")
        bot.answer_callback_query(call.id, "خطا در ثبت تغییر وضعیت.", show_alert=True)

def daily_report_text():
    today = datetime.now(TEHRAN).date().isoformat()
    rows = (
        db.table("orders")
        .select("status,amount_toman,source,created_at")
        .gte("created_at", f"{today}T00:00:00+03:30")
        .lt("created_at", f"{today}T23:59:59+03:30")
        .execute()
    ).data or []
    approved = [r for r in rows if r.get("status") == "approved"]
    pending = [r for r in rows if r.get("status") in {"pending", "awaiting_payment"}]
    rejected = [r for r in rows if r.get("status") == "rejected"]
    website = sum(1 for r in rows if r.get("source") == "website")
    telegram = sum(1 for r in rows if r.get("source") == "telegram")
    sales = sum(int(r.get("amount_toman") or 0) for r in approved)
    return (
        "📊 <b>گزارش روزانه VPN IR</b>\\n"
        f"تاریخ: {today}\\n"
        f"کل سفارش‌ها: {len(rows)}\\n"
        f"سفارش سایت: {website} | سفارش ربات: {telegram}\\n"
        f"تأییدشده: {len(approved)}\\n"
        f"در انتظار: {len(pending)}\\n"
        f"ردشده: {len(rejected)}\\n"
        f"فروش سفارش‌های تأییدشده: {sales:,} تومان"
    )

@bot.message_handler(commands=["report"])
def daily_report_command(message):
    if not is_admin(message.from_user.id):
        return
    try:
        bot.send_message(message.chat.id, daily_report_text())
    except Exception:
        log.exception("Daily report failed")
        bot.send_message(message.chat.id, "گزارش فعلاً در دسترس نیست.")

def scheduled_daily_report():
    while True:
        try:
            now = datetime.now(TEHRAN)
            if now.hour >= 21:
                report_date = now.date().isoformat()
                existing = (
                    db.table("bot_daily_reports")
                    .select("report_date")
                    .eq("report_date", report_date)
                    .maybe_single()
                    .execute()
                )
                if not existing.data:
                    bot.send_message(ADMIN_TELEGRAM_ID, daily_report_text())
                    db.table("bot_daily_reports").insert({
                        "report_date": report_date,
                        "sent_at": datetime.now(timezone.utc).isoformat(),
                    }).execute()
        except Exception:
            log.exception("Scheduled daily report failed")
        time.sleep(30)

if __name__ == "__main__":
    threading.Thread(target=notify_new_orders, daemon=True).start()
    threading.Thread(target=scheduled_daily_report, daemon=True).start()
    log.info("VPN IR bot started")
    bot.infinity_polling(skip_pending=True, timeout=30, long_polling_timeout=30)
