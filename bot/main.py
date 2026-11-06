"""VPN IR Telegram bot starter. Secrets are read only from environment variables."""
import os
import logging
import telebot
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
from dotenv import load_dotenv

load_dotenv()
logging.basicConfig(level=logging.INFO)
TOKEN = os.getenv("BOT_TOKEN")
ADMIN_ID = int(os.getenv("ADMIN_TELEGRAM_ID", "8356825459"))
SUPPORT = os.getenv("SUPPORT_USERNAME", "Vpn_IRan1400").lstrip("@")
if not TOKEN:
    raise RuntimeError("BOT_TOKEN is required; copy .env.example and configure environment variables.")
bot = telebot.TeleBot(TOKEN, parse_mode="HTML")

def menu():
    kb = InlineKeyboardMarkup(row_width=2)
    kb.add(InlineKeyboardButton("VPN فرانسه", callback_data="france"),
           InlineKeyboardButton("VPN چندکشوری", callback_data="multi"),
           InlineKeyboardButton("VPN نامحدود", callback_data="unlimited"),
           InlineKeyboardButton("تلگرام استارز", callback_data="stars"),
           InlineKeyboardButton("تلگرام پریمیوم", callback_data="premium"))
    kb.add(InlineKeyboardButton("پشتیبانی", url=f"https://t.me/{SUPPORT}"))
    return kb

@bot.message_handler(commands=["start"])
def start(message):
    bot.send_message(message.chat.id,
        "به <b>VPN IR</b> خوش آمدی.\nبرای انتخاب خدمت از منوی زیر استفاده کن.",
        reply_markup=menu())

@bot.callback_query_handler(func=lambda call: call.data in {"france","multi","unlimited","stars","premium"})
def service(call):
    details = {
        "france": "VPN فرانسه: هر گیگ ۶٬۰۰۰ تومان؛ حداقل ۵ و حداکثر ۱۰۰ گیگابایت.",
        "multi": "VPN چندکشوری (۱۸ کشور): هر گیگ ۱۵٬۰۰۰ تومان؛ حداقل ۱۵ و حداکثر ۱۰۰ گیگابایت.",
        "unlimited": "VPN نامحدود ۳۰ روزه: ۳۹۹٬۰۰۰ تومان. احتمال قطعی روزانه ۱۰ تا ۲۰ دقیقه وجود دارد.",
        "stars": "تلگرام استارز: هر عدد ۴٬۷۵۰ تومان؛ حداقل ۵۰ و حداکثر ۱٬۰۰۰ عدد.",
        "premium": "برای تلگرام پریمیوم درخواست استعلام قیمت ثبت کن؛ قیمت توسط پشتیبانی اعلام می‌شود."
    }
    bot.answer_callback_query(call.id)
    bot.send_message(call.message.chat.id, details[call.data] +
        f"\n\nبرای ثبت سفارش نهایی و بررسی، با پشتیبانی تماس بگیر: @{SUPPORT}")

@bot.message_handler(commands=["admin"])
def admin(message):
    if message.from_user.id != ADMIN_ID:
        return
    bot.send_message(message.chat.id, "پنل مدیریتی کامل پس از اتصال امن دیتابیس و API فعال می‌شود.")

if __name__ == "__main__":
    logging.info("VPN IR bot starting")
    bot.infinity_polling(skip_pending=True, timeout=30, long_polling_timeout=30)
