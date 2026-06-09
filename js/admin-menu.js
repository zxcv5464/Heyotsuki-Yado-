(() => {
  const client = window.SUPABASE_CLIENT;
  const editableRoles = new Set(["owner", "admin"]);
  const allowedMenuKeys = new Set(["menu", "menu2"]);

  const workspace = document.querySelector("[data-menu-workspace]");
  const denied = document.querySelector("[data-menu-denied]");
  const message = document.querySelector("[data-menu-message]");
  const menuForm = document.querySelector("[data-menu-form]");
  const sectionForm = document.querySelector("[data-section-form]");
  const itemForm = document.querySelector("[data-item-form]");
  const sectionEditor = document.querySelector("[data-section-editor]");
  const itemEditor = document.querySelector("[data-item-editor]");
  const sectionList = document.querySelector("[data-section-list]");
  const itemList = document.querySelector("[data-item-list]");
  const newSectionButton = document.querySelector("[data-new-section]");
  const newItemButton = document.querySelector("[data-new-item]");
  const currentKeyBadge = document.querySelector("[data-current-menu-key]");
  const itemSectionLabel = document.querySelector("[data-item-section-label]");
  const itemSectionSelect = itemForm?.elements.namedItem("section_id");

  let currentMenuKey = "menu";
  let menuData = null;
  let sections = [];
  let items = [];
  let selectedSectionId = null;

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

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

  const fillMenuForm = () => {
    if (!menuData) return;
    menuForm.elements.title.value = menuData.title || "";
    menuForm.elements.short_title.value = menuData.short_title || "";
    menuForm.elements.english_title.value = menuData.english_title || "";
    menuForm.elements.description.value = menuData.description || "";
    menuForm.elements.href.value = menuData.href || "";
    menuForm.elements.is_visible.checked = Boolean(menuData.is_visible);
    menuForm.elements.sort_order.value = menuData.sort_order ?? "";
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
              </div>
              <p>${escapeHtml(item.description || "")}</p>
              <small>${escapeHtml(item.price)} ・ 排序 ${escapeHtml(item.sort_order)}</small>
            </div>
            <div class="menu-admin-row-actions">
              <button class="text-button" data-edit-item="${escapeHtml(item.id)}" type="button">編輯</button>
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
          "key, title, short_title, english_title, description, href, theme, is_visible, sort_order"
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
          "id, section_id, name, description, price, featured, is_visible, sort_order"
        )
        .in("section_id", sectionIds)
        .order("sort_order", { ascending: true });
      if (itemResult.error) {
        setMessage(`品項資料讀取失敗：${itemResult.error.message}`);
        return;
      }
      items = itemResult.data || [];
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
    itemEditor.hidden = true;
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
      itemForm.elements.sort_order.value = item.sort_order ?? "";
    }
    itemEditor.hidden = false;
    itemEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const saveMenu = async (event) => {
    event.preventDefault();
    setMessage("");
    const button = menuForm.querySelector('button[type="submit"]');
    setBusy(button, true);
    const payload = {
      title: menuForm.elements.title.value.trim(),
      short_title: menuForm.elements.short_title.value.trim(),
      english_title: menuForm.elements.english_title.value.trim(),
      description: menuForm.elements.description.value.trim(),
      is_visible: menuForm.elements.is_visible.checked,
      sort_order: Number(menuForm.elements.sort_order.value) || 0,
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
      sort_order: sortValue ? Number(sortValue) : maxSort + 10,
    };
    const query = id
      ? client.from("menu_items").update(payload).eq("id", id)
      : client.from("menu_items").insert(payload);
    const { error } = await query;
    setBusy(button, false);
    if (error) {
      setMessage(`品項儲存失敗：${error.message}`);
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
    if (!editableRoles.has(profile.role)) {
      denied.hidden = false;
      workspace.hidden = true;
      return;
    }
    workspace.hidden = false;
    await loadCurrentMenu();
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
  sectionForm?.addEventListener("submit", saveSection);
  itemForm?.addEventListener("submit", saveItem);
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
    if (edit) {
      openItemEditor(items.find((item) => item.id === edit.dataset.editItem));
    } else if (toggle) {
      toggleItem(toggle.dataset.toggleItem);
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
