import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});
const bearer = (request: Request) => (request.headers.get("Authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1] || "";
const uuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return json({ error: "帳號服務未設定 SUPABASE_SERVICE_ROLE_KEY。" }, 500);
  const token = bearer(request);
  if (!token) return json({ error: "需要登入後台。" }, 401);
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "請求格式錯誤。" }, 400); }
  const action = String(body.action || "");
  const profileId = String(body.profile_id || "");
  if (!uuid(profileId) || !["reset_password", "delete"].includes(action)) return json({ error: "帳號操作資料無效。" }, 400);
  const service = createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: callerUser, error: callerError } = await service.auth.getUser(token);
  if (callerError || !callerUser.user) return json({ error: "登入狀態已失效。" }, 401);
  const callerId = callerUser.user.id;
  const [{ data: caller }, { data: permissionRows }, { data: target }] = await Promise.all([
    service.from("admin_profiles").select("role, is_active").eq("id", callerId).maybeSingle(),
    service.from("admin_profile_permissions").select("permission_key, is_enabled").eq("profile_id", callerId).eq("permission_key", "accounts.manage"),
    service.from("admin_profiles").select("id, role, is_active").eq("id", profileId).maybeSingle(),
  ]);
  const callerIsOwner = caller?.is_active && caller.role === "owner";
  const canManage = callerIsOwner || (caller?.is_active && (permissionRows || []).some((row) => row.is_enabled));
  if (!canManage) return json({ error: "沒有帳號管理權限。" }, 403);
  if (!target) return json({ error: "帳號不存在。" }, 404);
  if (target.role === "owner" && !callerIsOwner) return json({ error: "只有 Owner 可以操作 Owner 帳號。" }, 403);
  if (action === "reset_password") {
    const password = String(body.password || "");
    if (password.length < 8) return json({ error: "新密碼至少需要 8 碼。" }, 400);
    const { error } = await service.auth.admin.updateUserById(profileId, { password });
    if (error) return json({ error: "密碼重設失敗。" }, 500);
    return json({ status: "password_reset" });
  }
  if (target.role === "owner" && target.is_active) {
    const { count } = await service.from("admin_profiles").select("id", { count: "exact", head: true }).eq("role", "owner").eq("is_active", true);
    if ((count || 0) <= 1) return json({ error: "不可註銷最後一位啟用 Owner。" }, 409);
  }
  const { error } = await service.auth.admin.deleteUser(profileId);
  if (error) return json({ error: "帳號註銷失敗。" }, 500);
  return json({ status: "deleted" });
});
