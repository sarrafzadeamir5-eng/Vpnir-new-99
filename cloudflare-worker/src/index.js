const API = "https://api.telegram.org";
const tehranOffset = "+03:30";

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function escapeHtml(value = "") {
  return String(value).replace(/[&<>"]/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;",
  })[c]);
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function config(env) {
  for (const key of ["BOT_TOKEN", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "WEBHOOK_SECRET"]) {
    if (!env[key]) throw new Error("Missing environment variable: " + key);
  }
  return {
    token: env.BOT_TOKEN,
    supabase: env.SUPABASE_URL.replace(/\/$/, ""),
    serviceKey: env.SUPABASE_SERVICE_ROLE_KEY,
    adminId: String(env.ADMIN_TELEGRAM_ID || "8356825459"),
    support: String(env.SUPPORT_USERNAME || "Vpn_IRan1400").replace(/^@/, ""),
    webhookSecret: env.WEBHOOK_SECRET,
    setupSecret: env.SETUP_SECRET || "",
  };
}

async function telegram(env, method, payload = {}) {
  const c = config(env);
  const response = await fetch(`${API}/bot${c.token}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok || !data.ok) throw new Error("Telegram API error: " + (data.description || response.status));
  return data.result;
}

async function db(env, path, options = {}) {
  const c = config(env);
  const response = await fetch(c.supabase + "/rest/v1/" + path, {
    ...options,
    headers: {
      apikey: c.serviceKey,
      authorization: "Bearer " + c.serviceKey,
      "content-type": "application/json",
      ...(options.headers || {}),
      ...(options.method === "POST" ? { Prefer: "return=representation" } : {}),
    },
  });
  const body = await response.text();
  if (!response.ok) throw new Error("Supabase " + response.status + ": " + body.slice(0, 500));
  return body ? JSON.parse(body) : null;
}

async function rpc(env, name, args) {
  return db(env, "rpc/" + name, { method: "POST", body: JSON.stringify(args) });
}

async function send(env, chatId, text, extra = {}) {
  return telegram(env, "sendMessage", { chat_id: chatId, text, parse_mode: "HTML", ...extra });
}

function keyboard() {
  return {
    keyboard: [
      [{ text: "🔐 کد ورود سایت" }, { text: "📦 راهنمای سفارش" }],
      [{ text: "🛟 پشتیبانی" }],
    ],
    resize_keyboard: true,
  };
}

async function issueCode(env, message) {
  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1000000).padStart(6, "0");
  await rpc(env, "issue_site_login_code", {
    p_telegram_id: message.from.id,
    p_code_hash: await sha256(code),
  });
  await send(env, message.chat.id,
    "کد ورود سایت VPN IR شما:\n<code>" + code + "</code>\n\n" +
    "این کد فقط ۵ دقیقه معتبره و فقط یک‌بار قابل استفاده‌ست. کد رو در اختیار هیچ‌کس قرار نده."
  );
}

function serviceLabel(service) {
  return ({
    france: "VPN فرانسه",
    multi: "VPN چندکشور",
    unlimited: "VPN نامحدود",
    stars: "تلگرام استارز",
    premium: "درخواست تلگرام پریمیوم",
  })[service] || service || "—";
}

async function handleMessage(env, message) {
  if (!message?.from || !message?.chat) return;
  const text = String(message.text || "");
  if (text.startsWith("/start")) {
    const name = escapeHtml(message.from.first_name || "دوست عزیز");
    return send(env, message.chat.id,
      "سلام " + name + "، به ربات VPN IR خوش اومدی.\nبرای ورود به سایت، دکمه «کد ورود سایت» رو بزن.",
      { reply_markup: keyboard() }
    );
  }
  if (text === "/login" || text === "/code" || text === "🔐 کد ورود سایت") {
    try { return await issueCode(env, message); }
    catch (e) {
      console.error("issue code failed", e);
      return send(env, message.chat.id, "فعلاً صدور کد انجام نشد. چند دقیقه دیگه دوباره تلاش کن.");
    }
  }
  if (text === "📦 راهنمای سفارش") {
    return send(env, message.chat.id,
      "برای ثبت درخواست وارد سایت شو، با کد همین ربات وارد حساب شو و فرم درخواست رو تکمیل کن. وضعیت درخواست از طریق پنل و ربات اطلاع‌رسانی می‌شه."
    );
  }
  if (text === "🛟 پشتیبانی") {
    const c = config(env);
    return send(env, message.chat.id, "پشتیبانی: @" + escapeHtml(c.support));
  }
  if (text === "/report" && String(message.from.id) === config(env).adminId) {
    return send(env, message.chat.id, await dailyReport(env));
  }
}

async function handleCallback(env, call) {
  const c = config(env);
  if (String(call.from?.id) !== c.adminId) {
    return telegram(env, "answerCallbackQuery", {
      callback_query_id: call.id,
      text: "اجازه انجام این کار رو نداری.",
      show_alert: true,
    });
  }
  const match = /^order:(approve|reject):([0-9a-f-]+)$/i.exec(call.data || "");
  if (!match) return telegram(env, "answerCallbackQuery", { callback_query_id: call.id, text: "درخواست نامعتبر است." });
  const [, action, orderId] = match;
  const status = action === "approve" ? "approved" : "rejected";
  const rows = await db(env,
    "orders?id=eq." + encodeURIComponent(orderId) +
    "&status=in.(awaiting_payment,pending)&select=id,user_id,tracking_code,status",
    { method: "PATCH", body: JSON.stringify({ status }) }
  );
  if (!rows?.length) {
    return telegram(env, "answerCallbackQuery", {
      callback_query_id: call.id,
      text: "این سفارش قبلاً بررسی شده یا وجود نداره.",
      show_alert: true,
    });
  }
  const order = rows[0];
  await db(env, "order_events", {
    method: "POST",
    body: JSON.stringify({
      order_id: orderId,
      actor: "admin:" + c.adminId,
      event: status,
      details: { via: "telegram_admin_bot" },
    }),
  });
  const users = await db(env, "app_users? id=eq." + encodeURIComponent(order.user_id) + "&select=telegram_id".replace("? ", "?"));
  if (users?.[0]?.telegram_id) {
    await send(env, users[0].telegram_id,
      "درخواست <code>" + escapeHtml(order.tracking_code || orderId) + "</code> " +
      (status === "approved" ? "تأیید شد ✅" : "رد شد ❌")
    );
  }
  await telegram(env, "answerCallbackQuery", {
    callback_query_id: call.id,
    text: status === "approved" ? "تأیید شد" : "رد شد",
  });
  await telegram(env, "editMessageReplyMarkup", {
    chat_id: call.message.chat.id,
    message_id: call.message.message_id,
    reply_markup: { inline_keyboard: [] },
  });
}

async function handleUpdate(env, update) {
  if (update.message) return handleMessage(env, update.message);
  if (update.callback_query) return handleCallback(env, update.callback_query);
}

async function notifyOrders(env) {
  const c = config(env);
  const orders = await db(env,
    "orders?source=eq.website&bot_notified_at=is.null&select=id,user_id,tracking_code,service,quantity,amount_toman,discount_toman,status,customer_note,created_at&order=created_at.asc&limit=20"
  );
  for (const order of orders || []) {
    const users = await db(env,
      "app_users?id=eq." + encodeURIComponent(order.user_id) + "&select=telegram_id"
    );
    const telegramId = users?.[0]?.telegram_id;
    const amount = Number(order.amount_toman || 0).toLocaleString("en-US");
    const discount = Number(order.discount_toman || 0).toLocaleString("en-US");
    const note = escapeHtml(String(order.customer_note || "—").slice(0, 400));
    const text =
      "🧾 <b>درخواست جدید سایت</b>\n" +
      "شناسه: <code>" + escapeHtml(order.id) + "</code>\n" +
      "پیگیری: <code>" + escapeHtml(order.tracking_code || "—") + "</code>\n" +
      "کاربر تلگرام: <code>" + escapeHtml(telegramId || "نامشخص") + "</code>\n" +
      "نوع درخواست: " + escapeHtml(serviceLabel(order.service)) + "\n" +
      "تعداد/حجم: " + escapeHtml(order.quantity ?? "—") + "\n" +
      "مبلغ نهایی: " + amount + " تومان\n" +
      "تخفیف: " + discount + " تومان\n" +
      "وضعیت: " + escapeHtml(order.status) + "\n" +
      "توضیحات: " + note;
    const buttons = order.service === "premium" ? [] : [[
      { text: "✅ تأیید", callback_data: "order:approve:" + order.id },
      { text: "❌ رد", callback_data: "order:reject:" + order.id },
    ]];
    if (order.service === "premium") {
      buttons.push([{ text: "❌ رد درخواست", callback_data: "order:reject:" + order.id }]);
    }
    try {
      await send(env, c.adminId, text, { reply_markup: { inline_keyboard: buttons } });
      await db(env,
        "orders?id=eq." + encodeURIComponent(order.id) + "&bot_notified_at=is.null",
        { method: "PATCH", body: JSON.stringify({ bot_notified_at: new Date().toISOString() }) }
      );
    } catch (e) {
      console.error("order notification failed", order.id, e);
    }
  }
}

async function dailyReport(env) {
  const c = config(env);
  const now = new Date();
  const local = new Date(now.getTime() + 210 * 60000);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, "0");
  const d = String(local.getUTCDate()).padStart(2, "0");
  const date = y + "-" + m + "-" + d;
  const start = date + "T00:00:00" + tehranOffset;
  const end = date + "T23:59:59" + tehranOffset;
  const orders = await db(env,
    "orders?created_at=gte." + encodeURIComponent(start) +
    "&created_at=lte." + encodeURIComponent(end) +
    "&select=status,amount_toman,source"
  );
  const rows = orders || [];
  const approved = rows.filter(x => x.status === "approved");
  const pending = rows.filter(x => ["pending", "awaiting_payment"].includes(x.status));
  const rejected = rows.filter(x => x.status === "rejected");
  const website = rows.filter(x => x.source === "website").length;
  const telegram = rows.filter(x => x.source === "telegram").length;
  const sales = approved.reduce((sum, x) => sum + Number(x.amount_toman || 0), 0);
  return "📊 <b>گزارش روزانه</b>\nتاریخ: " + date +
    "\nکل درخواست‌ها: " + rows.length +
    "\nسایت: " + website + " | ربات: " + telegram +
    "\nتأییدشده: " + approved.length +
    "\nدر انتظار: " + pending.length +
    "\nردشده: " + rejected.length +
    "\nمجموع مبالغ تأییدشده: " + sales.toLocaleString("en-US") + " تومان";
}

async function scheduled(env) {
  await notifyOrders(env);
  const c = config(env);
  const now = new Date();
  const local = new Date(now.getTime() + 210 * 60000);
  if (local.getUTCHours() !== 21 || local.getUTCMinutes() > 1) return;
  const date = local.toISOString().slice(0, 10);
  const existing = await db(env, "bot_daily_reports?report_date=eq." + date + "&select=report_date");
  if (existing?.length) return;
  await send(env, c.adminId, await dailyReport(env));
  await db(env, "bot_daily_reports", {
    method: "POST",
    body: JSON.stringify({ report_date: date, sent_at: new Date().toISOString() }),
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/") {
        return json({ service: "VPNIR Telegram webhook", status: "ok" });
      }
      if (request.method === "POST" && url.pathname === "/telegram/webhook") {
        const secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token");
        if (secret !== config(env).webhookSecret) return json({ error: "unauthorized" }, 401);
        const update = await request.json();
        await handleUpdate(env, update);
        return json({ ok: true });
      }
      if (request.method === "POST" && url.pathname === "/setup-webhook") {
        const c = config(env);
        if (!c.setupSecret || request.headers.get("Authorization") !== "Bearer " + c.setupSecret) {
          return json({ error: "unauthorized" }, 401);
        }
        const webhookUrl = url.origin + "/telegram/webhook";
        const result = await telegram(env, "setWebhook", {
          url: webhookUrl,
          secret_token: c.webhookSecret,
          allowed_updates: ["message", "callback_query"],
          drop_pending_updates: true,
        });
        return json({ ok: result, webhook: webhookUrl });
      }
      return json({ error: "not_found" }, 404);
    } catch (e) {
      console.error(e);
      return json({ error: "internal_error" }, 500);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(scheduled(env));
  },
};
