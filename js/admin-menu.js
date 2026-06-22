(() => {
  const client = window.SUPABASE_CLIENT;
  const allowedMenuKeys = new Set(["menu", "menu2"]);

  const workspace = document.querySelector("[data-menu-workspace]");
  const denied = document.querySelector("[data-menu-denied]");
  const message = document.querySelector("[data-menu-message]");
  const menuForm = document.querySelector("[data-menu-form]");
  const sectionForm = document.querySelector("[data-section-form]");
  const itemForm = document.querySelector("[data-item-form]");
  const sectionEditor = document.querySelector("[data-section-editor]");
  const itemEditor = document.querySelector("[data-item-editor]");
  const optionEditor = document.querySelector("[data-option-editor]");
  const sectionList = document.querySelector("[data-section-list]");
  const itemList = document.querySelector("[data-item-list]");
  const newSectionButton = document.querySelector("[data-new-section]");
  const newItemButton = document.querySelector("[data-new-item]");
  const currentKeyBadge = document.querySelector("[data-current-menu-key]");
  const itemSectionLabel = document.querySelector("[data-item-section-label]");
  const itemSectionSelect = itemForm?.elements.namedItem("section_id");
  const optionForm = document.querySelector("[data-order-option-form]");
  const optionList = document.querySelector("[data-order-option-list]");
  const optionItemLabel = document.querySelector("[data-option-item-label]");
  const optionStaffFieldset = document.querySelector("[data-option-staff-fieldset]");
  const optionStaffList = document.querySelector("[data-option-staff-list]");
  const orderModeHint = document.querySelector("[data-order-mode-hint]");

  let currentMenuKey = "menu";
  let menuData = null;
  let sections = [];
  let items = [];
  let selectedSectionId = null;
  let optionItemId = null;
  let orderOptions = [];
  let optionStaffRows = [];
  let staffMembers = [];

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const PAYROLL_RULE_LABELS = {
    excluded: "不列入薪資",
    food_pool: "公池平均",
    direct_staff: "指定員工",
    dance_split: "舞蹈分配"
  };

  const setMessage = (text, type = "error") => {
    if (!message) return;
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const setBusy = (button, busy, busyText = "儲存中...") => {
    if (!button) return;
    if (!button.dataset.defaultText) {
      button.dataset.defaultText = button.textContent;
    }
    button.disabled = busy;
    button.textContent = busy ? busyText : button.dataset.defaultText;
  };

  const statusBadge = (visible) =>
    visible
      ? '<span class="status-badge status-badge-visible">顯示中</span>'
      : '<span class="status-badge status-badge-hidden">已隱藏</span>';

  const formatMinuteValue = (minute) => {
    const value = Number(minute);
    if (!Number.isFinite(value)) return "";
    if (value === 1440) return "24:00";
    const normalized = ((value % 1440) + 1440) % 1440;
    return `${String(Math.floor(normalized / 60)).padStart(2, "0")}:${String(
      normalized % 60
    ).padStart(2, "0")}`;
  };

  const parseTimeValue = (value) => {
    const match = String(value || "").trim().match(/^(\d{2}):(\d{2})$/);
    if (!match) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (hour === 24 && minute === 0) return 1440;
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  };

  const syncOrderModeHint = () => {
    const mode = menuForm.elements.order_acceptance_mode.value;
    const messages = {
      auto: "依照營業日與營業時間自動開關。",
      open: "目前會強制開放點餐。",
      closed: "目前會強制關閉點餐。"
    };
    orderModeHint.textContent = messages[mode] || messages.auto;
  };

  const fillMenuForm = () => {
    if (!menuData) return;
    menuForm.elements.title.value = menuData.title || "";
    menuForm.elements.short_title.value = menuData.short_title || "";
    menuForm.elements.english_title.value = menuData.english_title || "";
    menuForm.elements.description.value = menuData.description || "";
    menuForm.elements.href.value = menuData.href || "";
    menuForm.elements.is_visible.checked = Boolean(menuData.is_visible);
    menuForm.elements.sort_order.value = menuData.sort_order ?? "";
    menuForm.elements.order_customer_label.value =
      menuData.order_customer_label || "角色 ID";
    menuForm.elements.order_contact_visible.checked =
      menuData.order_contact_visible !== false;
    menuForm.elements.order_contact_required.checked = Boolean(
      menuData.order_contact_required
    );
    menuForm.elements.order_note_visible.checked =
      menuData.order_note_visible !== false;
    menuForm.elements.order_note_required.checked = Boolean(
      menuData.order_note_required
    );
    menuForm.elements.order_acceptance_mode.value =
      menuData.order_acceptance_mode || "auto";
    const weekdays = new Set(menuData.order_open_weekdays || [5, 6, 0]);
    document.querySelectorAll("[data-order-weekday]").forEach((checkbox) => {
      checkbox.checked = weekdays.has(Number(checkbox.value));
    });
    menuForm.elements.order_open_time.value = formatMinuteValue(
      menuData.order_open_minute ?? 1260
    );
    menuForm.elements.order_close_time.value = formatMinuteValue(
      menuData.order_close_minute ?? 1440
    );
    menuForm.elements.order_time_slot_minutes.value =
      menuData.order_time_slot_minutes ?? 30;
    menuForm.elements.order_time_label.value =
      menuData.order_time_label || "用餐時間";
    menuForm.elements.order_time_visible.checked =
      menuData.order_time_visible !== false;
    menuForm.elements.order_time_required.checked =
      menuData.order_time_required !== false;
    menuForm.elements.order_closed_message.value =
      menuData.order_closed_message || "";
    menuForm.elements.order_manual_notice.value =
      menuData.order_manual_notice || "";
    syncMenuRequirementControls();
    syncTimeFieldControls();
    syncOrderModeHint();
    currentKeyBadge.textContent = currentMenuKey;
  };

  const updateSectionOptions = () => {
    itemSectionSelect.innerHTML = sections
      .map(
        (section) =>
          `<option value="${escapeHtml(section.id)}">${escapeHtml(section.title)}${section.is_visible ? "" : "（已隱藏）"}</option>`
      )
      .join("");
  };

  const renderSections = () => {
    if (!sections.length) {
      sectionList.innerHTML = '<p class="empty-state">目前沒有分類。</p>';
      selectedSectionId = null;
      newItemButton.disabled = true;
      renderItems();
      updateSectionOptions();
      return;
    }

    if (!sections.some((section) => section.id === selectedSectionId)) {
      selectedSectionId = sections[0].id;
    }
    newItemButton.disabled = false;
    updateSectionOptions();

    sectionList.innerHTML = sections
      .map((section) => {
        const selected =
          section.id === selectedSectionId ? " is-selected" : "";
        return `
          <article class="menu-admin-row${section.is_visible ? "" : " is-hidden"}${selected}" data-section-select="${escapeHtml(section.id)}">
            <div class="menu-admin-row-main">
              <div class="menu-admin-row-title">
                <strong>${escapeHtml(section.title)}</strong>
                ${statusBadge(section.is_visible)}
              </div>
              <p>${escapeHtml(section.subtitle || "")}</p>
              <small>排序 ${escapeHtml(section.sort_order)} ・ ${escapeHtml(section.layout_type)}</small>
            </div>
            <div class="menu-admin-row-actions">
              <button class="text-button" data-edit-section="${escapeHtml(section.id)}" type="button">編輯</button>
              <button class="text-button" data-toggle-section="${escapeHtml(section.id)}" type="button">${section.is_visible ? "隱藏" : "顯示"}</button>
            </div>
          </article>`;
      })
      .join("");
  };

  const renderItems = () => {
    const section = sections.find((entry) => entry.id === selectedSectionId);
    if (!section) {
      itemSectionLabel.textContent = "請先選擇分類。";
      itemList.innerHTML =
        '<p class="empty-state">請從左側選擇一個分類。</p>';
      return;
    }

    itemSectionLabel.textContent = `目前分類：${section.title}`;
    const sectionItems = items.filter(
      (item) => item.section_id === selectedSectionId
    );
    if (!sectionItems.length) {
      itemList.innerHTML = '<p class="empty-state">此分類目前沒有品項。</p>';
      return;
    }

    itemList.innerHTML = sectionItems
      .map(
        (item) => `
          <article class="menu-admin-row${item.is_visible ? "" : " is-hidden"}">
            <div class="menu-admin-row-main">
              <div class="menu-admin-row-title">
                <strong>${escapeHtml(item.name)}</strong>
                ${item.featured ? '<span class="status-badge status-badge-featured">強調</span>' : ""}
                ${statusBadge(item.is_visible)}
                ${item.is_orderable ? '<span class="status-badge status-badge-visible">可點餐</span>' : '<span class="status-badge status-badge-hidden">不開放點餐</span>'}
                ${item.requires_staff_selection ? '<span class="status-badge status-badge-featured">需選擇人員</span>' : ""}
                <span class="status-badge status-badge-featured">薪資：${escapeHtml(PAYROLL_RULE_LABELS[item.payroll_rule] || PAYROLL_RULE_LABELS.excluded)}</span>
                ${item.order_limit_quantity == null ? "" : `<span class="status-badge ${Number(item.order_limit_quantity) === 0 ? "status-badge-hidden" : "status-badge-featured"}">本日限量 ${escapeHtml(item.order_limit_quantity)}</span>`}
                ${item.allow_item_note === false ? '<span class="status-badge status-badge-hidden">無品項備註</span>' : ""}
              </div>
              <p>${escapeHtml(item.description || "")}</p>
              <small>${escapeHtml(item.price)} ・ 排序 ${escapeHtml(item.sort_order)}</small>
            </div>
            <div class="menu-admin-row-actions">
              <button class="text-button" data-edit-item="${escapeHtml(item.id)}" type="button">編輯</button>
              <button class="text-button" data-manage-options="${escapeHtml(item.id)}" type="button">加購選項</button>
              <button class="text-button" data-toggle-item="${escapeHtml(item.id)}" type="button">${item.is_visible ? "隱藏" : "顯示"}</button>
            </div>
          </article>`
      )
      .join("");
  };

  const renderAll = () => {
    fillMenuForm();
    renderSections();
    renderItems();
    document.querySelectorAll("[data-menu-key]").forEach((button) => {
      button.classList.toggle(
        "is-active",
        button.dataset.menuKey === currentMenuKey
      );
    });
  };

  const loadCurrentMenu = async (preferredSectionId = selectedSectionId) => {
    setMessage("");
    const [menuResult, sectionResult] = await Promise.all([
      client
        .from("menus")
        .select(
          "key, title, short_title, english_title, description, href, theme, is_visible, sort_order, order_customer_label, order_contact_visible, order_contact_required, order_note_visible, order_note_required, order_acceptance_mode, order_open_weekdays, order_open_minute, order_close_minute, order_time_slot_minutes, order_time_label, order_time_visible, order_time_required, order_closed_message, order_manual_notice"
        )
        .eq("key", currentMenuKey)
        .maybeSingle(),
      client
        .from("menu_sections")
        .select(
          "id, menu_key, title, subtitle, notice, layout_type, is_visible, sort_order"
        )
        .eq("menu_key", currentMenuKey)
        .order("sort_order", { ascending: true }),
    ]);

    if (menuResult.error || sectionResult.error || !menuResult.data) {
      setMessage(
        `菜單資料讀取失敗：${
          menuResult.error?.message ||
          sectionResult.error?.message ||
          "找不到菜單資料。"
        }`
      );
      return;
    }

    menuData = menuResult.data;
    sections = sectionResult.data || [];
    const sectionIds = sections.map((section) => section.id);
    items = [];

    if (sectionIds.length) {
      const itemResult = await client
        .from("menu_items")
        .select(
          "id, section_id, name, description, price, featured, is_visible, sort_order, is_orderable, requires_staff_selection, staff_selection_label, order_limit_quantity, allow_item_note"
        )
        .in("section_id", sectionIds)
        .order("sort_order", { ascending: true });
      if (itemResult.error) {
        setMessage(`品項資料讀取失敗：${itemResult.error.message}`);
        return;
      }
      items = itemResult.data || [];
      if (items.length) {
        const ruleResult = await client
          .from("menu_item_payroll_rules")
          .select("menu_item_id, payroll_rule")
          .in("menu_item_id", items.map((item) => item.id));
        if (ruleResult.error) {
          items = items.map((item) => ({ ...item, payroll_rule: "excluded" }));
        } else {
          const rules = new Map(
            (ruleResult.data || []).map((row) => [
              row.menu_item_id,
              row.payroll_rule
            ])
          );
          items = items.map((item) => ({
            ...item,
            payroll_rule: rules.get(item.id) || "excluded"
          }));
        }
      }
    }

    selectedSectionId = sections.some(
      (section) => section.id === preferredSectionId
    )
      ? preferredSectionId
      : sections[0]?.id || null;
    renderAll();
  };

  const closeSectionEditor = () => {
    sectionForm.reset();
    sectionForm.elements.id.value = "";
    sectionForm.elements.is_visible.checked = true;
    sectionEditor.hidden = true;
  };

  const openSectionEditor = (section = null) => {
    closeSectionEditor();
    document.querySelector("#section-form-title").textContent = section
      ? "編輯分類"
      : "新增分類";
    if (section) {
      sectionForm.elements.id.value = section.id;
      sectionForm.elements.title.value = section.title || "";
      sectionForm.elements.subtitle.value = section.subtitle || "";
      sectionForm.elements.notice.value = section.notice || "";
      sectionForm.elements.layout_type.value =
        section.layout_type || "detailed";
      sectionForm.elements.is_visible.checked = Boolean(section.is_visible);
      sectionForm.elements.sort_order.value = section.sort_order ?? "";
    }
    sectionEditor.hidden = false;
    sectionEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const closeItemEditor = () => {
    itemForm.reset();
    itemForm.elements.id.value = "";
    itemForm.elements.is_visible.checked = true;
    itemForm.elements.is_orderable.checked = true;
    itemForm.elements.allow_item_note.checked = true;
    itemForm.elements.requires_staff_selection.checked = false;
    itemForm.elements.order_limit_quantity.value = "";
    itemForm.elements.staff_selection_label.value =
      "請選擇湯娘的獨門料理";
    if (itemForm.elements.payroll_rule) {
      itemForm.elements.payroll_rule.value = "excluded";
    }
    itemEditor.hidden = true;
  };

  const formatOptionPrice = (option) =>
    option.price_delta_text ||
    `${Number(option.price_delta_amount) >= 0 ? "+" : ""}${Number(
      option.price_delta_amount || 0
    ).toLocaleString("en-US")} Gil`;

  const resetOptionForm = () => {
    optionForm.reset();
    optionForm.elements.id.value = "";
    optionForm.elements.price_delta_amount.value = "0";
    optionForm.elements.is_visible.checked = true;
    optionForm.elements.requires_staff_capability.checked = false;
    syncOptionStaffFieldset();
    renderOptionStaff([]);
  };

  const renderOptionStaff = (selectedIds) => {
    const selected = new Set(selectedIds || []);
    optionStaffList.innerHTML = staffMembers.map((staff) => `
      <label class="checkbox-field">
        <input type="checkbox" value="${escapeHtml(staff.id)}" data-option-staff-id${selected.has(staff.id) ? " checked" : ""}>
        <span>${escapeHtml(staff.name)}${staff.is_visible ? "" : "（員工已隱藏）"}</span>
      </label>
    `).join("");
  };

  const syncOptionStaffFieldset = () => {
    optionStaffFieldset.hidden =
      !optionForm.elements.requires_staff_capability.checked;
  };

  const renderOrderOptions = () => {
    if (!orderOptions.length) {
      optionList.innerHTML = '<p class="empty-state">此品項尚無加購選項。</p>';
      return;
    }
    optionList.innerHTML = orderOptions.map((option) => `
      <article class="menu-admin-row${option.is_visible ? "" : " is-hidden"}">
        <div class="menu-admin-row-main">
          <div class="menu-admin-row-title">
            <strong>${escapeHtml(option.label)}</strong>
            ${statusBadge(option.is_visible)}
            ${option.requires_staff_capability ? '<span class="status-badge status-badge-featured">限定員工</span>' : ""}
          </div>
          <p>${escapeHtml(option.description || "")}</p>
          <small>${escapeHtml(formatOptionPrice(option))} ・ 排序 ${escapeHtml(option.sort_order)}</small>
        </div>
        <div class="menu-admin-row-actions">
          <button class="text-button" data-edit-order-option="${escapeHtml(option.id)}" type="button">編輯</button>
          <button class="text-button" data-toggle-order-option="${escapeHtml(option.id)}" type="button">${option.is_visible ? "隱藏" : "顯示"}</button>
        </div>
      </article>
    `).join("");
  };

  const loadOrderOptions = async () => {
    const [
      optionsResult,
      staffResult,
      itemStaffResult,
      capabilityResult
    ] = await Promise.all([
      client
        .from("menu_item_order_options")
        .select("id, menu_item_id, label, description, price_delta_amount, price_delta_text, requires_staff_capability, is_visible, sort_order")
        .eq("menu_item_id", optionItemId)
        .order("sort_order", { ascending: true }),
      client
        .from("staff_members")
        .select("id, name, is_visible, sort_order")
        .order("sort_order", { ascending: true }),
      client
        .from("menu_item_staff_options")
        .select("staff_id")
        .eq("menu_item_id", optionItemId)
        .eq("is_visible", true),
      client
        .from("menu_item_order_option_staff")
        .select("id, option_id, staff_id, is_visible, sort_order")
    ]);
    const error =
      optionsResult.error ||
      staffResult.error ||
      itemStaffResult.error ||
      capabilityResult.error;
    if (error) throw error;
    orderOptions = optionsResult.data || [];
    const itemStaffIds = new Set(
      (itemStaffResult.data || []).map((row) => row.staff_id)
    );
    staffMembers = (staffResult.data || []).filter((staff) =>
      itemStaffIds.has(staff.id)
    );
    optionStaffRows = capabilityResult.data || [];
    if (!optionForm.elements.id.value) renderOptionStaff([]);
    renderOrderOptions();
  };

  const openOptionManager = async (itemId) => {
    const item = items.find((entry) => entry.id === itemId);
    if (!item) return;
    optionItemId = itemId;
    optionItemLabel.textContent = `目前品項：${item.name}`;
    resetOptionForm();
    optionEditor.hidden = false;
    try {
      await loadOrderOptions();
      optionEditor.scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (error) {
      setMessage(`加購選項讀取失敗：${error.message}`);
    }
  };

  const editOrderOption = (option) => {
    optionForm.elements.id.value = option.id;
    optionForm.elements.label.value = option.label || "";
    optionForm.elements.description.value = option.description || "";
    optionForm.elements.price_delta_amount.value =
      option.price_delta_amount ?? 0;
    optionForm.elements.price_delta_text.value =
      option.price_delta_text || "";
    optionForm.elements.requires_staff_capability.checked = Boolean(
      option.requires_staff_capability
    );
    optionForm.elements.is_visible.checked = Boolean(option.is_visible);
    optionForm.elements.sort_order.value = option.sort_order ?? 0;
    syncOptionStaffFieldset();
    renderOptionStaff(
      optionStaffRows
        .filter((row) => row.option_id === option.id && row.is_visible)
        .map((row) => row.staff_id)
    );
  };

  const saveOrderOption = async (event) => {
    event.preventDefault();
    const button = optionForm.querySelector('button[type="submit"]');
    setBusy(button, true);
    const id = optionForm.elements.id.value;
    const payload = {
      menu_item_id: optionItemId,
      label: optionForm.elements.label.value.trim(),
      description: optionForm.elements.description.value.trim() || null,
      price_delta_amount:
        Number(optionForm.elements.price_delta_amount.value) || 0,
      price_delta_text:
        optionForm.elements.price_delta_text.value.trim() || null,
      requires_staff_capability:
        optionForm.elements.requires_staff_capability.checked,
      is_visible: optionForm.elements.is_visible.checked,
      sort_order: Number(optionForm.elements.sort_order.value) || 0
    };
    let optionId = id;
    const result = id
      ? await client
          .from("menu_item_order_options")
          .update(payload)
          .eq("id", id)
          .select("id")
          .single()
      : await client
          .from("menu_item_order_options")
          .insert(payload)
          .select("id")
          .single();
    if (result.error) {
      setBusy(button, false);
      setMessage(`加購選項儲存失敗：${result.error.message}`);
      return;
    }
    optionId = result.data.id;
    if (payload.requires_staff_capability) {
      const selectedIds = [
        ...optionStaffList.querySelectorAll("[data-option-staff-id]:checked")
      ].map((input) => input.value);
      const allRows = staffMembers.map((staff, index) => ({
        option_id: optionId,
        staff_id: staff.id,
        is_visible: selectedIds.includes(staff.id),
        sort_order: index * 10
      }));
      if (allRows.length) {
        const { error } = await client
          .from("menu_item_order_option_staff")
          .upsert(allRows, { onConflict: "option_id,staff_id" });
        if (error) {
          setBusy(button, false);
          setMessage(`加購員工能力儲存失敗：${error.message}`);
          return;
        }
      }
    }
    setBusy(button, false);
    setMessage("加購選項已儲存。", "success");
    resetOptionForm();
    await loadOrderOptions();
  };

  const toggleOrderOption = async (option) => {
    const { error } = await client
      .from("menu_item_order_options")
      .update({ is_visible: !option.is_visible })
      .eq("id", option.id);
    if (error) {
      setMessage(`加購選項狀態更新失敗：${error.message}`);
      return;
    }
    await loadOrderOptions();
  };

  const openItemEditor = (item = null) => {
    if (!sections.length) return;
    closeItemEditor();
    updateSectionOptions();
    document.querySelector("#item-form-title").textContent = item
      ? "編輯品項"
      : "新增品項";
    itemForm.elements.section_id.value =
      item?.section_id || selectedSectionId || sections[0].id;
    if (item) {
      itemForm.elements.id.value = item.id;
      itemForm.elements.name.value = item.name || "";
      itemForm.elements.description.value = item.description || "";
      itemForm.elements.price.value = item.price || "";
      itemForm.elements.featured.checked = Boolean(item.featured);
      itemForm.elements.is_visible.checked = Boolean(item.is_visible);
      itemForm.elements.is_orderable.checked = Boolean(item.is_orderable);
      itemForm.elements.allow_item_note.checked =
        item.allow_item_note !== false;
      itemForm.elements.order_limit_quantity.value =
        item.order_limit_quantity ?? "";
      itemForm.elements.requires_staff_selection.checked = Boolean(
        item.requires_staff_selection
      );
      itemForm.elements.staff_selection_label.value =
        item.staff_selection_label || "請選擇湯娘的獨門料理";
      itemForm.elements.sort_order.value = item.sort_order ?? "";
      if (itemForm.elements.payroll_rule) {
        itemForm.elements.payroll_rule.value = item.payroll_rule || "excluded";
      }
    }
    itemEditor.hidden = false;
    itemEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const saveMenu = async (event) => {
    event.preventDefault();
    setMessage("");
    const button = menuForm.querySelector('button[type="submit"]');
    setBusy(button, true);
    const openMinute = parseTimeValue(
      menuForm.elements.order_open_time.value
    );
    let closeMinute = parseTimeValue(
      menuForm.elements.order_close_time.value
    );
    if (openMinute === null || closeMinute === null) {
      setBusy(button, false);
      setMessage("請以 HH:MM 格式填寫點餐營業時間。");
      return;
    }
    if (closeMinute <= openMinute && closeMinute < 1440) {
      closeMinute += 1440;
    }
    if (closeMinute <= openMinute || closeMinute > 2880) {
      setBusy(button, false);
      setMessage("關閉時間必須晚於開放時間，跨日結束時間可填 01:00。");
      return;
    }
    const weekdays = [
      ...document.querySelectorAll("[data-order-weekday]:checked")
    ].map((checkbox) => Number(checkbox.value));
    const payload = {
      title: menuForm.elements.title.value.trim(),
      short_title: menuForm.elements.short_title.value.trim(),
      english_title: menuForm.elements.english_title.value.trim(),
      description: menuForm.elements.description.value.trim(),
      is_visible: menuForm.elements.is_visible.checked,
      sort_order: Number(menuForm.elements.sort_order.value) || 0,
      order_customer_label:
        menuForm.elements.order_customer_label.value.trim() || "角色 ID",
      order_contact_visible:
        menuForm.elements.order_contact_visible.checked,
      order_contact_required:
        menuForm.elements.order_contact_visible.checked &&
        menuForm.elements.order_contact_required.checked,
      order_note_visible: menuForm.elements.order_note_visible.checked,
      order_note_required:
        menuForm.elements.order_note_visible.checked &&
        menuForm.elements.order_note_required.checked,
      order_acceptance_mode:
        menuForm.elements.order_acceptance_mode.value,
      order_open_weekdays: weekdays,
      order_open_minute: openMinute,
      order_close_minute: closeMinute,
      order_time_slot_minutes:
        Number(menuForm.elements.order_time_slot_minutes.value) || 30,
      order_time_label:
        menuForm.elements.order_time_label.value.trim() || "用餐時間",
      order_time_visible:
        menuForm.elements.order_time_visible.checked,
      order_time_required:
        menuForm.elements.order_time_visible.checked &&
        menuForm.elements.order_time_required.checked,
      order_closed_message:
        menuForm.elements.order_closed_message.value.trim() || null,
      order_manual_notice:
        menuForm.elements.order_manual_notice.value.trim() || null,
    };
    const { error } = await client
      .from("menus")
      .update(payload)
      .eq("key", currentMenuKey);
    setBusy(button, false);
    if (error) {
      setMessage(`菜單資料儲存失敗：${error.message}`);
      return;
    }
    setMessage("菜單基本資料已儲存。", "success");
    await loadCurrentMenu();
  };

  const saveSection = async (event) => {
    event.preventDefault();
    setMessage("");
    const button = sectionForm.querySelector('button[type="submit"]');
    setBusy(button, true);
    const id = sectionForm.elements.id.value;
    const sortValue = sectionForm.elements.sort_order.value.trim();
    const maxSort = sections.reduce(
      (maximum, section) =>
        Math.max(maximum, Number(section.sort_order) || 0),
      0
    );
    const payload = {
      menu_key: currentMenuKey,
      title: sectionForm.elements.title.value.trim(),
      subtitle: sectionForm.elements.subtitle.value.trim(),
      notice: sectionForm.elements.notice.value.trim(),
      layout_type: sectionForm.elements.layout_type.value,
      is_visible: sectionForm.elements.is_visible.checked,
      sort_order: sortValue ? Number(sortValue) : maxSort + 10,
    };
    const query = id
      ? client.from("menu_sections").update(payload).eq("id", id)
      : client.from("menu_sections").insert(payload);
    const { error } = await query;
    setBusy(button, false);
    if (error) {
      setMessage(`分類儲存失敗：${error.message}`);
      return;
    }
    closeSectionEditor();
    setMessage("分類已儲存。", "success");
    await loadCurrentMenu(id || null);
  };

  const saveItem = async (event) => {
    event.preventDefault();
    setMessage("");
    const button = itemForm.querySelector('button[type="submit"]');
    setBusy(button, true);
    const id = itemForm.elements.id.value;
    const sectionId = itemForm.elements.section_id.value;
    const sortValue = itemForm.elements.sort_order.value.trim();
    const limitValue =
      itemForm.elements.order_limit_quantity.value.trim();
    const maxSort = items
      .filter((item) => item.section_id === sectionId)
      .reduce(
        (maximum, item) => Math.max(maximum, Number(item.sort_order) || 0),
        0
      );
    const payload = {
      section_id: sectionId,
      name: itemForm.elements.name.value.trim(),
      description: itemForm.elements.description.value.trim(),
      price: itemForm.elements.price.value.trim(),
      featured: itemForm.elements.featured.checked,
      is_visible: itemForm.elements.is_visible.checked,
      is_orderable: itemForm.elements.is_orderable.checked,
      allow_item_note: itemForm.elements.allow_item_note.checked,
      order_limit_quantity: limitValue === "" ? null : Number(limitValue),
      requires_staff_selection:
        itemForm.elements.requires_staff_selection.checked,
      staff_selection_label:
        itemForm.elements.staff_selection_label.value.trim() ||
        "請選擇湯娘的獨門料理",
      sort_order: sortValue ? Number(sortValue) : maxSort + 10,
    };
    const payrollRule = itemForm.elements.payroll_rule?.value || "excluded";
    const query = id
      ? client.from("menu_items").update(payload).eq("id", id)
      : client.from("menu_items").insert(payload);
    const saveResult = await query.select("id").single();
    const { error } = saveResult;
    if (error) {
      setBusy(button, false);
      setMessage(`品項儲存失敗：${error.message}`);
      return;
    }
    const ruleResult = await client.rpc("upsert_menu_item_payroll_rule", {
      p_menu_item_id: saveResult.data.id,
      p_payroll_rule: payrollRule
    });
    setBusy(button, false);
    if (ruleResult.error) {
      setMessage(`品項已儲存，但薪資規則儲存失敗：${ruleResult.error.message}`);
      return;
    }
    selectedSectionId = sectionId;
    closeItemEditor();
    setMessage("品項已儲存。", "success");
    await loadCurrentMenu(sectionId);
  };

  const toggleSection = async (id) => {
    const section = sections.find((entry) => entry.id === id);
    if (!section) return;
    const { error } = await client
      .from("menu_sections")
      .update({ is_visible: !section.is_visible })
      .eq("id", id);
    if (error) {
      setMessage(`分類狀態更新失敗：${error.message}`);
      return;
    }
    setMessage(section.is_visible ? "分類已隱藏。" : "分類已顯示。", "success");
    await loadCurrentMenu(id);
  };

  const toggleItem = async (id) => {
    const item = items.find((entry) => entry.id === id);
    if (!item) return;
    const { error } = await client
      .from("menu_items")
      .update({ is_visible: !item.is_visible })
      .eq("id", id);
    if (error) {
      setMessage(`品項狀態更新失敗：${error.message}`);
      return;
    }
    setMessage(item.is_visible ? "品項已隱藏。" : "品項已顯示。", "success");
    await loadCurrentMenu(item.section_id);
  };

  const init = async (profile) => {
    if (!window.ADMIN_CAN?.("menu.manage")) {
      denied.hidden = false;
      workspace.hidden = true;
      return;
    }
    workspace.hidden = false;
    await loadCurrentMenu();
  };

  const syncMenuRequirementControls = () => {
    const contactVisible = menuForm.elements.order_contact_visible.checked;
    const noteVisible = menuForm.elements.order_note_visible.checked;
    menuForm.elements.order_contact_required.disabled = !contactVisible;
    menuForm.elements.order_note_required.disabled = !noteVisible;
    if (!contactVisible) {
      menuForm.elements.order_contact_required.checked = false;
    }
    if (!noteVisible) {
      menuForm.elements.order_note_required.checked = false;
    }
  };

  const syncTimeFieldControls = () => {
    const visible = menuForm.elements.order_time_visible.checked;
    menuForm.elements.order_time_label.disabled = !visible;
    menuForm.elements.order_time_required.disabled = !visible;
    if (!visible) {
      menuForm.elements.order_time_required.checked = false;
    }
  };

  document.querySelectorAll("[data-menu-key]").forEach((button) => {
    button.addEventListener("click", async () => {
      const key = button.dataset.menuKey;
      if (!allowedMenuKeys.has(key) || key === currentMenuKey) return;
      currentMenuKey = key;
      selectedSectionId = null;
      closeSectionEditor();
      closeItemEditor();
      await loadCurrentMenu();
    });
  });
  menuForm?.addEventListener("submit", saveMenu);
  menuForm?.elements.order_contact_visible.addEventListener(
    "change",
    syncMenuRequirementControls
  );
  menuForm?.elements.order_note_visible.addEventListener(
    "change",
    syncMenuRequirementControls
  );
  menuForm?.elements.order_acceptance_mode.addEventListener(
    "change",
    syncOrderModeHint
  );
  menuForm?.elements.order_time_visible.addEventListener(
    "change",
    syncTimeFieldControls
  );
  sectionForm?.addEventListener("submit", saveSection);
  itemForm?.addEventListener("submit", saveItem);
  optionForm?.addEventListener("submit", saveOrderOption);
  optionForm?.elements.requires_staff_capability.addEventListener(
    "change",
    syncOptionStaffFieldset
  );
  document
    .querySelector("[data-reset-order-option]")
    ?.addEventListener("click", resetOptionForm);
  document
    .querySelector("[data-close-option-manager]")
    ?.addEventListener("click", () => {
      optionEditor.hidden = true;
      optionItemId = null;
    });
  newSectionButton?.addEventListener("click", () => openSectionEditor());
  newItemButton?.addEventListener("click", () => openItemEditor());
  document
    .querySelector("[data-cancel-section]")
    ?.addEventListener("click", closeSectionEditor);
  document
    .querySelector("[data-cancel-item]")
    ?.addEventListener("click", closeItemEditor);

  sectionList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-section]");
    const toggle = event.target.closest("[data-toggle-section]");
    if (edit) {
      openSectionEditor(
        sections.find((section) => section.id === edit.dataset.editSection)
      );
      return;
    }
    if (toggle) {
      toggleSection(toggle.dataset.toggleSection);
      return;
    }
    const row = event.target.closest("[data-section-select]");
    if (row) {
      selectedSectionId = row.dataset.sectionSelect;
      renderSections();
      renderItems();
    }
  });

  itemList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-item]");
    const toggle = event.target.closest("[data-toggle-item]");
    const manageOptions = event.target.closest("[data-manage-options]");
    if (edit) {
      openItemEditor(items.find((item) => item.id === edit.dataset.editItem));
    } else if (manageOptions) {
      openOptionManager(manageOptions.dataset.manageOptions);
    } else if (toggle) {
      toggleItem(toggle.dataset.toggleItem);
    }
  });

  optionList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-order-option]");
    const toggle = event.target.closest("[data-toggle-order-option]");
    if (edit) {
      const option = orderOptions.find(
        (entry) => entry.id === edit.dataset.editOrderOption
      );
      if (option) editOrderOption(option);
    } else if (toggle) {
      const option = orderOptions.find(
        (entry) => entry.id === toggle.dataset.toggleOrderOption
      );
      if (option) toggleOrderOption(option);
    }
  });

  if (window.ADMIN_PROFILE) {
    init(window.ADMIN_PROFILE);
  } else {
    window.addEventListener(
      "admin-auth-ready",
      (event) => init(event.detail),
      { once: true }
    );
  }
})();
