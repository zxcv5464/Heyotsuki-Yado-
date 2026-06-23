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
    ? `${normalized.slice(0, maxLength - 1)}…`
    : normalized;
};

const getBearerToken = (request: Request) => {
  const authorization = request.headers.get("Authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1] || "";
};

const DEFAULT_BUSINESS_HOURS = "週五 至 週日 PM 21:00 — 24:00";
const CORE_FIELD_KEYS = new Set([
  "customer_name",
  "contact",
  "reservation_date",
  "reservation_time",
  "party_size",
  "plan",
  "preferred_staff_name",
  "preferred_staff_2_name",
  "changing_together",
  "photo_service",
  "dessert_service",
  "note",
]);

const getOtherReplies = (formAnswers: unknown) => {
  if (
    !formAnswers ||
    typeof formAnswers !== "object" ||
    Array.isArray(formAnswers)
  ) {
    return "";
  }

  const replies = Object.entries(formAnswers)
    .filter(([fieldKey]) => !CORE_FIELD_KEYS.has(fieldKey))
    .map(([fieldKey, answer]) => {
      if (
        answer &&
        typeof answer === "object" &&
        !Array.isArray(answer)
      ) {
        const snapshot = answer as Record<string, unknown>;
        return {
          label: text(snapshot.label, fieldKey),
          value: String(
            snapshot.display_value ?? snapshot.value ?? ""
          ).trim(),
        };
      }
      return {
        label: fieldKey,
        value: String(answer ?? "").trim(),
      };
    })
    .filter((reply) => reply.value)
    .map((reply) => `${reply.label}｜${reply.value}`);

  return replies.length ? truncate(replies.join("\n")) : "";
};

const getBusinessHours = async (
  serviceClient: ReturnType<typeof createClient>
) => {
  const envFallback = text(
    Deno.env.get("DISCORD_RESERVATION_BUSINESS_HOURS"),
    DEFAULT_BUSINESS_HOURS
  );
  const { data, error } = await serviceClient
    .from("site_settings")
    .select("key, value")
    .in("key", ["openingDays", "openingHours"]);

  if (error) {
    console.warn(
      "Failed to read site business hours; using notification fallback.",
      error
    );
    return envFallback;
  }

  const settings = Object.fromEntries(
    (data || []).map((setting) => [setting.key, setting.value])
  );
  const openingDays = String(settings.openingDays || "").trim();
  const openingHours = String(settings.openingHours || "").trim();
  return openingDays && openingHours
    ? `${openingDays} ${openingHours}`
    : envFallback;
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
  const webhookUrl = Deno.env.get("DISCORD_RESERVATION_WEBHOOK_URL");
  if (!supabaseUrl || !serviceRoleKey || !webhookUrl) {
    console.error("Reservation notification secrets are not configured.");
    return jsonResponse({ error: "Notification service is not configured." }, 500);
  }

  let body: { reservation_id?: unknown; force?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  const reservationId = String(body.reservation_id || "").trim();
  const force = body.force === true;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(reservationId)) {
    return jsonResponse({ error: "reservation_id must be a valid UUID." }, 400);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  const businessHours = await getBusinessHours(serviceClient);

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
      .eq("permission_key", "reservations.manage")
      .eq("is_enabled", true);
    if (
      profileError ||
      permissionError ||
      !profile ||
      !profile.is_active ||
      (profile.role !== "owner" && !(permissions || []).length)
    ) {
      return jsonResponse({ error: "Reservation management permission is required." }, 403);
    }
  }

  const { data: reservation, error: reservationError } = await serviceClient
    .from("reservations")
    .select(
      "id, customer_name, contact, reservation_date, reservation_time, party_size, changing_together, plan, preferred_staff_name, preferred_staff_2_name, photo_service, dessert_service, note, form_answers, discord_status, discord_attempts, deleted_at"
    )
    .eq("id", reservationId)
    .maybeSingle();

  if (reservationError) {
    console.error("Failed to read reservation.", reservationError);
    return jsonResponse({ error: "Failed to read reservation." }, 500);
  }
  if (!reservation) {
    return jsonResponse({ error: "Reservation not found." }, 404);
  }
  if (reservation.deleted_at) {
    return jsonResponse({ status: "skipped", reason: "Reservation is deleted." });
  }
  if (reservation.discord_status === "sent" && !force) {
    return jsonResponse({ status: "already_sent" });
  }

  const attempts = Number(reservation.discord_attempts || 0) + 1;
  const { error: attemptError } = await serviceClient
    .from("reservations")
    .update({ discord_attempts: attempts })
    .eq("id", reservation.id);
  if (attemptError) {
    console.error("Failed to update Discord attempt count.", attemptError);
    return jsonResponse({ error: "Failed to update notification status." }, 500);
  }

  const otherReplies = getOtherReplies(reservation.form_answers);
  const discordPayload = {
    username: "嘿月湯宿",
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: "嘿月湯宿｜入宿預約通知",
        description: "已收到一筆新的入宿預約，請依資訊確認接待安排。",
        color: 0x7b2937,
        fields: [
          {
            name: "營業時間",
            value: truncate(businessHours),
          },
          {
            name: "來客資訊",
            value: truncate(
              `姓名｜${text(reservation.customer_name)}\n` +
                `聯絡｜${text(reservation.contact)}\n` +
                `日期｜${text(reservation.reservation_date)}\n` +
                `時段｜${text(reservation.reservation_time)}`
            ),
          },
          {
            name: "預約內容",
            value: truncate(
              `人數｜${text(reservation.party_size)}人\n` +
                `方案｜${text(reservation.plan)}\n` +
                `指定湯娘｜${text(reservation.preferred_staff_name)}\n` +
                `第二指定｜${text(reservation.preferred_staff_2_name)}`
            ),
          },
          {
            name: "混浴確認",
            value: truncate(reservation.changing_together),
          },
          {
            name: "現場安排",
            value: truncate(
              `拍照服務｜${text(reservation.photo_service)}\n` +
                `茶點安排｜${text(reservation.dessert_service)}`
            ),
          },
          {
            name: "備註事項",
            value: truncate(reservation.note),
          },
          ...(otherReplies
            ? [
                {
                  name: "其他回覆",
                  value: otherReplies,
                },
              ]
            : []),
        ],
        footer: {
          text: "Heyotsuki Yado ・ Reservation Notice",
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
        `Discord webhook returned ${discordResponse.status}: ${responseText.slice(0, 500)}`
      );
    }

    const { error: successError } = await serviceClient
      .from("reservations")
      .update({
        discord_status: "sent",
        discord_notified_at: new Date().toISOString(),
        discord_last_error: null,
      })
      .eq("id", reservation.id);
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
    console.error("Discord reservation notification failed.", error);
    const { error: failureUpdateError } = await serviceClient
      .from("reservations")
      .update({
        discord_status: "failed",
        discord_last_error: errorMessage.slice(0, 2000),
      })
      .eq("id", reservation.id);
    if (failureUpdateError) {
      console.error("Failed to save Discord error status.", failureUpdateError);
    }
    return jsonResponse({ error: errorMessage, status: "failed", attempts }, 502);
  }
});
