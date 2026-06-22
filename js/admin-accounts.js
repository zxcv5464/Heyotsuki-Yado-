(() => {
  "use strict";
  const state = { client: null, snapshot: null, profile: null, can: null, editingProfileId: null };
  const workspace = document.querySelector("[data-accounts-workspace]");
  const denied = document.querySelector("[data-accounts-denied]");
  const message = document.querySelector("[data-accounts-message]");
  const list = document.querySelector("[data-accounts-list]");
  const createForm = document.querySelector("[data-account-create-form]");
  const editForm = document.querySelector("[data-account-edit-form]");
  const templateForm = document.querySelector("[data-template-form]");
  const editProfile = document.querySelector("[data-account-edit-profile]");
  const editSection = document.querySelector("[data-account-edit-section]");
  const manageSections = document.querySelectorAll("[data-accounts-manage]");
  const permissionSection = document.querySelector("[data-permissions-manage]");
  const templateList = document.querySelector("[data-template-list]");
  const resetPasswordButton = document.querySelector("[data-account-reset-password]");
  const deleteAccountButton = document.querySelector("[data-account-delete]");

  const setMessage = (text, type = "") => {
    message.textContent = text || "";
    message.className = "admin-message";
    if (type) message.classList.add(`is-${type}`);
  };
  const setBusy = (button, busy, label = "處理中...") => {
    if (!button) return;
    button.dataset.label ||= button.textContent;
    button.disabled = busy;
    button.textContent = busy ? label : button.dataset.label;
  };
  const append = (parent, tag, text, className = "") => {
    const node = document.createElement(tag);
    node.textContent = text;
    if (className) node.className = className;
    parent.append(node);
    return node;
  };
  const templates = () => state.snapshot?.templates || [];
  const definitions = () => state.snapshot?.definitions || [];
  const accounts = () => state.snapshot?.accounts || [];
  const staff = () => state.snapshot?.staffOptions || [];

  const addOptions = (select, items, value, label, placeholder) => {
    select.replaceChildren();
    if (placeholder !== undefined) {
      const option = new Option(placeholder, "");
      select.append(option);
    }
    items.forEach((item) => select.append(new Option(label(item), value(item))));
  };
  const renderPermissionBoxes = (container, selected, name) => {
    container.replaceChildren();
    const enabled = new Set(selected || []);
    const categories = new Map();
    definitions().forEach((definition) => {
      if (!categories.has(definition.category)) categories.set(definition.category, []);
      categories.get(definition.category).push(definition);
    });
    categories.forEach((items, category) => {
      const group = document.createElement("section");
      group.className = "admin-permission-group";
      append(group, "h4", category);
      const options = document.createElement("div");
      options.className = "admin-permission-options";
      items.forEach((definition) => {
        const label = document.createElement("label");
        label.className = "checkbox-field";
        const input = document.createElement("input");
        input.type = "checkbox";
        input.name = name;
        input.value = definition.key;
        input.checked = enabled.has(definition.key);
        const text = document.createElement("span");
        text.textContent = definition.label;
        label.append(input, text);
        options.append(label);
      });
      group.append(options);
      container.append(group);
    });
  };
  const getFunctionErrorMessage = async (error, fallback) => {
    if (!error) return fallback;
    try {
      const response = error.context;
      if (response?.clone) {
        const body = await response.clone().json();
        if (body?.error) return body.error;
      }
    } catch {}
    return error.message || fallback;
  };
  const readPermissionBoxes = (container) => [...container.querySelectorAll("input:checked")].map((input) => input.value);
  const populateStaffSelect = (select, currentId = "") => {
    const available = staff().filter((item) => !item.id || item.id === currentId || !accounts().some((account) => account.staffId === item.id));
    addOptions(select, available, (item) => item.id, (item) => `${item.name}${item.isVisible ? "" : "（隱藏）"}`, "不綁定員工");
    select.value = currentId || "";
  };
  const populateTemplateSelect = (select, currentId = "") => {
    addOptions(select, templates(), (item) => item.id, (item) => item.name, "選擇模板");
    select.value = currentId || "";
  };
  const syncCreateStaffRequirement = () => {
    const role = createForm.elements.role.value;
    const select = createForm.elements.staff_id;
    const placeholder = select.options[0];
    const required = role === "staff";
    select.required = required;
    if (placeholder) {
      placeholder.textContent = required ? "請選擇要綁定的員工" : "不綁定員工";
    }
  };
  const syncEditForm = () => {
    const account = accounts().find((item) => item.id === state.editingProfileId);
    if (!account) return;
    editForm.elements.display_name.value = account.displayName || "";
    editForm.elements.role.value = account.role;
    populateStaffSelect(editForm.elements.staff_id, account.staffId);
    populateTemplateSelect(editForm.elements.template_id, account.permissionTemplateId);
    editForm.elements.is_active.checked = Boolean(account.isActive);
    renderPermissionBoxes(document.querySelector("[data-account-edit-permissions]"), account.permissions, "permission");
  };
  const render = () => {
    list.replaceChildren();
    accounts().forEach((account) => {
      const card = document.createElement("article");
      card.className = "payroll-row";
      append(card, "strong", `${account.displayName}｜${account.email || "未提供 Email"}`);
      append(card, "p", `角色：${account.role}｜${account.isActive ? "啟用" : "已停用"}｜綁定員工：${account.staffName || "未綁定"}`, "field-help");
      append(card, "p", `模板：${templates().find((template) => template.id === account.permissionTemplateId)?.name || "未套用"}｜權限 ${account.permissions.length} 項`, "field-help");
      if (state.can("accounts.manage")) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "admin-button admin-button-secondary";
        button.dataset.accountSelect = account.id;
        button.textContent = "編輯帳號";
        card.append(button);
      }
      list.append(card);
    });
    manageSections.forEach((section) => { section.hidden = !state.can("accounts.manage"); });
    permissionSection.hidden = !state.can("permissions.manage");
    if (state.can("accounts.manage")) {
      addOptions(editProfile, accounts(), (item) => item.id, (item) => `${item.displayName}｜${item.email || item.id}`);
      populateStaffSelect(createForm.elements.staff_id);
      populateTemplateSelect(createForm.elements.template_id);
      syncCreateStaffRequirement();
      if (!accounts().some((account) => account.id === state.editingProfileId)) {
        state.editingProfileId = null;
      }
      editSection.hidden = !state.editingProfileId;
      if (state.editingProfileId) {
        editProfile.value = state.editingProfileId;
        syncEditForm();
      }
    }
    if (state.can("permissions.manage")) {
      renderPermissionBoxes(document.querySelector("[data-template-permissions]"), [], "template_permission");
      templateList.replaceChildren();
      templates().forEach((template) => {
        const card = document.createElement("article");
        card.className = "payroll-row";
        append(card, "strong", template.name);
        append(card, "p", template.description || "未填寫說明", "field-help");
        append(card, "p", `${template.permissions.length} 項權限${template.isSystem ? "｜系統模板" : ""}`, "field-help");
        if (!template.isSystem) {
          const edit = document.createElement("button");
          edit.type = "button"; edit.className = "admin-button admin-button-secondary";
          edit.dataset.templateEdit = template.id; edit.textContent = "編輯模板";
          const remove = document.createElement("button");
          remove.type = "button"; remove.className = "admin-button admin-button-secondary";
          remove.dataset.templateDelete = template.id; remove.textContent = "刪除模板";
          card.append(edit, remove);
        }
        templateList.append(card);
      });
    }
  };
  const load = async () => {
    const { data, error } = await state.client.rpc("get_admin_accounts_snapshot");
    if (error) throw error;
    state.snapshot = data;
    render();
  };

  list.addEventListener("click", (event) => {
    const button = event.target.closest("[data-account-select]");
    if (!button) return;
    state.editingProfileId = button.dataset.accountSelect;
    render();
    editSection.scrollIntoView({ behavior: "smooth", block: "start" });
  });
  editProfile.addEventListener("change", () => {
    state.editingProfileId = editProfile.value;
    syncEditForm();
  });
  editForm.elements.template_id.addEventListener("change", () => {
    const template = templates().find(
      (item) => item.id === editForm.elements.template_id.value
    );
    if (!template) return;
    renderPermissionBoxes(
      document.querySelector("[data-account-edit-permissions]"),
      template.permissions,
      "permission"
    );
  });
  createForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const staffId = String(createForm.elements.staff_id.value || "").trim();
    if (createForm.elements.role.value === "staff" && !staffId) {
      setMessage("一般員工帳號必須先選擇要綁定的員工。", "error");
      createForm.elements.staff_id.focus();
      return;
    }
    const button = createForm.querySelector("button[type='submit']");
    const body = {
      email: String(createForm.elements.email.value || "").trim(),
      password: String(createForm.elements.password.value || ""),
      display_name: String(createForm.elements.display_name.value || "").trim(),
      role: createForm.elements.role.value,
      staff_id: staffId,
      template_id: createForm.elements.template_id.value,
      is_active: createForm.elements.is_active.checked,
    };
    setBusy(button, true);
    const { data, error } = await state.client.functions.invoke("admin-create-staff-account", { body });
    setBusy(button, false);
    if (error || data?.error) { setMessage(`建立帳號失敗：${data?.error || await getFunctionErrorMessage(error, "帳號服務無法完成請求。")}`, "error"); return; }
    createForm.reset();
    await load();
    setMessage("帳號已建立，初始密碼未被保存。", "success");
  });
  createForm.elements.role.addEventListener("change", syncCreateStaffRequirement);
  resetPasswordButton.addEventListener("click", async () => {
    const password = window.prompt("輸入新的臨時密碼（至少 8 碼）：");
    if (password === null) return;
    if (password.length < 8) { setMessage("新密碼至少需要 8 碼。", "error"); return; }
    if (!window.confirm("確定重設此帳號密碼？舊密碼會立刻失效。")) return;
    setBusy(resetPasswordButton, true);
    const { data, error } = await state.client.functions.invoke("admin-manage-staff-account", {
      body: { action: "reset_password", profile_id: editProfile.value, password }
    });
    setBusy(resetPasswordButton, false);
    if (error || data?.error) { setMessage(`密碼重設失敗：${data?.error || await getFunctionErrorMessage(error, "帳號服務無法完成請求。")}`, "error"); return; }
    setMessage("密碼已重設；請用安全方式交付新的臨時密碼。", "success");
  });
  deleteAccountButton.addEventListener("click", async () => {
    const account = accounts().find((item) => item.id === editProfile.value);
    if (!account || !window.confirm(`確定註銷「${account.displayName}」帳號？此操作無法復原。`)) return;
    setBusy(deleteAccountButton, true, "註銷中...");
    const { data, error } = await state.client.functions.invoke("admin-manage-staff-account", {
      body: { action: "delete", profile_id: account.id }
    });
    setBusy(deleteAccountButton, false);
    if (error || data?.error) { setMessage(`帳號註銷失敗：${data?.error || await getFunctionErrorMessage(error, "帳號服務無法完成請求。")}`, "error"); return; }
    state.editingProfileId = null;
    await load();
    setMessage("帳號已註銷。", "success");
  });
  editForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = editForm.querySelector("button[type='submit']");
    const form = new FormData(editForm);
    setBusy(button, true);
    const { data, error } = await state.client.rpc("update_admin_account_permissions", {
      p_profile_id: form.get("profile_id"), p_display_name: form.get("display_name"),
      p_role: form.get("role"), p_staff_id: form.get("staff_id") || null,
      p_is_active: editForm.elements.is_active.checked, p_template_id: form.get("template_id") || null,
      p_permission_keys: readPermissionBoxes(document.querySelector("[data-account-edit-permissions]")),
    });
    setBusy(button, false);
    if (error) { setMessage(`帳號儲存失敗：${error.message}`, "error"); return; }
    state.snapshot = data;
    state.editingProfileId = null;
    render();
    setMessage("帳號權限已儲存。", "success");
  });
  templateForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = templateForm.querySelector("button[type='submit']");
    setBusy(button, true);
    const { data, error } = await state.client.rpc("save_admin_permission_template", {
      p_template_id: templateForm.dataset.templateId || null, p_name: templateForm.elements.name.value.trim(),
      p_description: templateForm.elements.description.value.trim(),
      p_permission_keys: readPermissionBoxes(document.querySelector("[data-template-permissions]")),
    });
    setBusy(button, false);
    if (error) { setMessage(`模板儲存失敗：${error.message}`, "error"); return; }
    templateForm.reset(); delete templateForm.dataset.templateId; state.snapshot = data; render(); setMessage("自訂模板已儲存。", "success");
  });
  templateList.addEventListener("click", async (event) => {
    const edit = event.target.closest("[data-template-edit]");
    const remove = event.target.closest("[data-template-delete]");
    if (edit) {
      const template = templates().find((item) => item.id === edit.dataset.templateEdit);
      if (!template) return;
      templateForm.dataset.templateId = template.id;
      templateForm.elements.name.value = template.name;
      templateForm.elements.description.value = template.description || "";
      renderPermissionBoxes(document.querySelector("[data-template-permissions]"), template.permissions, "template_permission");
      templateForm.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    if (!remove || !window.confirm("確定刪除此自訂模板？")) return;
    const { data, error } = await state.client.rpc("delete_admin_permission_template", { p_template_id: remove.dataset.templateDelete });
    if (error) { setMessage(`模板刪除失敗：${error.message}`, "error"); return; }
    state.snapshot = data; render(); setMessage("自訂模板已刪除。", "success");
  });
  window.addEventListener("admin-auth-ready", async (event) => {
    state.client = event.detail.client; state.profile = event.detail.profile; state.can = event.detail.can;
    if (!state.can("accounts.view")) { denied.hidden = false; return; }
    workspace.hidden = false;
    try { await load(); } catch (error) { setMessage(`帳號資料讀取失敗：${error.message}`, "error"); }
  }, { once: true });
})();
