(() => {
  "use strict";
  const state = { client: null, snapshot: null, periodId: null, roleId: null, roleFormMode: null, slotDraft: [], tab: "setup", accountRole: null, periodFormMode: null, editingPeriodId: null };
  const $ = (selector) => document.querySelector(selector);
  const access = $("[data-roster-access]");
  const denied = $("[data-roster-denied]");
  const message = $("[data-roster-message]");
  const periodList = $("[data-roster-period-list]");
  const periodForm = $("[data-roster-period-form]");
  const slotEditor = $("[data-roster-slot-editor]");
  const requirementEditor = $("[data-roster-requirement-editor]");
  const workspace = $("[data-roster-period-workspace]");
  const assignmentSection = $("[data-roster-assignment-section]");
  const previewSection = $("[data-roster-preview-section]");
  const roleForm = $("[data-roster-role-form]");
  const roleList = $("[data-roster-role-list]");
  const statusLabels = { unselected: "未選擇", available: "可", unavailable: "否", standby: "備用" };
  const periodLabels = { draft: "關閉填寫", open: "開放填寫", published: "關閉填寫", locked: "關閉填寫" };
  const append = (parent, tag, text = "", className = "") => {
    const node = document.createElement(tag); node.textContent = text; if (className) node.className = className; parent.append(node); return node;
  };
  const button = (text, action, className = "admin-button admin-button-secondary") => {
    const node = document.createElement("button"); node.type = "button"; node.className = className; node.textContent = text; node.dataset.rosterAction = action; return node;
  };
  const can = (key) => window.ADMIN_CAN?.(key) === true;
  const isStaffAccount = () => state.accountRole === "staff";
  const isManager = () => !isStaffAccount() && state.snapshot?.canManage === true && can("roster.manage");
  const activePeriod = () => state.snapshot?.period || null;
  const slots = () => state.snapshot?.slots || [];
  const staff = () => state.snapshot?.staff || [];
  const requirements = () => state.snapshot?.requirements || [];
  const availability = () => state.snapshot?.availability || [];
  const assignments = () => state.snapshot?.assignments || [];
  const availabilityFor = (slotId, staffId) => availability().find((entry) => entry.shiftSlotId === slotId && entry.staffId === staffId)?.status || "unselected";
  const staffName = (staffId) => staff().find((item) => item.id === staffId)?.name || "已移除員工";
  const setMessage = (text = "", type = "") => { message.textContent = text; message.className = "admin-message"; if (type) message.classList.add(`is-${type}`); };
  const setBusy = (element, busy, label = "處理中...") => { if (!element) return; element.dataset.label ||= element.textContent; element.disabled = busy; element.textContent = busy ? label : element.dataset.label; };
  const rpc = async (name, args) => { const { data, error } = await state.client.rpc(name, args); if (error) throw error; state.snapshot = data; state.periodId = data?.period?.id || state.periodId; hydratePeriodForm(); render(); return data; };
  const formatDate = (value) => value ? new Intl.DateTimeFormat("zh-TW", { month: "numeric", day: "numeric", weekday: "short" }).format(new Date(`${value}T00:00:00`)) : "";
  const formatTime = (value) => {
    const time = String(value || "").slice(0, 5);
    return time === "00:00" ? "24:00" : time;
  };

  const rangeDates = (from, to) => {
    if (!from || !to || from > to) return [];
    const [fromYear, fromMonth, fromDay] = from.split("-").map(Number);
    const [toYear, toMonth, toDay] = to.split("-").map(Number);
    const result = []; const cursor = new Date(Date.UTC(fromYear, fromMonth - 1, fromDay)); const end = new Date(Date.UTC(toYear, toMonth - 1, toDay));
    while (cursor <= end) {
      result.push(`${cursor.getUTCFullYear()}-${String(cursor.getUTCMonth() + 1).padStart(2, "0")}-${String(cursor.getUTCDate()).padStart(2, "0")}`);
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    return result;
  };
  const rebuildSlotDraft = () => {
    const from = periodForm.elements.date_from.value; const to = periodForm.elements.date_to.value;
    const old = new Map(state.slotDraft.map((slot) => [`${slot.businessDate}:${slot.sortOrder}`, slot]));
    state.slotDraft = rangeDates(from, to).flatMap((businessDate) => [
      old.get(`${businessDate}:10`) || { businessDate, label: "第一班", startTime: "21:00", endTime: "22:30", sortOrder: 10, isActive: true },
      old.get(`${businessDate}:20`) || { businessDate, label: "第二班", startTime: "22:30", endTime: "00:00", sortOrder: 20, isActive: true },
    ]);
    renderSlotEditor();
  };
  const hydratePeriodForm = () => {
    const period = activePeriod();
    if (!period || !isManager()) return;
    periodForm.elements.date_from.value = period.dateFrom;
    periodForm.elements.date_to.value = period.dateTo;
    state.slotDraft = slots().map((slot) => ({ businessDate: slot.businessDate, label: slot.label, startTime: slot.startTime.slice(0, 5), endTime: slot.endTime.slice(0, 5), sortOrder: slot.sortOrder, isActive: slot.isActive }));
  };
  const renderSlotEditor = () => {
    slotEditor.replaceChildren();
    const days = new Map();
    state.slotDraft.forEach((slot, index) => {
      if (!days.has(slot.businessDate)) {
        const day = document.createElement("section"); day.className = "roster-slot-day"; append(day, "h4", formatDate(slot.businessDate)); days.set(slot.businessDate, day); slotEditor.append(day);
      }
      const card = document.createElement("div"); card.className = "roster-slot-row";
      [["label", "名稱", "text"], ["startTime", "開始", "time"], ["endTime", "結束", "time"]].forEach(([key, label, type]) => {
        const field = document.createElement("label"); field.className = "admin-field"; append(field, "span", label);
        const input = document.createElement("input"); input.type = type; input.value = slot[key]; input.dataset.slotIndex = index; input.dataset.slotField = key; field.append(input); card.append(field);
      });
      const enabled = document.createElement("label"); enabled.className = "checkbox-field"; const checkbox = document.createElement("input"); checkbox.type = "checkbox"; checkbox.checked = slot.isActive; checkbox.dataset.slotIndex = index; checkbox.dataset.slotField = "isActive"; enabled.append(checkbox, document.createTextNode("啟用")); card.append(enabled);
      days.get(slot.businessDate).append(card);
    });
  };
  const renderRequirementEditor = () => {
    requirementEditor.replaceChildren();
    (state.snapshot?.roles || []).filter((role) => role.isActive).forEach((role) => {
      const label = document.createElement("label"); label.className = "checkbox-field";
      const input = document.createElement("input"); input.type = "checkbox"; input.value = role.id; input.checked = state.periodFormMode === "create" || requirements().some((item) => item.roleId === role.id) || !activePeriod(); input.dataset.roleRequirement = "true";
      label.append(input, document.createTextNode(`${role.name}（${role.minStaffCount}-${role.maxStaffCount} 人）`)); requirementEditor.append(label);
    });
  };
  const renderPeriods = () => {
    periodList.replaceChildren();
    (state.snapshot?.periods || []).forEach((period) => {
      const item = document.createElement("button"); item.type = "button"; item.className = "roster-period-button"; item.dataset.periodId = period.id;
      if (period.id === activePeriod()?.id) item.classList.add("is-active");
      append(item, "strong", period.title); append(item, "span", `${period.dateFrom} - ${period.dateTo}｜${periodLabels[period.status] || period.status}`); periodList.append(item);
    });
    if (!(state.snapshot?.periods || []).length) append(periodList, "p", "尚未建立排班期間。", "admin-empty");
  };
  const renderGlobalPeriods = () => {
    const container = $("[data-roster-global-periods]"); container.replaceChildren();
    const periods = [...(state.snapshot?.periods || [])].sort((a, b) => b.dateFrom.localeCompare(a.dateFrom));
    if (!periods.length) { append(container, "span", "尚未建立可查看的排班期間。", "field-help"); return; }

    const renderGroup = (label, groupPeriods, isOpen) => {
      if (!groupPeriods.length) return;
      const containsSelectedPeriod = state.periodFormMode !== "create" && groupPeriods.some((period) => period.id === activePeriod()?.id);
      const group = document.createElement("details"); group.className = "roster-period-group"; group.open = isOpen || containsSelectedPeriod;
      const summary = document.createElement("summary");
      append(summary, "strong", label); append(summary, "span", `${groupPeriods.length} 期`); group.append(summary);
      const list = document.createElement("div"); list.className = "roster-period-list";
      groupPeriods.forEach((period) => {
        const item = document.createElement("button"); item.type = "button"; item.className = "roster-period-button"; item.dataset.periodId = period.id;
        if (state.periodFormMode !== "create" && period.id === activePeriod()?.id) item.classList.add("is-active");
        append(item, "strong", period.title); append(item, "span", periodLabels[period.status] || period.status); list.append(item);
      });
      group.append(list); container.append(group);
    };

    const today = taipeiToday();
    renderGroup("目前與未過期期間", periods.filter((period) => period.dateTo >= today), true);
    renderGroup("已過期期間", periods.filter((period) => period.dateTo < today), false);
  };
  const renderRoles = () => {
    roleList.replaceChildren();
    const roles = state.snapshot?.roles || [];
    roles.forEach((role, index) => {
      const row = document.createElement("article"); row.className = "roster-role-row";
      const info = document.createElement("div"); info.className = "roster-role-info";
      append(info, "strong", role.name);
      append(info, "span", `每班 ${role.minStaffCount}-${role.maxStaffCount} 人${role.isActive ? "" : "｜已停用"}`, "field-help");
      if (role.description) append(info, "p", role.description, "field-help");
      const actions = document.createElement("div"); actions.className = "roster-role-actions";
      const moveUp = button("上移", "move-role", "admin-button admin-button-secondary admin-button-small"); moveUp.dataset.roleId = role.id; moveUp.dataset.direction = "up"; moveUp.disabled = index === 0;
      const moveDown = button("下移", "move-role", "admin-button admin-button-secondary admin-button-small"); moveDown.dataset.roleId = role.id; moveDown.dataset.direction = "down"; moveDown.disabled = index === roles.length - 1;
      const edit = button("編輯", "edit-role", "admin-button admin-button-secondary admin-button-small"); edit.dataset.roleId = role.id;
      const remove = button("刪除", "delete-role", "admin-button admin-button-secondary admin-button-small"); remove.dataset.roleId = role.id;
      actions.append(moveUp, moveDown, edit, remove); row.append(info, actions); roleList.append(row);
    });
  };
  const statusSelect = (value, disabled = false) => {
    const select = document.createElement("select"); select.className = `roster-status-${value}`; select.disabled = disabled;
    Object.entries(statusLabels).forEach(([key, label]) => select.append(new Option(label, key, false, key === value))); return select;
  };
  const renderSelfAvailability = () => {
    const container = $("[data-roster-self-availability]"); container.replaceChildren(); const period = activePeriod();
    if (!period || !state.snapshot?.canSubmit) return;
    if (!state.snapshot?.myStaffId) return;
    append(container, "h4", "我的可上班狀態");
    const grid = document.createElement("div"); grid.className = "roster-self-grid";
    const editable = period.status === "open" || isManager();
    const days = new Map();
    slots().forEach((slot) => {
      if (!days.has(slot.businessDate)) {
        const day = document.createElement("section"); day.className = "roster-self-day"; append(day, "h5", formatDate(slot.businessDate)); days.set(slot.businessDate, day); grid.append(day);
      }
      const row = document.createElement("label"); row.className = "roster-self-shift";
      const detail = document.createElement("span"); append(detail, "strong", slot.label); append(detail, "small", `${formatTime(slot.startTime)} - ${formatTime(slot.endTime)}`);
      const select = statusSelect(availabilityFor(slot.id, state.snapshot.myStaffId), !editable); select.dataset.selfSlotId = slot.id;
      select.addEventListener("change", () => { select.className = `roster-status-${select.value}`; });
      row.append(detail, select); days.get(slot.businessDate).append(row);
    });
    if (editable) {
      days.forEach((day) => {
        const actions = document.createElement("div"); actions.className = "roster-self-day-actions";
        [["整天可", "available"], ["整天否", "unavailable"], ["整天備用", "standby"], ["清空", "unselected"]].forEach(([label, value]) => {
          const quick = button(label, "set-self-day", "admin-button admin-button-secondary admin-button-small"); quick.dataset.selfDayValue = value; actions.append(quick);
        });
        day.append(actions);
      });
    }
    container.append(grid);
    if (editable) {
      const save = button("儲存本期可上班狀態", "save-self", "admin-button"); container.append(save);
    } else {
      append(container, "p", "此期間已關閉填寫，目前僅可查看已儲存的可上班狀態。", "field-help");
    }
  };
  const renderMatrix = () => {
    const head = $("[data-roster-matrix-head]"); const body = $("[data-roster-matrix-body]"); head.replaceChildren(); body.replaceChildren(); if (!isManager()) return;
    const tr = document.createElement("tr"); append(tr, "th", "員工"); slots().forEach((slot) => append(tr, "th", `${formatDate(slot.businessDate)}\n${slot.label}`)); head.append(tr);
    const query = $("[data-roster-staff-search]").value.trim().toLowerCase(); const filter = $("[data-roster-status-filter]").value;
    staff().filter((person) => !query || person.name.toLowerCase().includes(query)).filter((person) => filter === "all" || slots().some((slot) => availabilityFor(slot.id, person.id) === filter)).forEach((person) => {
      const row = document.createElement("tr"); append(row, "th", person.name); slots().forEach((slot) => { const cell = document.createElement("td"); const select = statusSelect(availabilityFor(slot.id, person.id)); select.dataset.matrixSlotId = slot.id; select.dataset.matrixStaffId = person.id; cell.append(select); row.append(cell); }); body.append(row);
    });
  };
  const renderColumnTools = () => {
    const container = $("[data-roster-column-tools]"); container.replaceChildren(); if (!isManager()) return;
    slots().forEach((slot) => { const card = document.createElement("div"); card.className = "roster-column-tool"; append(card, "strong", `${formatDate(slot.businessDate)} ${slot.label}`); const select = statusSelect("available"); select.dataset.columnSlotId = slot.id; const apply = button("套用", "apply-column", "admin-button admin-button-small"); apply.dataset.slotId = slot.id; const clear = button("清空", "clear-column", "admin-button admin-button-secondary admin-button-small"); clear.dataset.slotId = slot.id; card.append(select, apply, clear); container.append(card); });
  };
  const renderAssignments = () => {
    const container = $("[data-roster-assignment-list]"); container.replaceChildren(); const period = activePeriod(); if (!period) return;
    const bySlot = new Map(slots().map((slot) => [slot.id, []])); assignments().forEach((item) => bySlot.get(item.shiftSlotId)?.push(item));
    slots().forEach((slot) => { const card = document.createElement("article"); card.className = "roster-assignment-card"; append(card, "h4", `${formatDate(slot.businessDate)}｜${slot.label} ${formatTime(slot.startTime)}-${formatTime(slot.endTime)}`);
      requirements().filter((requirement) => requirement.isRequired).forEach((requirement) => { const line = document.createElement("div"); line.className = "roster-assignment-role"; append(line, "strong", `${requirement.roleName}（至少 ${requirement.minStaffCount} 人）`);
        const rows = bySlot.get(slot.id).filter((item) => item.roleRequirementId === requirement.id); rows.forEach((item) => line.append(assignmentEditor(item, slot, requirement)));
        if (isManager() && period.status !== "published" && period.status !== "locked") { const add = button("新增人員／待定", "add-assignment", "admin-button admin-button-secondary admin-button-small"); add.dataset.slotId = slot.id; add.dataset.requirementId = requirement.id; line.append(add); }
        if (!rows.length) append(line, "p", "待定", "field-help"); card.append(line);
      }); container.append(card);
    });
  };
  const assignmentEditor = (item, slot, requirement) => {
    const row = document.createElement("div"); row.className = "roster-assignment-row";
    if (!isManager() || activePeriod().status === "published" || activePeriod().status === "locked") { append(row, "span", item.status === "pending" ? "待定" : staffName(item.staffId)); return row; }
    const select = document.createElement("select"); select.dataset.assignmentStaffId = item.id; select.append(new Option("待定", "")); staff().forEach((person) => { const stateText = availabilityFor(slot.id, person.id); select.append(new Option(`${person.name}（${statusLabels[stateText]}）`, person.id, false, person.id === item.staffId)); });
    const save = button("儲存", "save-assignment", "admin-button admin-button-small"); save.dataset.assignmentId = item.id; save.dataset.slotId = slot.id; save.dataset.requirementId = requirement.id;
    const remove = button("移除", "delete-assignment", "admin-button admin-button-secondary admin-button-small"); remove.dataset.assignmentId = item.id; row.append(select, save, remove); return row;
  };
  const taipeiToday = () => new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Taipei" }).format(new Date());
  const dateSummary = (businessDate) => {
    const lines = ["嘿月湯宿", `${formatDate(businessDate)} 營業班表`];
    slots().filter((slot) => slot.businessDate === businessDate).sort((a, b) => a.sortOrder - b.sortOrder).forEach((slot) => {
      lines.push(`${slot.label}｜${formatTime(slot.startTime)} - ${formatTime(slot.endTime)}`);
      requirements().filter((requirement) => requirement.isRequired).forEach((requirement) => {
        const members = assignments().filter((item) => item.shiftSlotId === slot.id && item.roleRequirementId === requirement.id && item.status === "assigned").map((item) => staffName(item.staffId));
        lines.push(`・${requirement.roleName}｜${members.join("、") || "待定"}`);
      });
    });
    return lines;
  };
  const renderPreview = () => {
    const preview = $("[data-roster-print-preview]"); preview.replaceChildren(); const period = activePeriod(); if (!period) return;
    const dates = [...new Set(slots().map((slot) => slot.businessDate))].sort((a, b) => b.localeCompare(a));
    if (!dates.length) { append(preview, "p", "此期間尚未建立班別。", "field-help"); return; }
    dates.forEach((businessDate) => {
      const details = document.createElement("details"); details.className = "roster-day-details";
      const summary = document.createElement("summary"); summary.textContent = `${formatDate(businessDate)}｜班表`; details.append(summary);
      const toolbar = document.createElement("div"); toolbar.className = "admin-card-actions";
      const copy = button("複製本日文字", "copy-date", "admin-button admin-button-secondary admin-button-small"); copy.dataset.businessDate = businessDate;
      const png = button("下載本日 PNG", "png-date", "admin-button admin-button-secondary admin-button-small"); png.dataset.businessDate = businessDate; toolbar.append(copy, png); details.append(toolbar);
      const grid = document.createElement("div"); grid.className = "roster-print-day-grid";
      slots().filter((slot) => slot.businessDate === businessDate).sort((a, b) => a.sortOrder - b.sortOrder).forEach((slot) => {
        const card = document.createElement("section"); card.className = "roster-print-slot"; append(card, "h3", `${slot.label}｜${formatTime(slot.startTime)} - ${formatTime(slot.endTime)}`);
        requirements().filter((requirement) => requirement.isRequired).forEach((requirement) => { const members = assignments().filter((item) => item.shiftSlotId === slot.id && item.roleRequirementId === requirement.id && item.status === "assigned").map((item) => staffName(item.staffId)); append(card, "p", `${requirement.roleName}｜${members.join("、") || "待定"}`); }); grid.append(card);
      });
      details.append(grid); preview.append(details);
    });
  };
  const render = () => {
    renderPeriods(); renderGlobalPeriods(); const period = activePeriod(); workspace.hidden = !period; assignmentSection.hidden = !period; previewSection.hidden = !period;
    document.querySelectorAll("[data-roster-manage]").forEach((element) => { element.hidden = !isManager(); });
    document.querySelector("[data-roster-manager-section]").hidden = !isManager();
    roleForm.hidden = !isManager() || !state.roleFormMode;
    $("[data-roster-role-form-heading]").textContent = state.roleFormMode === "edit" ? "修改職位" : "新增職位";
    if (!isManager() && ["setup", "roles", "assignments"].includes(state.tab)) state.tab = "availability";
    if (!period && ["availability", "assignments", "preview"].includes(state.tab) && isManager()) state.tab = "setup";
    $("[data-roster-period-switcher]").hidden = state.tab === "roles";
    document.querySelectorAll("[data-roster-tab]").forEach((tab) => tab.classList.toggle("is-active", tab.dataset.rosterTab === state.tab));
    document.querySelectorAll("[data-roster-panel]").forEach((panel) => {
      const needsPeriod = panel === workspace || panel === assignmentSection || panel === previewSection;
      panel.hidden = panel.dataset.rosterPanel !== state.tab || (needsPeriod && !period);
    });
    $("[data-roster-no-open]").hidden = isManager() || Boolean(period) || state.tab !== "availability";
    $("[data-roster-unbound]").hidden = isManager() || !period || !state.snapshot?.canSubmit || Boolean(state.snapshot?.myStaffId) || state.tab !== "availability";
    periodForm.hidden = !isManager() || !state.periodFormMode || (state.periodFormMode === "edit" && period?.status !== "open");
    if (isManager()) { renderRoles(); renderSlotEditor(); renderRequirementEditor(); }
    if (!period) return;
    $("[data-roster-period-form-heading]").textContent = state.periodFormMode === "edit" ? "修改目前排班期間" : "建立新排班期間";
    $("[data-roster-period-submit]").textContent = state.periodFormMode === "edit" ? "儲存目前期間" : "建立並開放填寫";
    $("[data-roster-open]").hidden = !isManager() || period.status !== "draft";
    $("[data-roster-close]").hidden = !isManager() || period.status !== "open";
    $("[data-roster-period-title]").textContent = period.title; $("[data-roster-period-status]").textContent = `目前狀態：${periodLabels[period.status] || period.status}`;
    renderSelfAvailability(); renderMatrix(); renderColumnTools(); renderAssignments(); renderPreview();
  };
  const load = async (periodId = state.periodId) => { const data = await rpc("roster_snapshot", { p_period_id: periodId || null }); state.periodId = data?.period?.id || null; };
  const readSlots = () => state.slotDraft.map((slot) => ({ ...slot }));
  const readRequirements = () => [...requirementEditor.querySelectorAll("input:checked")].map((input, index) => { const role = (state.snapshot?.roles || []).find((item) => item.id === input.value); return { roleId: role.id, roleName: role.name, minStaffCount: role.minStaffCount, maxStaffCount: role.maxStaffCount, sortOrder: role.sortOrder || index, isRequired: true }; });
  const saveAvailability = async (entries, trigger) => { setBusy(trigger, true); try { await rpc("save_roster_availability", { p_period_id: activePeriod().id, p_entries: entries }); setMessage("可上班狀態已儲存。", "success"); } catch (error) { setMessage(`儲存失敗：${error.message}`, "error"); } finally { setBusy(trigger, false); } };
  const setPeriodStatus = async (status, trigger) => { if (activePeriod()?.status === "locked") { setMessage("此期間已鎖定，無法再變更狀態。", "error"); return; } setBusy(trigger, true); try { await rpc("set_roster_period_status", { p_period_id: activePeriod().id, p_status: status }); setMessage(`期間已${periodLabels[status]}。`, "success"); } catch (error) { setMessage(`狀態更新失敗：${error.message}`, "error"); } finally { setBusy(trigger, false); } };

  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-period-id]"); if (!target) return;
    const shouldEditSelectedPeriod = isManager() && state.tab === "setup";
    load(target.dataset.periodId).then(() => {
      if (!shouldEditSelectedPeriod) return;
      state.periodFormMode = "edit"; state.editingPeriodId = target.dataset.periodId;
      hydratePeriodForm(); render();
    }).catch((error) => setMessage(error.message, "error"));
  });
  document.querySelector(".roster-tabs").addEventListener("click", (event) => { const tab = event.target.closest("[data-roster-tab]"); if (!tab || tab.hidden) return; state.tab = tab.dataset.rosterTab; render(); });
  periodForm.elements.date_from.addEventListener("change", rebuildSlotDraft); periodForm.elements.date_to.addEventListener("change", rebuildSlotDraft);
  slotEditor.addEventListener("change", (event) => { const input = event.target; const index = Number(input.dataset.slotIndex); const key = input.dataset.slotField; if (!Number.isInteger(index) || !key) return; state.slotDraft[index][key] = input.type === "checkbox" ? input.checked : input.value; });
  const toDateKey = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const suggestWeekendRange = () => {
    const today = new Date(); const weekday = today.getDay(); const fridayOffset = weekday === 0 ? -2 : weekday === 6 ? -1 : 5 - weekday;
    const friday = new Date(today.getFullYear(), today.getMonth(), today.getDate() + fridayOffset);
    while ((state.snapshot?.periods || []).some((period) => period.dateFrom === toDateKey(friday))) friday.setDate(friday.getDate() + 7);
    const sunday = new Date(friday.getFullYear(), friday.getMonth(), friday.getDate() + 2);
    return { from: toDateKey(friday), to: toDateKey(sunday) };
  };
  $("[data-roster-new-period]").addEventListener("click", () => {
    state.periodFormMode = "create"; state.editingPeriodId = null; state.slotDraft = []; periodForm.reset();
    const range = suggestWeekendRange(); periodForm.elements.date_from.value = range.from; periodForm.elements.date_to.value = range.to;
    rebuildSlotDraft(); render();
  });
  periodForm.addEventListener("submit", async (event) => { event.preventDefault(); const submit = event.submitter; const wasEditing = state.periodFormMode === "edit"; setBusy(submit, true); try { const form = new FormData(periodForm); const title = `${form.get("date_from")} - ${form.get("date_to")}`; await rpc("save_roster_period", { p_period_id: state.editingPeriodId, p_title: title, p_date_from: form.get("date_from"), p_date_to: form.get("date_to"), p_slots: readSlots(), p_requirements: readRequirements() }); state.periodFormMode = null; state.editingPeriodId = null; render(); setMessage(wasEditing ? "排班期間已更新。" : "排班期間已建立並開放填寫。", "success"); } catch (error) { setMessage(`期間儲存失敗：${error.message}`, "error"); } finally { setBusy(submit, false); } });
  const resetRoleForm = () => { state.roleId = null; state.roleFormMode = null; roleForm.reset(); roleForm.elements.is_active.checked = true; };
  $("[data-roster-new-role]").addEventListener("click", () => { resetRoleForm(); state.roleFormMode = "create"; render(); });
  $("[data-roster-close-role]").addEventListener("click", () => { resetRoleForm(); render(); });
  roleForm.addEventListener("submit", async (event) => { event.preventDefault(); const submit = event.submitter; const form = new FormData(roleForm); setBusy(submit, true); try { await rpc("save_roster_role", { p_role_id: state.roleId, p_code: null, p_name: form.get("name"), p_description: form.get("description"), p_min_staff_count: Number(form.get("min_staff_count")), p_max_staff_count: Number(form.get("max_staff_count")), p_sort_order: null, p_is_active: roleForm.elements.is_active.checked }); resetRoleForm(); render(); setMessage("職位已儲存。", "success"); } catch (error) { setMessage(`職位儲存失敗：${error.message}`, "error"); } finally { setBusy(submit, false); } });
  roleList.addEventListener("click", async (event) => {
    const target = event.target.closest("[data-role-id]"); if (!target || target.disabled) return;
    if (target.dataset.rosterAction === "move-role") {
      setBusy(target, true);
      try {
        await rpc("move_roster_role", { p_role_id: target.dataset.roleId, p_direction: target.dataset.direction });
        setMessage("職位順序已更新。", "success");
      } catch (error) {
        setMessage(`職位排序失敗：${error.message}`, "error");
      } finally {
        setBusy(target, false);
      }
      return;
    }
    if (target.dataset.rosterAction === "delete-role") {
      const role = (state.snapshot.roles || []).find((item) => item.id === target.dataset.roleId);
      if (!window.confirm(`確定要刪除「${role?.name || "此職位"}」嗎？\n既有期間會保留職位快照，但此職位設定會移除。`)) return;
      try {
        await rpc("delete_roster_role", { p_role_id: target.dataset.roleId });
        setMessage("職位已刪除。", "success");
      } catch (error) {
        setMessage(`職位刪除失敗：${error.message}`, "error");
      }
      return;
    }
    const role = (state.snapshot.roles || []).find((item) => item.id === target.dataset.roleId);
    if (!role) return;
    state.roleId = role.id;
    ["name", "description", "min_staff_count", "max_staff_count"].forEach((key) => {
      roleForm.elements[key].value = role[{ min_staff_count: "minStaffCount", max_staff_count: "maxStaffCount" }[key] || key] ?? "";
    });
    roleForm.elements.is_active.checked = role.isActive;
    state.roleFormMode = "edit";
    render();
  });
  $("[data-roster-save-matrix]").addEventListener("click", (event) => saveAvailability([...document.querySelectorAll("[data-matrix-slot-id]")].map((select) => ({ shiftSlotId: select.dataset.matrixSlotId, staffId: select.dataset.matrixStaffId, status: select.value })), event.currentTarget));
  $("[data-roster-self-availability]").addEventListener("click", (event) => {
    const action = event.target.closest("[data-roster-action]"); if (!action) return;
    if (action.dataset.rosterAction === "set-self-day") {
      action.closest(".roster-self-day").querySelectorAll("[data-self-slot-id]").forEach((select) => {
        select.value = action.dataset.selfDayValue; select.className = `roster-status-${select.value}`;
      });
      return;
    }
    if (action.dataset.rosterAction !== "save-self") return;
    const staffId = state.snapshot.myStaffId;
    saveAvailability([...document.querySelectorAll("[data-self-slot-id]")].map((select) => ({ shiftSlotId: select.dataset.selfSlotId, staffId, status: select.value })), action);
  });
  ["[data-roster-staff-search]", "[data-roster-status-filter]"].forEach((selector) => $(selector).addEventListener("input", renderMatrix));
  $("[data-roster-column-tools]").addEventListener("click", (event) => { const action = event.target.dataset.rosterAction; if (!action) return; const slotId = event.target.dataset.slotId; const value = action === "clear-column" ? "unselected" : document.querySelector(`[data-column-slot-id="${slotId}"]`).value; document.querySelectorAll(`[data-matrix-slot-id="${slotId}"]`).forEach((select) => { select.value = value; select.className = `roster-status-${value}`; }); });
  $("[data-roster-open]").addEventListener("click", (event) => setPeriodStatus("open", event.currentTarget)); $("[data-roster-close]").addEventListener("click", (event) => setPeriodStatus("draft", event.currentTarget));
  $("[data-roster-generate]").addEventListener("click", async (event) => { if (!window.confirm("依目前可上班狀態產生草稿？手動指定的人員會保留。")) return; setBusy(event.currentTarget, true); try { await rpc("generate_roster_assignments", { p_period_id: activePeriod().id, p_use_standby: $("[data-roster-use-standby]").checked, p_clear_existing: $("[data-roster-clear-draft]").checked }); setMessage("排班草稿已產生。", "success"); } catch (error) { setMessage(`一鍵排班失敗：${error.message}`, "error"); } finally { setBusy(event.currentTarget, false); } });
  $("[data-roster-assignment-list]").addEventListener("click", async (event) => { const action = event.target.dataset.rosterAction; if (!action || !isManager()) return; try { if (action === "delete-assignment") { await rpc("delete_roster_assignment", { p_assignment_id: event.target.dataset.assignmentId }); } else { const assignmentId = action === "save-assignment" ? event.target.dataset.assignmentId : null; const slotId = event.target.dataset.slotId; const requirementId = event.target.dataset.requirementId; const select = assignmentId ? document.querySelector(`[data-assignment-staff-id="${assignmentId}"]`) : null; const staffId = select?.value || null; if (staffId && availabilityFor(slotId, staffId) === "unavailable" && !window.confirm("此員工標示為「否」，仍要手動排入嗎？")) return; await rpc("save_roster_assignment", { p_assignment_id: assignmentId, p_period_id: activePeriod().id, p_shift_slot_id: slotId, p_role_requirement_id: requirementId, p_staff_id: staffId, p_status: staffId ? "assigned" : "pending", p_is_manual: true, p_note: null }); } setMessage("排班草稿已更新。", "success"); } catch (error) { setMessage(`草稿更新失敗：${error.message}`, "error"); } });
  const downloadDayPng = (businessDate) => {
    const daySlots = slots().filter((slot) => slot.businessDate === businessDate).sort((a, b) => a.sortOrder - b.sortOrder);
    const roleRows = requirements().filter((requirement) => requirement.isRequired);
    const canvas = document.createElement("canvas");
    const width = 1600; const margin = 70; const gap = 34; const cardWidth = (width - margin * 2 - gap) / 2;
    const cardHeight = 108 + roleRows.length * 54;
    const rows = Math.ceil(daySlots.length / 2); const height = Math.max(760, 260 + rows * (cardHeight + gap) + 100);
    canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fffaf0"; ctx.fillRect(0, 0, width, height);
    ctx.strokeStyle = "#d8c5a4"; ctx.lineWidth = 2; ctx.strokeRect(24, 24, width - 48, height - 48);
    ctx.fillStyle = "#6f5140"; ctx.font = "600 20px sans-serif"; ctx.textAlign = "center"; ctx.fillText("HEYOTSUKI YADO", width / 2, 72);
    ctx.fillStyle = "#3f3028"; ctx.font = "bold 52px serif"; ctx.fillText("嘿月湯宿", width / 2, 132);
    ctx.fillStyle = "#876a53"; ctx.font = "28px serif"; ctx.fillText(`～ ${formatDate(businessDate)} 營業班表 ～`, width / 2, 178);
    daySlots.forEach((slot, index) => {
      const column = index % 2; const row = Math.floor(index / 2); const x = margin + column * (cardWidth + gap); const y = 230 + row * (cardHeight + gap);
      ctx.fillStyle = "#fffefd"; ctx.strokeStyle = "#d8c5a4"; ctx.lineWidth = 2; ctx.beginPath(); ctx.roundRect(x, y, cardWidth, cardHeight, 20); ctx.fill(); ctx.stroke();
      ctx.fillStyle = "#4a382f"; ctx.font = "bold 29px serif"; ctx.textAlign = "left"; ctx.fillText(`${slot.label}｜${formatTime(slot.startTime)} - ${formatTime(slot.endTime)}`, x + 28, y + 48);
      ctx.strokeStyle = "#e4d8ca"; ctx.beginPath(); ctx.moveTo(x + 28, y + 70); ctx.lineTo(x + cardWidth - 28, y + 70); ctx.stroke();
      roleRows.forEach((requirement, rowIndex) => {
        const members = assignments().filter((item) => item.shiftSlotId === slot.id && item.roleRequirementId === requirement.id && item.status === "assigned").map((item) => staffName(item.staffId)).join("、") || "待定";
        const lineY = y + 108 + rowIndex * 54;
        ctx.fillStyle = "#6a5548"; ctx.font = "24px serif"; ctx.textAlign = "left"; ctx.fillText(`・ ${requirement.roleName}`, x + 28, lineY);
        ctx.fillStyle = members === "待定" ? "#a87520" : "#3f3028"; ctx.font = "bold 24px serif"; ctx.textAlign = "right"; ctx.fillText(members, x + cardWidth - 28, lineY);
        if (rowIndex < roleRows.length - 1) { ctx.strokeStyle = "#eee5db"; ctx.beginPath(); ctx.moveTo(x + 28, lineY + 18); ctx.lineTo(x + cardWidth - 28, lineY + 18); ctx.stroke(); }
      });
    });
    ctx.fillStyle = "#806b5c"; ctx.font = "22px serif"; ctx.textAlign = "center"; ctx.fillText("一湯入月　靜人心宿", width / 2, height - 62);
    const link = document.createElement("a"); link.href = canvas.toDataURL("image/png"); link.download = `heyotsuki-roster-${businessDate}.png`; link.click();
  };
  $("[data-roster-print-preview]").addEventListener("click", async (event) => { const action = event.target.dataset.rosterAction; const businessDate = event.target.dataset.businessDate; if (!action || !businessDate) return; if (action === "copy-date") { try { await navigator.clipboard.writeText(dateSummary(businessDate).join("\n")); setMessage("本日班表文字已複製。", "success"); } catch { setMessage("無法自動複製，請直接選取班表內容。", "error"); } } if (action === "png-date") downloadDayPng(businessDate); });
  window.addEventListener("admin-auth-ready", async (event) => { state.client = event.detail.client; state.accountRole = event.detail.profile?.role || event.detail.role || null; if (!event.detail.can("roster.view") && !event.detail.can("roster.submit")) { denied.hidden = false; return; } state.tab = state.accountRole === "staff" ? "availability" : (event.detail.can("roster.manage") ? "setup" : "availability"); try { await load(); if (isManager()) { periodForm.elements.date_from.value ||= new Date().toISOString().slice(0, 10); periodForm.elements.date_to.value ||= periodForm.elements.date_from.value; rebuildSlotDraft(); renderRequirementEditor(); } access.hidden = false; } catch (error) { access.hidden = false; setMessage(`排班資料讀取失敗：${error.message}`, "error"); } }, { once: true });
})();
