import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const enc = new TextEncoder();
async function sha(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(value));
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2,"0")).join("");
}
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const body = await req.json();
    if (body.action === "verify_login") {
      const telegramId = Number(body.telegram_id);
      const code = String(body.code ?? "").trim();
      if (!Number.isSafeInteger(telegramId) || telegramId <= 0 || !/^\d{6}$/.test(code)) return json({error:"invalid_input"},400);
      const token = crypto.randomUUID().replaceAll("-","") + crypto.randomUUID().replaceAll("-","");
      const { data, error } = await supabase.rpc("verify_site_login_code", {
        p_telegram_id: telegramId, p_code_hash: await sha(code), p_token_hash: await sha(token)
      });
      if (error) return json({error:"login_failed", detail:error.message},400);
      return json({ session_token: token, user_id: data, expires_in: 604800 });
    }
    if (body.action === "create_order") {
      const token = String(body.session_token ?? "");
      if (token.length < 40) return json({error:"unauthorized"},401);
      const { data, error } = await supabase.rpc("create_site_order", {
        p_session_hash: await sha(token), p_service: String(body.service ?? ""),
        p_quantity: body.quantity == null ? null : Number(body.quantity),
        p_discount_code: body.discount_code ? String(body.discount_code) : null,
        p_note: body.note ? String(body.note).slice(0,500) : null
      });
      if (error) return json({error:"order_failed", detail:error.message},400);
      return json({order:data?.[0] ?? null},201);
    }
    if (body.action === "track_order") {
      const code = String(body.tracking_code ?? "").trim().toUpperCase();
      if (!/^[A-F0-9]{8,16}$/.test(code)) return json({error:"invalid_tracking_code"},400);
      const { data, error } = await supabase.from("orders").select("tracking_code,service,quantity,amount_toman,discount_toman,status,created_at,updated_at").eq("tracking_code",code).maybeSingle();
      if (error) return json({error:"lookup_failed"},500);
      if (!data) return json({error:"not_found"},404);
      return json({order:data});
    }
    return json({error:"unknown_action"},400);
  } catch (_e) { return json({error:"bad_request"},400); }
});
