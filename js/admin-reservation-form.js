(() => {
  const client = window.SUPABASE_CLIENT;
  const optionFieldTypes = new Set(["radio", "select"]);
  const creatableFieldTypes = new Set([
    "text",
    "textarea",
    "number",
    "radio",
    "select",
  ]);
  const fieldKeyPattern = /^[a-z0-9_]+$/;

  const workspace = document.querySelector("[data-form-workspace]");
  const readonlyMessage = document.querySelector("[data-form-readonly]");
  const message = document.querySelector("[data-form-message]");
  const settingsForm = document.querySelector("[data-settings-form]");
  const slotList = document.querySelector("[data-slot-list]");
  const overrideList = document.querySelector("[data-override-list]");
  const fieldList = document.querySelector("[data-field-list]");
  const optionList = document.querySelector("[data-option-list]");
  const slotEditor = document.querySelector("[data-slot-editor]");
  const overrideEditor = document.querySelector("[data-override-editor]");
  const fieldEditor = document.querySelector("[data-field-editor]");
  const optionSection = document.querySelector("[data-option-section]");
  const optionEditor = document.querySelector("[data-option-editor]");
  const slotForm = document.querySelector("[data-slot-form]");
  const overrideForm = document.querySelector("[data-override-form]");
  const fieldForm = document.querySelector("[data-field-form]");
  const optionForm = document.querySelector("[data-option-form]");

  let canEdit = false;
  let settings = null;
  let slots = [];
  let overrides = [];
  let fields = [];
  let options = [];
  let selectedFieldId = null;

  const supportsOptions = (field) =>
    field &&
    optionFieldTypes.has(field.field_type) &&
    field.field_key !== "reservation_time";

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

  const statusBadge = (visible) =>
    visible
      ? '<span class="status-badge status-badge-visible">顯示中</span>'
      : '<span class="status-badge status-badge-hidden">已隱藏</span>';

  const toggleEditing = () => {
    document
      .querySelectorAll(
        "[data-form-workspace] input, [data-form-workspace] textarea, [data-form-workspace] select, [data-form-workspace] button"
      )
      .forEach((control) => {
        control.disabled = !canEdit;
      });
    if (!canEdit) {
      readonlyMessage.hidden = false;
      [slotEditor, overrideEditor, fieldEditor, optionEditor].forEach(
        (editor) => {
          editor.hidden = true;
        }
      );
    }
  };

  const fillSettings = () => {
    settingsForm.elements.title.value = settings?.title || "";
    settingsForm.elements.description.value = settings?.description || "";
    settingsForm.elements.min_days_before.value =
      settings?.min_days_before ?? 1;
    settingsForm.elements.booking_window_days.value =
      settings?.booking_window_days ?? 60;
    settingsForm.elements.is_active.checked = Boolean(settings?.is_active);
    settingsForm
      .querySelectorAll('input[name="allowed_weekdays"]')
      .forEach((checkbox) => {
        checkbox.checked = (settings?.allowed_weekdays || []).includes(
          Number(checkbox.value)
        );
      });
  };

  const renderSlots = () => {
    slotList.innerHTML = slots.length
      ? slots
          .map(
            (slot) => `
              <article class="menu-admin-row${slot.is_visible ? "" : " is-hidden"}">
                <div class="menu-admin-row-main">
                  <div class="menu-admin-row-title"><strong>${escapeHtml(slot.label)}</strong>${statusBadge(slot.is_visible)}</div>
                  <small>${escapeHtml(slot.value)} ・ 排序 ${escapeHtml(slot.sort_order)}</small>
                </div>
                ${canEdit ? `<div class="menu-admin-row-actions"><button class="text-button" data-edit-slot="${escapeHtml(slot.id)}" type="button">編輯</button><button class="text-button" data-toggle-slot="${escapeHtml(slot.id)}" type="button">${slot.is_visible ? "隱藏" : "顯示"}</button></div>` : ""}
              </article>`
          )
          .join("")
      : '<p class="empty-state">目前沒有預約時段。</p>';
  };

  const renderOverrides = () => {
    overrideList.innerHTML = overrides.length
      ? overrides
          .map(
            (entry) => `
              <article class="menu-admin-row">
                <div class="menu-admin-row-main">
                  <div class="menu-admin-row-title"><strong>${escapeHtml(entry.target_date)}</strong><span class="status-badge ${entry.mode === "open" ? "status-badge-visible" : "status-badge-hidden"}">${entry.mode === "open" ? "例外開放" : "例外關閉"}</span></div>
                  <p>${escapeHtml(entry.note || "")}</p>
                </div>
                ${canEdit ? `<div class="menu-admin-row-actions"><button class="text-button" data-edit-override="${escapeHtml(entry.id)}" type="button">編輯</button></div>` : ""}
              </article>`
          )
          .join("")
      : '<p class="empty-state">目前沒有例外日期。</p>';
  };

  const renderFields = () => {
    fieldList.innerHTML = fields.length
      ? fields
          .map(
            (field) => `
              <article class="menu-admin-row${field.is_visible ? "" : " is-hidden"}" data-select-field="${escapeHtml(field.id)}">
                <div class="menu-admin-row-main">
                  <div class="menu-admin-row-title"><strong>${escapeHtml(field.label)}</strong>${statusBadge(field.is_visible)}${field.required ? '<span class="status-badge status-badge-featured">必填</span>' : ""}</div>
                  <p>${escapeHtml(field.help_text || "")}</p>
                  <small>${escapeHtml(field.field_key)} ・ ${escapeHtml(field.field_type)} ・ 排序 ${escapeHtml(field.sort_order)}</small>
                </div>
                ${canEdit ? `<div class="menu-admin-row-actions"><button class="text-button" data-edit-field="${escapeHtml(field.id)}" type="button">編輯</button></div>` : ""}
              </article>`
          )
          .join("")
      : '<p class="empty-state">目前沒有表單欄位。</p>';
  };

  const renderOptions = () => {
    const field = fields.find((entry) => entry.id === selectedFieldId);
    const fieldOptions = options.filter(
      (option) => option.field_id === selectedFieldId
    );
    optionSection.hidden = !supportsOptions(field);
    if (optionSection.hidden) return;
    document.querySelector("[data-option-field-label]").textContent =
      `目前欄位：${field.label}`;
    optionList.innerHTML = fieldOptions.length
      ? fieldOptions
          .map(
            (option) => `
              <article class="menu-admin-row${option.is_visible ? "" : " is-hidden"}">
                <div class="menu-admin-row-main">
                  <div class="menu-admin-row-title"><strong>${escapeHtml(option.label)}</strong>${statusBadge(option.is_visible)}</div>
                  <small>${escapeHtml(option.value)} ・ 排序 ${escapeHtml(option.sort_order)}</small>
                </div>
                ${canEdit ? `<div class="menu-admin-row-actions"><button class="text-button" data-edit-option="${escapeHtml(option.id)}" type="button">編輯</button><button class="text-button" data-toggle-option="${escapeHtml(option.id)}" type="button">${option.is_visible ? "隱藏" : "顯示"}</button></div>` : ""}
              </article>`
          )
          .join("")
      : '<p class="empty-state">此欄位目前沒有選項。</p>';
  };

  const renderAll = () => {
    fillSettings();
    renderSlots();
    renderOverrides();
    renderFields();
    renderOptions();
    toggleEditing();
  };

  const loadData = async () => {
    setMessage("");
    const [settingsResult, slotsResult, overridesResult, fieldsResult, optionsResult] =
      await Promise.all([
        client
          .from("reservation_form_settings")
          .select("id, title, description, allowed_weekdays, min_days_before, booking_window_days, is_active")
          .eq("id", "default")
          .maybeSingle(),
        client
          .from("reservation_time_slots")
          .select("id, label, value, is_visible, sort_order")
          .order("sort_order", { ascending: true }),
        client
          .from("reservation_date_overrides")
          .select("id, target_date, mode, note")
          .order("target_date", { ascending: true }),
        client
          .from("reservation_form_fields")
          .select("id, field_key, label, help_text, field_type, required, is_visible, sort_order")
          .order("sort_order", { ascending: true }),
        client
          .from("reservation_form_options")
          .select("id, field_id, label, value, is_visible, sort_order")
          .order("sort_order", { ascending: true }),
      ]);
    const failed = [
      settingsResult,
      slotsResult,
      overridesResult,
      fieldsResult,
      optionsResult,
    ].find((result) => result.error);
    if (failed) {
      setMessage(`預約表單設定讀取失敗：${failed.error.message}`);
      return;
    }
    settings = settingsResult.data;
    slots = slotsResult.data || [];
    overrides = overridesResult.data || [];
    fields = fieldsResult.data || [];
    options = optionsResult.data || [];
    if (!selectedFieldId) {
      selectedFieldId =
        fields.find((field) => supportsOptions(field))?.id ||
        null;
    }
    renderAll();
  };

  const closeEditor = (editor, form) => {
    form.reset();
    if (form.elements.id) form.elements.id.value = "";
    editor.hidden = true;
  };

  const openSlot = (slot = null) => {
    closeEditor(slotEditor, slotForm);
    document.querySelector("[data-slot-editor-title]").textContent = slot
      ? "編輯時段"
      : "新增時段";
    if (slot) {
      slotForm.elements.id.value = slot.id;
      slotForm.elements.label.value = slot.label;
      slotForm.elements.value.value = slot.value;
      slotForm.elements.sort_order.value = slot.sort_order;
      slotForm.elements.is_visible.checked = slot.is_visible;
    } else {
      slotForm.elements.is_visible.checked = true;
    }
    slotEditor.hidden = false;
    slotEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const openOverride = (entry = null) => {
    closeEditor(overrideEditor, overrideForm);
    document.querySelector("[data-override-editor-title]").textContent = entry
      ? "編輯例外日期"
      : "新增例外日期";
    if (entry) {
      overrideForm.elements.id.value = entry.id;
      overrideForm.elements.target_date.value = entry.target_date;
      overrideForm.elements.mode.value = entry.mode;
      overrideForm.elements.note.value = entry.note || "";
    }
    overrideEditor.hidden = false;
    overrideEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const openField = (field = null) => {
    closeEditor(fieldEditor, fieldForm);
    document.querySelector("[data-field-editor-title]").textContent = field
      ? "編輯欄位"
      : "新增欄位";
    fieldForm.elements.field_key.readOnly = Boolean(field);
    fieldForm.elements.field_type.disabled = Boolean(field);
    if (field) {
      fieldForm.elements.id.value = field.id;
      fieldForm.elements.field_key.value = field.field_key;
      fieldForm.elements.field_type.value = field.field_type;
      fieldForm.elements.label.value = field.label;
      fieldForm.elements.help_text.value = field.help_text || "";
      fieldForm.elements.sort_order.value = field.sort_order;
      fieldForm.elements.required.checked = field.required;
      fieldForm.elements.is_visible.checked = field.is_visible;
      selectedFieldId = field.id;
      renderOptions();
    } else {
      const maxSort = fields.reduce(
        (max, entry) => Math.max(max, Number(entry.sort_order) || 0),
        0
      );
      fieldForm.elements.field_type.value = "text";
      fieldForm.elements.sort_order.value = maxSort + 10;
      fieldForm.elements.is_visible.checked = true;
    }
    fieldEditor.hidden = false;
    fieldEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const openOption = (option = null) => {
    if (!selectedFieldId) return;
    closeEditor(optionEditor, optionForm);
    document.querySelector("[data-option-editor-title]").textContent = option
      ? "編輯選項"
      : "新增選項";
    optionForm.elements.field_id.value = selectedFieldId;
    if (option) {
      optionForm.elements.id.value = option.id;
      optionForm.elements.label.value = option.label;
      optionForm.elements.value.value = option.value;
      optionForm.elements.sort_order.value = option.sort_order;
      optionForm.elements.is_visible.checked = option.is_visible;
    } else {
      optionForm.elements.is_visible.checked = true;
    }
    optionEditor.hidden = false;
    optionEditor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  settingsForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!canEdit) return;
    const allowedWeekdays = [
      ...settingsForm.querySelectorAll(
        'input[name="allowed_weekdays"]:checked'
      ),
    ].map((input) => Number(input.value));
    if (!allowedWeekdays.length) {
      setMessage("請至少選擇一個可預約星期。");
      return;
    }
    const payload = {
      title: settingsForm.elements.title.value.trim(),
      description: settingsForm.elements.description.value.trim(),
      allowed_weekdays: allowedWeekdays,
      min_days_before: Number(settingsForm.elements.min_days_before.value) || 0,
      booking_window_days:
        Number(settingsForm.elements.booking_window_days.value) || 60,
      is_active: settingsForm.elements.is_active.checked,
    };
    const { error } = await client
      .from("reservation_form_settings")
      .update(payload)
      .eq("id", "default");
    if (error) setMessage(`基本設定儲存失敗：${error.message}`);
    else {
      setMessage("基本設定已儲存。", "success");
      await loadData();
    }
  });

  slotForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!canEdit) return;
    const id = slotForm.elements.id.value;
    const maxSort = slots.reduce(
      (max, slot) => Math.max(max, Number(slot.sort_order) || 0),
      0
    );
    const payload = {
      label: slotForm.elements.label.value.trim(),
      value: slotForm.elements.value.value.trim(),
      sort_order:
        Number(slotForm.elements.sort_order.value) || maxSort + 10,
      is_visible: slotForm.elements.is_visible.checked,
    };
    const query = id
      ? client.from("reservation_time_slots").update(payload).eq("id", id)
      : client.from("reservation_time_slots").insert(payload);
    const { error } = await query;
    if (error) setMessage(`時段儲存失敗：${error.message}`);
    else {
      closeEditor(slotEditor, slotForm);
      setMessage("預約時段已儲存。", "success");
      await loadData();
    }
  });

  overrideForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!canEdit) return;
    const id = overrideForm.elements.id.value;
    const payload = {
      target_date: overrideForm.elements.target_date.value,
      mode: overrideForm.elements.mode.value,
      note: overrideForm.elements.note.value.trim() || null,
    };
    const query = id
      ? client.from("reservation_date_overrides").update(payload).eq("id", id)
      : client.from("reservation_date_overrides").insert(payload);
    const { error } = await query;
    if (error) setMessage(`例外日期儲存失敗：${error.message}`);
    else {
      closeEditor(overrideEditor, overrideForm);
      setMessage("例外日期已儲存。", "success");
      await loadData();
    }
  });

  fieldForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!canEdit) return;
    const id = fieldForm.elements.id.value;
    const fieldKey = fieldForm.elements.field_key.value.trim();
    const fieldType = fieldForm.elements.field_type.value;
    if (!fieldKeyPattern.test(fieldKey)) {
      setMessage("欄位識別碼只能使用小寫英文、數字與底線。");
      fieldForm.elements.field_key.focus();
      return;
    }
    if (!id && fields.some((field) => field.field_key === fieldKey)) {
      setMessage("欄位識別碼已存在，請使用其他名稱。");
      fieldForm.elements.field_key.focus();
      return;
    }
    if (!id && !creatableFieldTypes.has(fieldType)) {
      setMessage("新增欄位類型只能使用 text、textarea、number、radio 或 select。");
      return;
    }
    const payload = {
      label: fieldForm.elements.label.value.trim(),
      help_text: fieldForm.elements.help_text.value.trim() || null,
      required: fieldForm.elements.required.checked,
      is_visible: fieldForm.elements.is_visible.checked,
      sort_order: Number(fieldForm.elements.sort_order.value) || 0,
    };
    const query = id
      ? client.from("reservation_form_fields").update(payload).eq("id", id)
      : client
          .from("reservation_form_fields")
          .insert({
            ...payload,
            field_key: fieldKey,
            field_type: fieldType,
          })
          .select("id")
          .single();
    const { data, error } = await query;
    if (error) {
      if (
        error.code === "23505" ||
        /reservation_form_fields_field_key_key|duplicate key/i.test(
          error.message || ""
        )
      ) {
        setMessage("欄位識別碼已存在，請使用其他名稱。");
      } else {
        setMessage(`欄位儲存失敗：${error.message}`);
      }
    }
    else {
      closeEditor(fieldEditor, fieldForm);
      if (!id && data?.id) {
        selectedFieldId = data.id;
      }
      setMessage(id ? "表單欄位已儲存。" : "新欄位已建立。", "success");
      await loadData();
    }
  });

  optionForm?.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!canEdit) return;
    const id = optionForm.elements.id.value;
    const fieldId = optionForm.elements.field_id.value;
    const fieldOptions = options.filter((option) => option.field_id === fieldId);
    const maxSort = fieldOptions.reduce(
      (max, option) => Math.max(max, Number(option.sort_order) || 0),
      0
    );
    const payload = {
      field_id: fieldId,
      label: optionForm.elements.label.value.trim(),
      value: optionForm.elements.value.value.trim(),
      is_visible: optionForm.elements.is_visible.checked,
      sort_order:
        Number(optionForm.elements.sort_order.value) || maxSort + 10,
    };
    const query = id
      ? client.from("reservation_form_options").update(payload).eq("id", id)
      : client.from("reservation_form_options").insert(payload);
    const { error } = await query;
    if (error) setMessage(`選項儲存失敗：${error.message}`);
    else {
      closeEditor(optionEditor, optionForm);
      setMessage("欄位選項已儲存。", "success");
      await loadData();
    }
  });

  const toggleVisible = async (table, record) => {
    if (!canEdit || !record) return;
    const { error } = await client
      .from(table)
      .update({ is_visible: !record.is_visible })
      .eq("id", record.id);
    if (error) setMessage(`顯示狀態更新失敗：${error.message}`);
    else await loadData();
  };

  document.querySelector("[data-new-slot]")?.addEventListener("click", () => openSlot());
  document.querySelector("[data-new-override]")?.addEventListener("click", () => openOverride());
  document.querySelector("[data-new-field]")?.addEventListener("click", () => openField());
  document.querySelector("[data-new-option]")?.addEventListener("click", () => openOption());
  document.querySelector("[data-cancel-slot]")?.addEventListener("click", () => closeEditor(slotEditor, slotForm));
  document.querySelector("[data-cancel-override]")?.addEventListener("click", () => closeEditor(overrideEditor, overrideForm));
  document.querySelector("[data-cancel-field]")?.addEventListener("click", () => closeEditor(fieldEditor, fieldForm));
  document.querySelector("[data-cancel-option]")?.addEventListener("click", () => closeEditor(optionEditor, optionForm));

  slotList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-slot]");
    const toggle = event.target.closest("[data-toggle-slot]");
    if (edit) openSlot(slots.find((slot) => slot.id === edit.dataset.editSlot));
    if (toggle) toggleVisible("reservation_time_slots", slots.find((slot) => slot.id === toggle.dataset.toggleSlot));
  });
  overrideList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-override]");
    if (edit) openOverride(overrides.find((entry) => entry.id === edit.dataset.editOverride));
  });
  fieldList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-field]");
    const row = event.target.closest("[data-select-field]");
    const id = edit?.dataset.editField || row?.dataset.selectField;
    const field = fields.find((entry) => entry.id === id);
    if (!field) return;
    selectedFieldId = field.id;
    renderOptions();
    if (edit && canEdit) openField(field);
  });
  optionList?.addEventListener("click", (event) => {
    const edit = event.target.closest("[data-edit-option]");
    const toggle = event.target.closest("[data-toggle-option]");
    if (edit) openOption(options.find((option) => option.id === edit.dataset.editOption));
    if (toggle) toggleVisible("reservation_form_options", options.find((option) => option.id === toggle.dataset.toggleOption));
  });

  const init = async (profile) => {
    canEdit = window.ADMIN_CAN?.("reservation_form.manage") === true;
    workspace.hidden = false;
    await loadData();
  };

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
