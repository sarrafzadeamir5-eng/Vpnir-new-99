import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: cors });
}
async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function rpc(name: string, args: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  const raw = await res.text();
  let data: unknown = null;
  try { data = raw ? JSON.parse(raw) : null; } catch { data = raw; }
  if (!res.ok) throw new Error(typeof data === "object" && data && "message" in data ? String((data as {message: unknown}).message) : "database_error");
  return data;
}
function sessionFrom(req: Request): string {
  const auth = req.headers.get("authorization") ?? "";
  return auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response({ error: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY) return response({ error: "server_not_configured" }, 500);

  try {
    const body = await req.json();
    const action = String(body?.action ?? "");

    if (action === "verify_login") {
      const telegramId = String(body.telegram_id ?? "").trim();
      const code = String(body.code ?? "").trim();
      if (!/^\d{5,15}$/.test(telegramId) || !/^\d{6}$/.test(code)) {
        return response({ error: "invalid_input" }, 400);
      }
      const token = randomToken();
      const userId = await rpc("verify_site_login_code", {
        p_telegram_id: Number(telegramId),
        p_code_hash: await sha256(code),
        p_token_hash: await sha256(token),
      });
      if (!userId) return response({ error: "invalid_or_expired_code" }, 401);
      return response({ ok: true, token });
    }

    const token = sessionFrom(req);
    if (!/^[a-f0-9]{64}$/.test(token)) return response({ error: "unauthorized" }, 401);
    const sessionHash = await sha256(token);

    if (action === "create_order") {
      const service = String(body.service ?? "");
      const quantity = body.quantity === null || body.quantity === "" ? null : Number(body.quantity);
      if (quantity !== null && (!Number.isInteger(quantity) || quantity < 1 || quantity > 1000)) {
        return response({ error: "invalid_quantity" }, 400);
      }
      const result = await rpc("create_site_order", {
        p_session_hash: sessionHash,
        p_service: service,
        p_quantity: quantity,
        p_discount_code: body.discount_code ? String(body.discount_code).trim() : null,
        p_note: body.note ? String(body.note).slice(0, 500) : null,
      });
      return response({ ok: true, order: Array.isArray(result) ? result[0] : result });
    }

    if (action === "preview_discount") {
      const service = String(body.service ?? "");
      const quantity = body.quantity === null || body.quantity === "" ? null : Number(body.quantity);
      const result = await rpc("preview_site_discount", {
        p_session_hash: sessionHash,
        p_service: service,
        p_quantity: quantity,
        p_discount_code: String(body.discount_code ?? "").trim(),
      });
      return response({ ok: true, preview: Array.isArray(result) ? result[0] : result });
    }

    if (action === "my_orders") {
      const result = await rpc("get_site_orders", { p_session_hash: sessionHash });
      return response({ ok: true, orders: result ?? [] });
    }

    if (action === "logout") {
      await rpc("revoke_site_session", { p_session_hash: sessionHash });
      return response({ ok: true });
    }

    return response({ error: "unknown_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "request_failed";
    const safe = ["invalid_discount", "invalid_quantity", "invalid_service", "unauthorized", "rate_limited"].includes(message)
      ? message : "request_failed";
    return response({ error: safe }, 400);
  }
});
