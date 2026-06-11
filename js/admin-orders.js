(function () {
  "use strict";

  const SHOPS = {
    menu: "湯宿",
    menu2: "喫茶"
  };

  const STATUS_LABELS = {
    pending: "待確認",
    accepted: "已接受",
    preparing: "準備中",
    served: "已送達",
    cancelled: "已取消"
  };
  const DISCORD_STATUS_LABELS = {
    pending: "待推送",
    sent: "已推送",
    failed: "推送失敗",
    skipped: "已略過"
  };
  const SOUND_STORAGE_KEY = "heyotsuki.orderSoundEnabled";
  const POLL_INTERVAL_MS = 30000;
  const BASE_TITLE = document.title;
  const favicon = document.querySelector("[data-order-favicon]");
  const BASE_FAVICON = favicon?.href || "";

  const state = {
    client: null,
    session: null,
    profile: null,
    permissions: new Map(),
    shops: [],
    shopKey: "",
    orders: [],
    shopSettings: null,
    unreadByShop: new Map(),
    knownOrderIds: new Set(),
    realtimeChannel: null,
    pollTimer: null,
    audioContext: null,
    audioUnlocked: false,
    soundEnabled: false,
    destroyed: false,
    dirtyOrderIds: new Set()
  };

  const accessPanel = document.querySelector("[data-orders-access]");
  const deniedPanel = document.querySelector("[data-orders-denied]");
  const tabs = document.querySelector("[data-shop-tabs]");
  const list = document.querySelector("[data-orders-list]");
  const message = document.querySelector("[data-orders-message]");
  const statusFilter = document.querySelector("[data-orders-status]");
  const searchFilter = document.querySelector("[data-orders-search]");
  const deletedFilter = document.querySelector("[data-orders-deleted]");
  const refreshButton = document.querySelector("[data-orders-refresh]");
  const newOrderAlert = document.querySelector("[data-new-order-alert]");
  const newOrderAlertText = document.querySelector(
    "[data-new-order-alert-text]"
  );
  const toast = document.querySelector("[data-order-toast]");
  const soundToggle = document.querySelector("[data-order-sound-toggle]");
  const soundStatus = document.querySelector("[data-order-sound-status]");
  let toastTimer = null;

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function setMessage(text, type) {
    message.textContent = text || "";
    message.className = "admin-message";
    if (type) message.classList.add(`is-${type}`);
  }

  function isContentAdmin() {
    return state.profile && ["owner", "admin"].includes(state.profile.role);
  }

  function permissionFor(shopKey) {
    if (isContentAdmin()) {
      return { can_view_orders: true, can_update_orders: true, can_delete_orders: true };
    }
    return state.permissions.get(shopKey) || {
      can_view_orders: false,
      can_update_orders: false,
      can_delete_orders: false
    };
  }

  function formatDateTime(value) {
    if (!value) return "未提供";
    return new Intl.DateTimeFormat("zh-TW", {
      timeZone: "Asia/Taipei",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date(value));
  }

  function formatAmount(value) {
    if (value == null || Number.isNaN(Number(value))) return "部分品項無法計價";
    return `${Number(value).toLocaleString("en-US")} Gil`;
  }

  function formatOptionAmount(option) {
    if (option?.price_delta_text) return option.price_delta_text;
    const amount = Number(option?.price_delta_amount || 0);
    return `${amount >= 0 ? "+" : ""}${amount.toLocaleString("en-US")} Gil`;
  }

  function unreadTotal() {
    return [...state.unreadByShop.values()].reduce(
      (total, count) => total + count,
      0
    );
  }

  function updateDocumentTitle() {
    const total = unreadTotal();
    document.title = total ? `(${total}) ${BASE_TITLE}` : BASE_TITLE;
    updateFaviconBadge(total);
  }

  function updateFaviconBadge(count) {
    if (!favicon) return;
    if (!count) {
      favicon.href = BASE_FAVICON;
      return;
    }
    const canvas = document.createElement("canvas");
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext("2d");
    if (!context) return;

    context.fillStyle = "#7f1d1d";
    context.fillRect(2, 2, 60, 60);
    context.fillStyle = "#fffaf5";
    context.fillRect(15, 14, 34, 38);
    context.strokeStyle = "#7f1d1d";
    context.lineWidth = 4;
    context.lineCap = "round";
    [[22, 22, 42, 22], [22, 31, 42, 31], [22, 40, 35, 40]].forEach(
      ([x1, y1, x2, y2]) => {
        context.beginPath();
        context.moveTo(x1, y1);
        context.lineTo(x2, y2);
        context.stroke();
      }
    );

    const badgeText = count > 99 ? "99+" : String(count);
    const badgeRadius = count > 9 ? 18 : 15;
    const badgeX = 49;
    const badgeY = 15;
    context.fillStyle = "#dc2626";
    context.beginPath();
    context.arc(badgeX, badgeY, badgeRadius, 0, Math.PI * 2);
    context.fill();
    context.strokeStyle = "#ffffff";
    context.lineWidth = 3;
    context.stroke();
    context.fillStyle = "#ffffff";
    context.font = `700 ${count > 99 ? 15 : count > 9 ? 18 : 22}px sans-serif`;
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(badgeText, badgeX, badgeY + 1);
    favicon.href = canvas.toDataURL("image/png");
  }

  function showToast(text) {
    toast.textContent = text;
    toast.hidden = false;
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => {
      toast.hidden = true;
    }, 3500);
  }

  function updateNewOrderAlert() {
    const count = state.unreadByShop.get(state.shopKey) || 0;
    newOrderAlert.hidden = count === 0;
    if (count) {
      newOrderAlertText.textContent =
        `有 ${count} 筆${SHOPS[state.shopKey]}新訂單，點擊重新載入。`;
    }
    updateDocumentTitle();
  }

  function clearUnread(shopKey) {
    state.unreadByShop.set(shopKey, 0);
    renderTabs();
    updateNewOrderAlert();
  }

  function loadSoundPreference() {
    try {
      state.soundEnabled =
        window.localStorage.getItem(SOUND_STORAGE_KEY) === "true";
    } catch (error) {
      state.soundEnabled = false;
    }
    soundToggle.checked = state.soundEnabled;
    updateSoundStatus();
  }

  function updateSoundStatus(text = "") {
    soundStatus.className = "admin-sound-status";
    if (!state.soundEnabled) {
      soundStatus.textContent = "提示音已關閉";
      return;
    }
    if (text) {
      soundStatus.textContent = text;
      soundStatus.classList.add("is-blocked");
      return;
    }
    soundStatus.textContent = state.audioUnlocked
      ? "提示音已啟用"
      : "請重新啟用提示音";
    soundStatus.classList.add(
      state.audioUnlocked ? "is-ready" : "is-blocked"
    );
  }

  async function ensureAudioReady() {
    try {
      const AudioContextClass =
        window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) {
        updateSoundStatus("此瀏覽器不支援提示音");
        return false;
      }
      state.audioContext ||= new AudioContextClass();
      if (state.audioContext.state === "suspended") {
        await state.audioContext.resume();
      }
      state.audioUnlocked = state.audioContext.state === "running";
      updateSoundStatus();
      return state.audioUnlocked;
    } catch (error) {
      state.audioUnlocked = false;
      updateSoundStatus("瀏覽器尚未允許播放提示音");
      console.warn("點餐提示音解鎖失敗", error);
      return false;
    }
  }

  async function playOrderSound() {
    if (!state.soundEnabled) return;
    if (!(await ensureAudioReady())) return;
    try {
      const context = state.audioContext;
      const master = context.createGain();
      master.gain.setValueAtTime(0.65, context.currentTime);
      master.connect(context.destination);

      [
        { frequency: 740, start: 0, duration: 0.18 },
        { frequency: 1046, start: 0.2, duration: 0.28 }
      ].forEach(({ frequency, start, duration }) => {
        const oscillator = context.createOscillator();
        const gain = context.createGain();
        const startsAt = context.currentTime + start;
        oscillator.type = "triangle";
        oscillator.frequency.setValueAtTime(frequency, startsAt);
        gain.gain.setValueAtTime(0.0001, startsAt);
        gain.gain.exponentialRampToValueAtTime(0.72, startsAt + 0.018);
        gain.gain.exponentialRampToValueAtTime(
          0.0001,
          startsAt + duration
        );
        oscillator.connect(gain);
        gain.connect(master);
        oscillator.start(startsAt);
        oscillator.stop(startsAt + duration + 0.02);
      });
    } catch (error) {
      console.warn("點餐提示音播放失敗", error);
    }
  }

  function renderTabs() {
    tabs.innerHTML = state.shops.map((shopKey) => `
      <button
        class="admin-tab${shopKey === state.shopKey ? " is-active" : ""}"
        type="button"
        data-shop-key="${escapeHtml(shopKey)}"
      >${escapeHtml(SHOPS[shopKey])}${
        state.unreadByShop.get(shopKey)
          ? `<span class="admin-tab-badge">${escapeHtml(
              state.unreadByShop.get(shopKey)
            )}</span>`
          : ""
      }</button>
    `).join("");
  }

  function formatStaffSnapshot(item) {
    const staffName = String(
      item.selected_staff_name_snapshot || ""
    ).trim();
    const staffDetail = String(
      item.selected_staff_special_label_snapshot || ""
    ).trim();
    if (!staffName) return staffDetail;
    if (!staffDetail || staffDetail === staffName) return staffName;
    return `${staffName}｜${staffDetail}`;
  }

  function detail(label, value, full = false) {
    return `
      <div class="reservation-detail${full ? " reservation-detail-full" : ""}">
        <dt>${escapeHtml(label)}</dt>
        <dd>${escapeHtml(value || "未填寫")}</dd>
      </div>
    `;
  }

  function renderDiscordMeta(order) {
    const parts = [
      `推送 ${Number(order.discord_attempts || 0)} 次`,
      order.discord_notified_at
        ? `最後通知 ${formatDateTime(order.discord_notified_at)}`
        : ""
    ].filter(Boolean);
    return `
      <div class="reservation-discord-meta">
        <span>${escapeHtml(parts.join("・"))}</span>
        ${
          order.discord_last_error
            ? `<details class="admin-discord-error"><summary>查看 Discord 錯誤</summary><p>${escapeHtml(order.discord_last_error)}</p></details>`
            : ""
        }
      </div>
    `;
  }

  function renderItems(items) {
    if (!Array.isArray(items) || !items.length) return "<p>沒有品項資料。</p>";
    return `
      <ul class="admin-order-items">
        ${items.map((item) => {
          const options = Array.isArray(item.selected_options_snapshot)
            ? item.selected_options_snapshot
            : [];
          const staffLabel = formatStaffSnapshot(item);
          return `
          <li>
            <div class="admin-order-item-title">
              <strong>${escapeHtml(item.item_name_snapshot)} × ${escapeHtml(item.quantity)}</strong>
              <span>${escapeHtml(
                item.line_total_amount_snapshot != null
                  ? formatAmount(item.line_total_amount_snapshot)
                  : item.price_snapshot || "未計價"
              )}</span>
            </div>
            ${staffLabel ? `<p class="admin-order-item-detail">指定：${escapeHtml(staffLabel)}</p>` : ""}
            ${options.length ? `
              <p class="admin-order-item-detail">加購：${options.map((option) =>
                escapeHtml(
                  `${option.label || "未命名選項"} ${formatOptionAmount(option)}`
                )
              ).join("、")}</p>
            ` : ""}
            ${item.item_note ? `<p class="admin-order-item-detail">品項備註：${escapeHtml(item.item_note)}</p>` : ""}
          </li>
        `;
        }).join("")}
      </ul>
    `;
  }

  function renderOrders() {
    const settings = state.shopSettings || {};
    const contactVisible = settings.order_contact_visible !== false;
    const noteVisible = settings.order_note_visible !== false;
    const timeVisible = settings.order_time_visible !== false;
    const timeLabel = settings.order_time_label || "用餐／出餐時間";
    const query = searchFilter.value.trim().toLowerCase();
    const status = statusFilter.value;
    const showDeleted = deletedFilter.checked;
    const orders = state.orders.filter((order) => {
      if (!showDeleted && order.deleted_at) return false;
      if (status && order.status !== status) return false;
      if (!query) return true;
      const targets = contactVisible
        ? [order.customer_name, order.contact]
        : [order.customer_name];
      return targets.some((value) =>
        String(value || "").toLowerCase().includes(query)
      );
    });

    if (!orders.length) {
      list.innerHTML = '<p class="admin-empty">目前沒有符合條件的訂單。</p>';
      return;
    }

    const permission = permissionFor(state.shopKey);
    list.innerHTML = orders.map((order) => {
      const canUpdate = permission.can_update_orders && !order.deleted_at;
      const canDelete = permission.can_delete_orders && !order.deleted_at;
      const canResendDiscord = isContentAdmin() && !order.deleted_at;
      const discordBadgeClass =
        order.discord_status === "sent"
          ? "status-badge-visible"
          : order.discord_status === "failed"
            ? "status-badge-hidden"
            : "status-badge-featured";
      return `
        <article class="admin-order-card reservation-admin-card${order.deleted_at ? " is-deleted" : ""}" data-order-id="${escapeHtml(order.id)}">
          <header class="admin-order-card-header reservation-admin-card-header">
            <div>
              <p class="reservation-card-date">${escapeHtml(order.business_date || "未填寫")}・${escapeHtml(order.requested_time || "未指定")}</p>
              <h3>${escapeHtml(order.customer_name)}</h3>
            </div>
            <div class="reservation-card-badges">
              <span class="status-badge reservation-status reservation-status-${escapeHtml(order.status)}">${escapeHtml(STATUS_LABELS[order.status] || order.status)}</span>
              <span class="status-badge ${discordBadgeClass}">Discord ${escapeHtml(DISCORD_STATUS_LABELS[order.discord_status] || order.discord_status || "待推送")}</span>
              ${order.deleted_at ? '<span class="status-badge status-badge-hidden">已刪除</span>' : ""}
            </div>
          </header>
          <dl class="reservation-details admin-order-details">
            ${detail("店別", SHOPS[order.shop_key])}
            ${contactVisible ? detail("聯絡方式", order.contact) : ""}
            ${timeVisible ? detail(timeLabel, order.requested_time) : ""}
            ${detail("總金額", formatAmount(order.total_amount_snapshot))}
            ${noteVisible && order.note ? detail("客人備註", order.note, true) : ""}
            ${order.deleted_at ? detail("刪除資訊", `${formatDateTime(order.deleted_at)}・${order.delete_reason || "未填寫"}`, true) : ""}
          </dl>
          <section class="admin-order-content">
            <h4>出餐內容</h4>
            ${renderItems(order.order_items)}
          </section>
          ${renderDiscordMeta(order)}
          <div class="admin-order-edit">
            <label class="admin-field">
              <span>訂單狀態</span>
              <select data-order-status ${canUpdate ? "" : "disabled"}>
                ${Object.entries(STATUS_LABELS).map(([value, label]) =>
                  `<option value="${escapeHtml(value)}"${order.status === value ? " selected" : ""}>${escapeHtml(label)}</option>`
                ).join("")}
              </select>
            </label>
            <label class="admin-field admin-order-note">
              <span>管理備註</span>
              <textarea rows="3" data-order-admin-note ${canUpdate ? "" : "disabled"}>${escapeHtml(order.admin_note || "")}</textarea>
            </label>
          </div>
          <div class="admin-card-actions">
            ${canUpdate ? '<button class="admin-button" type="button" data-order-save>儲存變更</button>' : ""}
            ${canResendDiscord ? '<button class="admin-button admin-button-secondary" type="button" data-order-discord-resend>重新推送 Discord</button>' : ""}
            ${canDelete ? '<button class="admin-button admin-button-danger" type="button" data-order-delete>刪除</button>' : ""}
          </div>
          ${order.deleted_at ? `<p class="admin-deleted-note">刪除時間：${escapeHtml(formatDateTime(order.deleted_at))}｜原因：${escapeHtml(order.delete_reason || "未填寫")}</p>` : ""}
        </article>
      `;
    }).join("");
  }

  function registerNewOrder(order) {
    const shopKey = order?.shop_key;
    const orderId = order?.id;
    if (
      !shopKey ||
      !orderId ||
      !state.shops.includes(shopKey) ||
      state.knownOrderIds.has(orderId)
    ) {
      return;
    }
    state.knownOrderIds.add(orderId);
    state.unreadByShop.set(
      shopKey,
      (state.unreadByShop.get(shopKey) || 0) + 1
    );
    renderTabs();
    updateNewOrderAlert();
    showToast(`已收到${SHOPS[shopKey]}新訂單。`);
    playOrderSound();
  }

  async function loadOrders({ clearCurrentUnread = false } = {}) {
    if (!state.shopKey) return;
    setMessage("正在載入訂單…");
    const [ordersResult, settingsResult] = await Promise.all([
      state.client
        .from("orders")
        .select(`
          id, shop_key, customer_name, contact, note, status, admin_note,
          requested_time, business_date, total_amount_snapshot,
          discord_status, discord_attempts, discord_last_error,
          discord_notified_at,
          deleted_at, deleted_by, delete_reason, created_at,
          order_items (
            id, item_name_snapshot, price_snapshot, price_amount_snapshot, quantity,
            item_note, selected_staff_name_snapshot, selected_staff_special_label_snapshot,
            selected_options_snapshot, options_amount_snapshot,
            line_total_amount_snapshot,
            sort_order
          )
        `)
        .eq("shop_key", state.shopKey)
        .order("created_at", { ascending: false }),
      state.client
        .from("menus")
        .select(
          "order_customer_label, order_contact_visible, order_note_visible, order_time_visible, order_time_label"
        )
        .eq("key", state.shopKey)
        .maybeSingle()
    ]);
    const { data, error } = ordersResult;

    if (error || settingsResult.error) {
      const loadError = error || settingsResult.error;
      console.error("訂單載入失敗", loadError);
      setMessage(`訂單載入失敗：${loadError.message}`, "error");
      state.orders = [];
      state.shopSettings = null;
      renderOrders();
      return;
    }

    state.shopSettings = settingsResult.data || {};
    searchFilter.placeholder =
      state.shopSettings.order_contact_visible === false
        ? "角色 ID"
        : "角色 ID 或聯絡方式";
    state.orders = (data || []).map((order) => ({
      ...order,
      order_items: (order.order_items || []).sort((a, b) =>
        (a.sort_order || 0) - (b.sort_order || 0)
      )
    }));
    state.dirtyOrderIds.clear();
    state.orders.forEach((order) => state.knownOrderIds.add(order.id));
    if (clearCurrentUnread) {
      clearUnread(state.shopKey);
    }
    setMessage("");
    renderOrders();
  }

  async function seedKnownOrders() {
    const { data, error } = await state.client
      .from("orders")
      .select("id, shop_key, created_at")
      .in("shop_key", state.shops)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) throw error;
    (data || []).forEach((order) => state.knownOrderIds.add(order.id));
  }

  async function pollForNewOrders() {
    if (state.destroyed || !state.shops.length) return;
    const { data, error } = await state.client
      .from("orders")
      .select("id, shop_key, created_at")
      .in("shop_key", state.shops)
      .order("created_at", { ascending: false })
      .limit(50);
    if (error) {
      console.warn("新訂單輪詢失敗", error);
      return;
    }
    [...(data || [])].reverse().forEach(registerNewOrder);
  }

  function startPolling() {
    if (state.pollTimer || state.destroyed) return;
    state.pollTimer = window.setInterval(
      pollForNewOrders,
      POLL_INTERVAL_MS
    );
  }

  function stopPolling() {
    if (!state.pollTimer) return;
    window.clearInterval(state.pollTimer);
    state.pollTimer = null;
  }

  function subscribeToNewOrders() {
    if (!state.client?.channel || state.realtimeChannel) {
      startPolling();
      return;
    }
    try {
      startPolling();
      state.realtimeChannel = state.client
        .channel(`admin-orders-${state.session.user.id}`)
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "orders"
          },
          (payload) => {
            const order = payload?.new;
            if (!state.shops.includes(order?.shop_key)) return;
            registerNewOrder(order);
          }
        )
        .subscribe((status) => {
          if (status === "SUBSCRIBED") {
            // Keep the 30-second safety poll. A channel can subscribe even
            // when the table is not included in the Realtime publication.
            startPolling();
          } else if (
            ["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"].includes(status) &&
            !state.destroyed
          ) {
            startPolling();
          }
        });
    } catch (error) {
      console.warn("Realtime 訂閱失敗，改用輪詢", error);
      state.realtimeChannel = null;
      startPolling();
    }
  }

  async function cleanupMonitoring() {
    state.destroyed = true;
    stopPolling();
    if (state.realtimeChannel && state.client?.removeChannel) {
      try {
        await state.client.removeChannel(state.realtimeChannel);
      } catch (error) {
        console.warn("Realtime 頻道移除失敗", error);
      }
    }
    state.realtimeChannel = null;
  }

  async function saveOrder(card) {
    const id = card.dataset.orderId;
    const status = card.querySelector("[data-order-status]").value;
    const adminNote = card.querySelector("[data-order-admin-note]").value.trim();
    setMessage("正在儲存訂單…");
    const { error } = await state.client
      .from("orders")
      .update({ status, admin_note: adminNote || null })
      .eq("id", id);

    if (error) {
      console.error("訂單更新失敗", error);
      setMessage(`訂單更新失敗：${error.message}`, "error");
      return;
    }
    setMessage("訂單已更新。", "success");
    state.dirtyOrderIds.delete(id);
    await loadOrders();
  }

  async function softDeleteOrder(card) {
    const id = card.dataset.orderId;
    const order = state.orders.find((entry) => entry.id === id);
    if (!order) return;
    const confirmed = window.confirm(`確定要刪除「${order.customer_name}」的訂單嗎？`);
    if (!confirmed) return;
    const reason = window.prompt("刪除原因（可留空）", "") || "";
    setMessage("正在刪除訂單…");
    const { error } = await state.client
      .from("orders")
      .update({
        deleted_at: new Date().toISOString(),
        deleted_by: state.session.user.id,
        delete_reason: reason.trim() || null
      })
      .eq("id", id);

    if (error) {
      console.error("訂單刪除失敗", error);
      setMessage(`訂單刪除失敗：${error.message}`, "error");
      return;
    }
    setMessage("訂單已刪除。", "success");
    await loadOrders();
  }

  async function resendDiscord(card) {
    if (!isContentAdmin()) {
      setMessage("只有 owner 或 admin 可以重新推送 Discord。", "error");
      return;
    }
    const id = card.dataset.orderId;
    const order = state.orders.find((entry) => entry.id === id);
    if (!order || order.deleted_at) return;
    if (
      !window.confirm(
        `確定要重新推送「${order.customer_name}」的 Discord 出餐通知嗎？`
      )
    ) {
      return;
    }

    setMessage("正在重新推送 Discord…");
    try {
      const { data: sessionData } = await state.client.auth.getSession();
      const accessToken = sessionData?.session?.access_token;
      const { data, error } = await state.client.functions.invoke(
        "notify-order-discord",
        {
          headers: accessToken
            ? { Authorization: `Bearer ${accessToken}` }
            : undefined,
          body: {
            order_id: order.id,
            force: true
          }
        }
      );
      if (error) {
        let functionMessage = "";
        try {
          const payload = await error.context?.json();
          functionMessage = payload?.error || payload?.message || "";
        } catch {
          functionMessage = "";
        }
        throw new Error(
          functionMessage || error.message || "Discord 推播失敗。"
        );
      }
      if (data?.error || data?.status === "failed") {
        throw new Error(data?.error || "Discord 推播失敗。");
      }
      setMessage("Discord 已重新推送。", "success");
      await loadOrders();
    } catch (error) {
      console.error("Discord 訂單重新推送失敗", error);
      setMessage(
        `Discord 重新推送失敗：${error.message || "請稍後再試。"}`,
        "error"
      );
      await loadOrders();
    }
  }

  async function loadPermissions() {
    if (isContentAdmin()) {
      state.shops = Object.keys(SHOPS);
      return;
    }
    const { data, error } = await state.client
      .from("admin_shop_permissions")
      .select("shop_key, can_view_orders, can_update_orders, can_delete_orders")
      .eq("user_id", state.session.user.id);

    if (error) throw error;
    (data || []).forEach((permission) => state.permissions.set(permission.shop_key, permission));
    state.shops = Object.keys(SHOPS).filter((shopKey) =>
      permissionFor(shopKey).can_view_orders
    );
  }

  tabs.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-shop-key]");
    if (!button) return;
    state.shopKey = button.dataset.shopKey;
    renderTabs();
    await loadOrders({ clearCurrentUnread: true });
    updateNewOrderAlert();
  });
  list.addEventListener("click", async (event) => {
    const card = event.target.closest("[data-order-id]");
    if (!card) return;
    if (event.target.closest("[data-order-save]")) await saveOrder(card);
    if (event.target.closest("[data-order-discord-resend]")) {
      await resendDiscord(card);
    }
    if (event.target.closest("[data-order-delete]")) await softDeleteOrder(card);
  });
  list.addEventListener("input", (event) => {
    const card = event.target.closest("[data-order-id]");
    if (
      card &&
      (
        event.target.matches("[data-order-admin-note]") ||
        event.target.matches("[data-order-status]")
      )
    ) {
      state.dirtyOrderIds.add(card.dataset.orderId);
    }
  });
  list.addEventListener("change", (event) => {
    const card = event.target.closest("[data-order-id]");
    if (card && event.target.matches("[data-order-status]")) {
      state.dirtyOrderIds.add(card.dataset.orderId);
    }
  });
  [statusFilter, searchFilter, deletedFilter].forEach((element) =>
    element.addEventListener(element === searchFilter ? "input" : "change", renderOrders)
  );
  refreshButton.addEventListener("click", async () => {
    if (
      state.dirtyOrderIds.size &&
      !window.confirm("尚有未儲存的訂單變更，仍要重新整理嗎？")
    ) {
      return;
    }
    await loadOrders({ clearCurrentUnread: true });
  });
  newOrderAlert.addEventListener("click", async () => {
    if (
      state.dirtyOrderIds.size &&
      !window.confirm("尚有未儲存的訂單變更，仍要載入新訂單嗎？")
    ) {
      return;
    }
    await loadOrders({ clearCurrentUnread: true });
  });
  soundToggle.addEventListener("change", async () => {
    state.soundEnabled = soundToggle.checked;
    try {
      window.localStorage.setItem(
        SOUND_STORAGE_KEY,
        String(state.soundEnabled)
      );
    } catch (error) {
      console.warn("提示音設定無法保存", error);
    }
    if (state.soundEnabled) {
      await ensureAudioReady();
      await playOrderSound();
    } else {
      updateSoundStatus();
    }
  });
  document.addEventListener(
    "pointerdown",
    () => {
      if (state.soundEnabled && !state.audioUnlocked) {
        ensureAudioReady();
      }
    },
    { passive: true }
  );
  window.addEventListener("pagehide", cleanupMonitoring, { once: true });

  window.addEventListener("admin-auth-ready", async (event) => {
    state.client = event.detail.client;
    state.session = event.detail.session;
    state.profile = event.detail.profile;
    try {
      await loadPermissions();
      if (!state.shops.length) {
        deniedPanel.hidden = false;
        return;
      }
      state.shopKey = state.shops[0];
      accessPanel.hidden = false;
      loadSoundPreference();
      renderTabs();
      await loadOrders();
      try {
        await seedKnownOrders();
      } catch (monitorError) {
        console.warn("新訂單監控基準載入失敗", monitorError);
      }
      subscribeToNewOrders();
    } catch (error) {
      console.error("點餐權限載入失敗", error);
      deniedPanel.hidden = false;
      deniedPanel.querySelector("p").textContent = `權限讀取失敗：${error.message}`;
    }
  }, { once: true });
})();
