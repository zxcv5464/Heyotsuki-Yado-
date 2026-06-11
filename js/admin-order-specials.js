(function () {
  "use strict";

  const SHOPS = { menu: "湯宿", menu2: "喫茶" };
  const state = {
    client: null,
    shopKey: "menu",
    itemId: "",
    staff: [],
    items: [],
    options: []
  };

  const accessPanel = document.querySelector("[data-specials-access]");
  const deniedPanel = document.querySelector("[data-specials-denied]");
  const tabs = document.querySelector("[data-special-shop-tabs]");
  const itemSelect = document.querySelector("[data-special-item-select]");
  const list = document.querySelector("[data-specials-list]");
  const message = document.querySelector("[data-specials-message]");

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

  function renderTabs() {
    tabs.innerHTML = Object.entries(SHOPS).map(([key, label]) => `
      <button class="admin-tab${key === state.shopKey ? " is-active" : ""}" type="button" data-shop-key="${key}">
        ${escapeHtml(label)}
      </button>
    `).join("");
  }

  function renderItemSelect() {
    const ordered = [...state.items].sort((a, b) => {
      if (a.requires_staff_selection !== b.requires_staff_selection) {
        return a.requires_staff_selection ? -1 : 1;
      }
      return (a.sort_order || 0) - (b.sort_order || 0);
    });
    itemSelect.innerHTML = ordered.map((item) => `
      <option value="${escapeHtml(item.id)}"${item.id === state.itemId ? " selected" : ""}>
        ${escapeHtml(item.name)}${item.requires_staff_selection ? "（需要選員工）" : ""}
      </option>
    `).join("");
    if (!state.itemId || !ordered.some((item) => item.id === state.itemId)) {
      state.itemId = ordered[0]?.id || "";
      itemSelect.value = state.itemId;
    }
  }

  function renderList() {
    if (!state.itemId) {
      list.innerHTML = '<p class="admin-empty">此店目前沒有可設定的點餐品項。</p>';
      return;
    }
    const byStaff = new Map(
      state.options
        .filter((option) => option.menu_item_id === state.itemId)
        .map((option) => [option.staff_id, option])
    );
    list.innerHTML = state.staff.map((staff) => {
      const option = byStaff.get(staff.id);
      const enabled = Boolean(option && option.is_visible);
      return `
        <article class="admin-special-card${enabled ? " is-enabled" : ""}" data-staff-id="${escapeHtml(staff.id)}">
          <div class="admin-special-heading">
            <div>
              <h3>${escapeHtml(staff.name)}</h3>
              <p>${escapeHtml(staff.subtitle || "未填寫副標題")}${staff.is_visible ? "" : "｜員工目前已隱藏"}</p>
            </div>
            <span class="admin-status-badge ${enabled ? "status-sent" : "status-deleted"}">${enabled ? "此品項可選" : "未開放"}</span>
          </div>
          <div class="admin-form-grid">
            <label class="admin-checkbox">
              <input type="checkbox" data-option-visible ${enabled ? "checked" : ""}>
              <span>此品項可選擇此員工</span>
            </label>
            <label class="admin-field">
              <span>員工顯示名稱</span>
              <input type="text" data-option-display-name value="${escapeHtml(option?.display_name || "")}" placeholder="${escapeHtml(staff.name)}">
            </label>
            <label class="admin-field">
              <span>公開內容／服務名稱</span>
              <input type="text" data-option-label value="${escapeHtml(option?.option_label || "")}" placeholder="例如：墨魚麵（可留空）">
            </label>
            <label class="admin-field">
              <span>排序</span>
              <input type="number" data-option-sort value="${escapeHtml(option?.sort_order ?? staff.sort_order ?? 0)}">
            </label>
            <label class="admin-field admin-field-full">
              <span>後台備註</span>
              <textarea rows="2" data-option-note>${escapeHtml(option?.note || "")}</textarea>
            </label>
          </div>
          <div class="admin-card-actions">
            <button class="admin-button" type="button" data-option-save>儲存</button>
          </div>
        </article>
      `;
    }).join("");
  }

  async function loadShopItems() {
    setMessage("正在載入品項…");
    const { data: sections, error: sectionError } = await state.client
      .from("menu_sections")
      .select("id")
      .eq("menu_key", state.shopKey);
    if (sectionError) throw sectionError;
    const sectionIds = (sections || []).map((section) => section.id);
    if (!sectionIds.length) {
      state.items = [];
      state.itemId = "";
      renderItemSelect();
      renderList();
      return;
    }
    const { data, error } = await state.client
      .from("menu_items")
      .select("id, name, requires_staff_selection, is_orderable, sort_order")
      .in("section_id", sectionIds)
      .eq("is_orderable", true)
      .order("sort_order", { ascending: true });
    if (error) throw error;
    state.items = data || [];
    if (!state.items.some((item) => item.id === state.itemId)) {
      state.itemId = state.items[0]?.id || "";
    }
    renderItemSelect();
  }

  async function loadData() {
    setMessage("正在載入名單…");
    try {
      const [staffResult, optionResult] = await Promise.all([
        state.client
          .from("staff_members")
          .select("id, name, subtitle, is_visible, sort_order")
          .order("sort_order", { ascending: true })
          .order("name", { ascending: true }),
        state.client
          .from("menu_item_staff_options")
          .select("id, menu_item_id, staff_id, display_name, option_label, note, is_visible, sort_order")
          .order("sort_order", { ascending: true })
      ]);
      if (staffResult.error || optionResult.error) {
        throw staffResult.error || optionResult.error;
      }
      state.staff = staffResult.data || [];
      state.options = optionResult.data || [];
      await loadShopItems();
      setMessage("");
      renderList();
    } catch (error) {
      console.error("品項員工名單載入失敗", error);
      setMessage(`載入失敗：${error.message}`, "error");
    }
  }

  async function saveOption(card) {
    const payload = {
      menu_item_id: state.itemId,
      staff_id: card.dataset.staffId,
      is_visible: card.querySelector("[data-option-visible]").checked,
      display_name: card.querySelector("[data-option-display-name]").value.trim() || null,
      option_label: card.querySelector("[data-option-label]").value.trim() || null,
      sort_order: Number(card.querySelector("[data-option-sort]").value) || 0,
      note: card.querySelector("[data-option-note]").value.trim() || null
    };
    setMessage("正在儲存設定…");
    const { error } = await state.client
      .from("menu_item_staff_options")
      .upsert(payload, { onConflict: "menu_item_id,staff_id" });
    if (error) {
      console.error("品項員工設定儲存失敗", error);
      setMessage(`儲存失敗：${error.message}`, "error");
      return;
    }
    setMessage("品項員工設定已儲存。", "success");
    await loadData();
  }

  tabs.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-shop-key]");
    if (!button) return;
    state.shopKey = button.dataset.shopKey;
    state.itemId = "";
    renderTabs();
    await loadShopItems();
    renderList();
  });
  itemSelect.addEventListener("change", () => {
    state.itemId = itemSelect.value;
    renderList();
  });
  list.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-option-save]");
    if (!button) return;
    await saveOption(button.closest("[data-staff-id]"));
  });

  window.addEventListener("admin-auth-ready", async (event) => {
    state.client = event.detail.client;
    if (!["owner", "admin"].includes(event.detail.profile.role)) {
      deniedPanel.hidden = false;
      return;
    }
    accessPanel.hidden = false;
    renderTabs();
    await loadData();
  }, { once: true });
})();
