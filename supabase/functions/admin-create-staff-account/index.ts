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
const text = (value: unknown) => String(value ?? "").trim();
const uuid = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Account service is not configured." }, 500);
  const token = bearer(request);
  if (!token) return json({ error: "Authentication is required." }, 401);

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Request body must be valid JSON." }, 400); }
  const email = text(body.email).toLowerCase();
  const password = String(body.password ?? "");
  const displayName = text(body.display_name);
  const role = text(body.role);
  const staffId = text(body.staff_id);
  const templateId = text(body.template_id);
  const isActive = body.is_active !== false;
  if (!/^\S+@\S+\.\S+$/.test(email) || password.length < 8 || !displayName) return json({ error: "請填寫有效 Email、至少 8 碼的初始密碼與顯示名稱。" }, 400);
  if (!["owner", "admin", "staff"].includes(role)) return json({ error: "帳號角色無效。" }, 400);
  if (role === "staff" && !staffId) return json({ error: "一般員工帳號沒有傳入綁定員工。" }, 400);
  if (role === "staff" && !uuid(staffId)) return json({ error: "綁定員工資料格式無效，請重新讀取帳號管理頁後再試。" }, 400);
  if (!uuid(templateId)) return json({ error: "請選擇權限模板。" }, 400);

  const service = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: userData, error: userError } = await service.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "登入狀態已失效。" }, 401);
  const callerId = userData.user.id;
  const [{ data: caller }, { data: callerPermissions }] = await Promise.all([
    service.from("admin_profiles").select("role, is_active").eq("id", callerId).maybeSingle(),
    service.from("admin_profile_permissions").select("permission_key, is_enabled").eq("profile_id", callerId),
  ]);
  const callerIsOwner = caller?.is_active && caller.role === "owner";
  const permissionSet = new Set((callerPermissions || []).filter((item) => item.is_enabled).map((item) => item.permission_key));
  if (!caller?.is_active || (!callerIsOwner && !permissionSet.has("accounts.manage"))) return json({ error: "沒有帳號管理權限。" }, 403);
  if (role === "owner" && !callerIsOwner) return json({ error: "只有 Owner 可以建立 Owner 帳號。" }, 403);

  const [{ data: template }, { data: definitions }] = await Promise.all([
    service.from("admin_permission_templates").select("id").eq("id", templateId).maybeSingle(),
    service.from("admin_permission_definitions").select("permission_key"),
  ]);
  if (!template) return json({ error: "權限模板不存在。" }, 400);
  const { data: templateItems } = await service.from("admin_permission_template_items").select("permission_key, is_enabled").eq("template_id", templateId);
  if (!callerIsOwner && (templateItems || []).some((item) => item.is_enabled && ["accounts.manage", "permissions.manage"].includes(item.permission_key))) return json({ error: "只有 Owner 可以授予帳號或權限管理權。" }, 403);
  if (staffId) {
    const { data: linked } = await service.from("admin_profiles").select("id").eq("staff_id", staffId).maybeSingle();
    if (linked) return json({ error: "此員工已綁定其他後台帳號。" }, 409);
    const { data: staff } = await service.from("staff_members").select("id").eq("id", staffId).maybeSingle();
    if (!staff) return json({ error: "綁定員工不存在。" }, 400);
  }

  const { data: created, error: createError } = await service.auth.admin.createUser({ email, password, email_confirm: true });
  if (createError || !created.user) return json({ error: "帳號建立失敗，Email 可能已存在。" }, 409);
  try {
    const { error: profileError } = await service.from("admin_profiles").insert({
      id: created.user.id, display_name: displayName, role, staff_id: staffId || null,
      permission_template_id: templateId, is_active: isActive,
    });
    if (profileError) throw profileError;
    if (role !== "owner") {
      const knownKeys = new Set((definitions || []).map((item) => item.permission_key));
      const permissionKeys = new Set(
        (templateItems || []).filter((item) => item.is_enabled).map((item) => item.permission_key)
      );
      for (const permissionKey of [...permissionKeys]) {
        if (!permissionKey.endsWith(".manage")) continue;
        const viewKey = `${permissionKey.slice(0, -".manage".length)}.view`;
        if (knownKeys.has(viewKey)) permissionKeys.add(viewKey);
      }
      const rows = [...permissionKeys].map((permission_key) => ({ profile_id: created.user.id, permission_key, is_enabled: true }));
      if (rows.length) {
        const { error: permissionError } = await service.from("admin_profile_permissions").insert(rows);
        if (permissionError) throw permissionError;
      }
    }
  } catch {
    await service.auth.admin.deleteUser(created.user.id);
    return json({ error: "帳號資料建立失敗，已取消建立。" }, 500);
  }
  return json({ id: created.user.id, status: "created" });
});
