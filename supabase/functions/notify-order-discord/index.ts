import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });

const text = (value: unknown, fallback = "未填寫") => {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
};

const truncate = (value: unknown, maxLength = 1024) => {
  const normalized = text(value);
  return normalized.length > maxLength
    ? `${normalized.slice(0, Math.max(0, maxLength - 1))}…`
    : normalized;
};

const formatAmount = (value: unknown) => {
  if (value === null || value === undefined || value === "") {
    return "未填寫";
  }
  const amount = Number(value);
  return Number.isFinite(amount)
    ? `${amount.toLocaleString("en-US")} Gil`
    : "未填寫";
};

const getBearerToken = (request: Request) => {
  const authorization = request.headers.get("Authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1] || "";
};

type OrderOptionSnapshot = {
  label?: unknown;
  price_delta_text?: unknown;
  price_delta_amount?: unknown;
};

type OrderItem = {
  item_name_snapshot?: unknown;
  quantity?: unknown;
  selected_staff_name_snapshot?: unknown;
  selected_staff_special_label_snapshot?: unknown;
  selected_options_snapshot?: unknown;
  line_total_amount_snapshot?: unknown;
  price_amount_snapshot?: unknown;
  options_amount_snapshot?: unknown;
  sort_order?: unknown;
};

const formatOption = (option: OrderOptionSnapshot) => {
  const label = text(option.label, "未命名加購");
  const priceText = String(option.price_delta_text ?? "").trim();
  if (priceText) return `${label} ${priceText}`;
  const amount = Number(option.price_delta_amount);
  if (!Number.isFinite(amount)) return label;
  return `${label} ${amount >= 0 ? "+" : ""}${amount.toLocaleString("en-US")} Gil`;
};

const lineTotal = (item: OrderItem) => {
  if (
    item.line_total_amount_snapshot !== null &&
    item.line_total_amount_snapshot !== undefined &&
    item.line_total_amount_snapshot !== ""
  ) {
    const snapshot = Number(item.line_total_amount_snapshot);
    if (Number.isFinite(snapshot)) return snapshot;
  }
  if (
    item.price_amount_snapshot === null ||
    item.price_amount_snapshot === undefined ||
    item.price_amount_snapshot === ""
  ) {
    return null;
  }
  const price = Number(item.price_amount_snapshot);
  const options = Number(item.options_amount_snapshot || 0);
  const quantity = Number(item.quantity || 0);
  return Number.isFinite(price) && Number.isFinite(options) &&
      Number.isFinite(quantity)
    ? (price + options) * quantity
    : null;
};

const formatStaffSelection = (item: OrderItem) => {
  const staffName = text(item.selected_staff_name_snapshot, "");
  const specialLabel = text(item.selected_staff_special_label_snapshot, "");
  if (!staffName && !specialLabel) return "";

  // 「湯娘隱藏版」的 special label 通常是料理名稱，Discord 需要同時顯示
  // 員工名稱與料理名稱，例如：古嘿嘿｜墨魚麵。
  // 拍立得等其他品項維持原本的員工顯示，避免顯示成「員工｜服務標籤」。
  const itemName = text(item.item_name_snapshot, "");
  const isHiddenDish = /隱藏/.test(itemName);
  if (isHiddenDish && staffName && specialLabel && staffName !== specialLabel) {
    return `${staffName}｜${specialLabel}`;
  }

  return specialLabel || staffName;
};

const formatOrderItems = (items: OrderItem[]) => {
  const content = [...items]
    .sort((left, right) =>
      Number(left.sort_order || 0) - Number(right.sort_order || 0)
    )
    .map((item) => {
      const subtotal = lineTotal(item);
      const lines = [
        `・${text(item.item_name_snapshot)} × ${text(item.quantity, "1")}｜${
          formatAmount(subtotal)
        }`,
      ];
      const staff = formatStaffSelection(item);
      if (staff) lines.push(`　指定｜${staff}`);

      const options = Array.isArray(item.selected_options_snapshot)
        ? item.selected_options_snapshot as OrderOptionSnapshot[]
        : [];
      options.forEach((option) => {
        lines.push(`　＋${formatOption(option)}`);
      });
      return lines.join("\n");
    })
    .join("\n");
  return truncate(content || "未填寫");
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookUrl = Deno.env.get("DISCORD_ORDER_WEBHOOK_URL");
  if (!supabaseUrl || !serviceRoleKey || !webhookUrl) {
    console.error("Order notification secrets are not configured.");
    return jsonResponse({ error: "Notification service is not configured." }, 500);
  }

  let body: { order_id?: unknown; force?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  const orderId = String(body.order_id || "").trim();
  const force = body.force === true;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(orderId)
  ) {
    return jsonResponse({ error: "order_id must be a valid UUID." }, 400);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  if (force) {
    const accessToken = getBearerToken(request);
    if (!accessToken) {
      return jsonResponse({ error: "Authentication is required." }, 401);
    }
    const { data: userData, error: userError } =
      await serviceClient.auth.getUser(accessToken);
    if (userError || !userData.user) {
      return jsonResponse({ error: "Invalid authenticated session." }, 401);
    }
    const { data: profile, error: profileError } = await serviceClient
      .from("admin_profiles")
      .select("role, is_active")
      .eq("id", userData.user.id)
      .maybeSingle();
    const { data: permissions, error: permissionError } = await serviceClient
      .from("admin_profile_permissions")
      .select("permission_key, is_enabled")
      .eq("profile_id", userData.user.id)
      .eq("permission_key", "orders.manage")
      .eq("is_enabled", true);
    if (
      profileError ||
      permissionError ||
      !profile ||
      !profile.is_active ||
      (profile.role !== "owner" && !(permissions || []).length)
    ) {
      return jsonResponse({ error: "Order management permission is required." }, 403);
    }
  }

  const { data: order, error: orderError } = await serviceClient
    .from("orders")
    .select(
      `
      id, shop_key, customer_name, contact, note, requested_time,
      business_date, total_amount_snapshot, discord_status,
      discord_attempts, deleted_at
    `
    )
    .eq("id", orderId)
    .maybeSingle();

  if (orderError) {
    console.error("Failed to read order.", orderError);
    return jsonResponse({ error: "Failed to read order." }, 500);
  }
  if (!order) {
    return jsonResponse({ error: "Order not found." }, 404);
  }
  if (order.deleted_at) {
    return jsonResponse({ status: "skipped", reason: "Order is deleted." });
  }
  if (order.discord_status === "sent" && !force) {
    return jsonResponse({ status: "already_sent" });
  }

  const { data: orderItems, error: orderItemsError } = await serviceClient
    .from("order_items")
    .select(`
      item_name_snapshot, quantity, selected_staff_name_snapshot,
      selected_staff_special_label_snapshot, selected_options_snapshot,
      line_total_amount_snapshot, price_amount_snapshot,
      options_amount_snapshot, sort_order
    `)
    .eq("order_id", order.id)
    .order("sort_order", { ascending: true });
  if (orderItemsError) {
    console.error("Failed to read order items.", orderItemsError);
    return jsonResponse({ error: "Failed to read order items." }, 500);
  }

  const { data: shop, error: shopError } = await serviceClient
    .from("menus")
    .select(
      "title, short_title, order_contact_visible, order_note_visible, order_time_visible"
    )
    .eq("key", order.shop_key)
    .maybeSingle();
  if (shopError || !shop) {
    console.error("Failed to read order shop settings.", shopError);
    return jsonResponse({ error: "Failed to read order shop settings." }, 500);
  }

  const attempts = Number(order.discord_attempts || 0) + 1;
  const { error: attemptError } = await serviceClient
    .from("orders")
    .update({ discord_attempts: attempts })
    .eq("id", order.id);
  if (attemptError) {
    console.error("Failed to update Discord attempt count.", attemptError);
    return jsonResponse({ error: "Failed to update notification status." }, 500);
  }

  const shopName = text(
    shop.short_title || shop.title,
    order.shop_key === "menu2" ? "喫茶" : "湯宿"
  );
  const customerLines = [`角色 ID｜${text(order.customer_name)}`];
  if (shop.order_contact_visible !== false) {
    customerLines.push(`聯絡方式｜${text(order.contact)}`);
  }

  const serviceLines = [
    `店別｜${shopName}`,
    `營業日期｜${text(order.business_date)}`,
  ];
  if (shop.order_time_visible !== false) {
    serviceLines.push(`用餐時間｜${text(order.requested_time)}`);
  }

  const fields = [
    {
      name: "店別與時間",
      value: truncate(serviceLines.join("\n")),
    },
    {
      name: "來客資訊",
      value: truncate(customerLines.join("\n")),
    },
    {
      name: "出餐內容",
      value: formatOrderItems(
        Array.isArray(orderItems) ? orderItems : []
      ),
    },
    {
      name: "總金額",
      value: truncate(formatAmount(order.total_amount_snapshot)),
    },
    ...(shop.order_note_visible !== false
      ? [{
          name: "客人備註",
          value: truncate(order.note),
        }]
      : []),
  ];

  const discordPayload = {
    username: "嘿月湯宿",
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: "嘿月湯宿｜出餐通知",
        description: "已收到一筆新的用餐申請，請依內容安排出餐與服務。",
        color: 0x7b2937,
        fields,
        footer: {
          text: "Heyotsuki Yado ・ Order Notice",
        },
        timestamp: new Date().toISOString(),
      },
    ],
  };

  try {
    const discordResponse = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(discordPayload),
    });
    if (!discordResponse.ok) {
      const responseText = await discordResponse.text();
      throw new Error(
        `Discord webhook returned ${discordResponse.status}: ${
          responseText.slice(0, 500)
        }`
      );
    }

    const { error: successError } = await serviceClient
      .from("orders")
      .update({
        discord_status: "sent",
        discord_notified_at: new Date().toISOString(),
        discord_last_error: null,
      })
      .eq("id", order.id);
    if (successError) {
      console.error("Discord sent but status update failed.", successError);
      return jsonResponse(
        { error: "Discord sent, but notification status could not be saved." },
        500
      );
    }

    return jsonResponse({ status: "sent", attempts });
  } catch (error) {
    const errorMessage =
      error instanceof Error ? error.message : "Unknown Discord webhook error.";
    console.error("Discord order notification failed.", error);
    const { error: failureUpdateError } = await serviceClient
      .from("orders")
      .update({
        discord_status: "failed",
        discord_last_error: errorMessage.slice(0, 2000),
      })
      .eq("id", order.id);
    if (failureUpdateError) {
      console.error("Failed to save Discord error status.", failureUpdateError);
    }
    return jsonResponse({ error: errorMessage, status: "failed", attempts }, 502);
  }
});
