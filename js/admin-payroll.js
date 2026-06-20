(() => {
  "use strict";

  const SHOPS = {
    menu: "湯宿菜單",
    menu2: "喫茶菜單"
  };

  const SOURCE_LABELS = {
    food_pool: "公池平均",
    direct_staff: "指定員工",
    dance_split: "舞蹈分配",
    manual_adjustment: "調整項",
    unassigned_direct_staff: "待分配",
    unassigned_dance_split: "待分配舞蹈"
  };

  const state = {
    client: null,
    profile: null,
    snapshot: null,
    directStaffIds: new Set()
  };

  const accessPanel = document.querySelector("[data-payroll-access]");
  const deniedPanel = document.querySelector("[data-payroll-denied]");
  const form = document.querySelector("[data-payroll-form]");
  const shopSelect = document.querySelector("[data-payroll-shop]");
  const dateInput = document.querySelector("[data-payroll-date]");
  const loadButton = document.querySelector("[data-payroll-load]");
  const message = document.querySelector("[data-payroll-message]");
  const workspace = document.querySelector("[data-payroll-workspace]");
  const summary = document.querySelector("[data-payroll-summary]");
  const poolMembers = document.querySelector("[data-payroll-pool-members]");
  const savePoolButton = document.querySelector("[data-payroll-save-pool]");
  const poolSelectAllButton = document.querySelector("[data-payroll-pool-select-all]");
  const poolClearButton = document.querySelector("[data-payroll-pool-clear]");
  const danceForm = document.querySelector("[data-dance-session-form]");
  const danceItemSelect = document.querySelector("[data-dance-item]");
  const danceAmount = document.querySelector("[data-dance-amount]");
  const danceSessions = document.querySelector("[data-dance-sessions]");
  const danceItemSummary = document.querySelector("[data-dance-item-summary]");
  const danceAutoCreateButton = document.querySelector("[data-dance-auto-create]");
  const regenerateButton = document.querySelector("[data-payroll-regenerate]");
  const csvButton = document.querySelector("[data-payroll-csv]");
  const copyButton = document.querySelector("[data-payroll-copy]");
  const lockButton = document.querySelector("[data-payroll-lock]");
  const unassigned = document.querySelector("[data-payroll-unassigned]");
  const totals = document.querySelector("[data-payroll-totals]");
  const entries = document.querySelector("[data-payroll-entries]");
  const adjustmentForm = document.querySelector("[data-payroll-adjustment-form]");
  const adjustmentStaff = document.querySelector("[data-adjustment-staff]");
  const adjustmentAmount = document.querySelector("[data-adjustment-amount]");
  const adjustmentDescription = document.querySelector("[data-adjustment-description]");

  const setMessage = (text, type = "") => {
    message.textContent = text || "";
    message.className = "admin-message";
    if (type) message.classList.add(`is-${type}`);
  };

  const setBusy = (button, busy, busyText = "處理中...") => {
    if (!button) return;
    if (!button.dataset.defaultText) button.dataset.defaultText = button.textContent;
    button.disabled = busy;
    button.textContent = busy ? busyText : button.dataset.defaultText;
  };

  const formatAmount = (value) =>
    `${Number(value || 0).toLocaleString("en-US")} Gil`;

  const append = (parent, tag, className, text) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text;
    parent.append(element);
    return element;
  };

  const protectSpreadsheetCell = (value) => {
    const text = String(value ?? "");
    return /^[=+\-@]/.test(text) ? `'${text}` : text;
  };

  const csvCell = (value) =>
    `"${protectSpreadsheetCell(value).replace(/"/g, '""')}"`;

  const shortId = (value) => String(value || "").slice(0, 8);

  const getStatusLabel = (status) => {
    if (status === "locked") return "已鎖定";
    if (status === "draft") return "草稿";
    if (status === "active") return "";
    if (status === "void") return "作廢";
    return status || "";
  };

  const getEntryDisplayName = (entry) =>
    entry.sourceItemName || SOURCE_LABELS[entry.sourceType] || "未命名";

  const getDanceSessionCountByItem = () => {
    const countByItem = new Map();
    (state.snapshot?.danceSessions || [])
      .filter((session) => session.status === "active")
      .forEach((session) => {
      countByItem.set(
        session.orderItemId,
        (countByItem.get(session.orderItemId) || 0) + 1
      );
    });
    return countByItem;
  };

  const getActiveDanceSessions = () =>
    (state.snapshot?.danceSessions || []).filter((session) => session.status === "active");

  const getNextDanceSessionNo = (orderItemId) => {
    const used = new Set(
      getActiveDanceSessions()
        .filter((session) => session.orderItemId === orderItemId)
        .map((session) => Number(session.sessionNo))
    );
    let next = 1;
    while (used.has(next)) next += 1;
    return next;
  };

  const isLocked = () => state.snapshot?.batch?.status === "locked";

  const loadDirectStaffIds = async (batchId) => {
    state.directStaffIds = new Set();
    if (!batchId) return;
    const { data, error } = await state.client.rpc(
      "get_payroll_direct_staff_ids",
      { p_batch_id: batchId }
    );
    if (error) {
      setMessage(`讀取當日指名員工失敗：${error.message}`, "error");
      return;
    }
    state.directStaffIds = new Set(data || []);
  };

  const setSnapshot = async (snapshot, reloadDirectStaffIds = false) => {
    state.snapshot = snapshot;
    if (reloadDirectStaffIds) {
      await loadDirectStaffIds(snapshot?.batch?.id);
    }
  };

  const loadDefaultDate = async () => {
    const { data, error } = await state.client.rpc(
      "get_payroll_default_business_date",
      { p_shop_key: shopSelect.value }
    );
    if (!error && data) dateInput.value = data;
  };

  const loadBatch = async () => {
    setBusy(loadButton, true);
    setMessage("讀取薪資批次中...");
    const { data, error } = await state.client.rpc(
      "create_or_get_payroll_batch",
      {
        p_shop_key: shopSelect.value,
        p_business_date: dateInput.value
      }
    );
    setBusy(loadButton, false);
    if (error) {
      setMessage(`薪資批次讀取失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data, true);
    workspace.hidden = false;
    setMessage("");
    render();
  };

  const refreshBatch = async () => {
    if (!state.snapshot?.batch?.id) return;
    const { data, error } = await state.client.rpc(
      "get_payroll_batch_snapshot",
      { p_batch_id: state.snapshot.batch.id }
    );
    if (error) {
      setMessage(`薪資批次重新讀取失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data, true);
    render();
  };

  const renderSummary = () => {
    const batch = state.snapshot.batch;
    summary.replaceChildren();
    [
      ["店別", SHOPS[batch.shopKey] || batch.shopKey],
      ["營業日", batch.businessDate],
      ["狀態", batch.status === "locked" ? "已鎖定" : "草稿"],
      ["未分配", `${state.snapshot.unassigned?.length || 0} 筆`]
    ].forEach(([label, value]) => {
      const card = document.createElement("article");
      card.className = "admin-report-summary-card";
      append(card, "span", "", label);
      append(card, "strong", "", value);
      summary.append(card);
    });
  };

  const renderPoolMembers = () => {
    const selected = new Set(
      (state.snapshot.poolMembers || []).map((member) => member.staffId)
    );
    poolMembers.replaceChildren();
    (state.snapshot.staffOptions || [])
      .filter((staff) => !state.directStaffIds.has(staff.id))
      .forEach((staff) => {
      const label = document.createElement("label");
      label.className = "checkbox-field";
      label.dataset.staffSearchName = String(staff.name || "").toLowerCase();
      const input = document.createElement("input");
      input.type = "checkbox";
      input.value = staff.id;
      input.dataset.poolStaffId = staff.id;
      input.checked = selected.has(staff.id);
      input.disabled = isLocked();
      const text = document.createElement("span");
      text.textContent = `${staff.name}${staff.isVisible ? "" : "（隱藏）"}`;
      label.append(input, text);
      poolMembers.append(label);
    });
    savePoolButton.disabled = isLocked();
    poolSelectAllButton.disabled = isLocked();
    poolClearButton.disabled = isLocked();
    danceAutoCreateButton.disabled = isLocked();
  };

  const renderDanceItems = () => {
    danceItemSelect.replaceChildren();
    const countByItem = getDanceSessionCountByItem();
    const danceItems = state.snapshot.danceItems || [];
    const missingQuantityOne = danceItems.filter(
      (item) => Number(item.quantity) === 1 && !countByItem.has(item.orderItemId)
    ).length;
    const manualItems = danceItems.filter(
      (item) => Number(item.quantity) !== 1 && !countByItem.has(item.orderItemId)
    ).length;
    const createdItems = danceItems.filter((item) =>
      countByItem.has(item.orderItemId)
    ).length;
    if (danceItemSummary) {
      danceItemSummary.textContent =
        `舞蹈品項 ${danceItems.length} 筆；未建數量 1：${missingQuantityOne} 筆；需手動處理：${manualItems} 筆；已建：${createdItems} 筆。`;
    }
    danceItems.forEach((item) => {
      const option = document.createElement("option");
      const sessionCount = countByItem.get(item.orderItemId) || 0;
      const status = sessionCount ? `已建 ${sessionCount} 場` : "未建";
      option.value = item.orderItemId;
      option.textContent =
        `#${shortId(item.orderItemId)}｜${item.customerName}｜${item.itemName}｜數量 ${item.quantity}｜${formatAmount(item.amount)}｜${status}`;
      option.dataset.amount = item.amount;
      danceItemSelect.append(option);
    });
    if (danceItemSelect.options[0]) {
      danceAmount.value = danceItemSelect.options[0].dataset.amount || "0";
    }
    [...danceForm.elements].forEach((element) => {
      element.disabled = isLocked();
    });
  };

  const renderDanceSessions = () => {
    danceSessions.replaceChildren();
    const sessions = getActiveDanceSessions();
    if (!sessions.length) {
      append(danceSessions, "p", "admin-empty", "尚未建立舞蹈場次。");
      return;
    }
    const itemById = new Map(
      (state.snapshot.danceItems || []).map((item) => [item.orderItemId, item])
    );
    sessions.forEach((session) => {
      const item = itemById.get(session.orderItemId);
      const sessionStatusLabel = getStatusLabel(session.status);
      const participantNames = (session.participants || [])
        .map((participant) => participant.name)
        .join("、");
      const card = document.createElement("article");
      card.className = "payroll-row";
      append(
        card,
        "strong",
        "",
        `#${shortId(session.orderItemId)}｜${item?.customerName || "訂單"}｜${item?.itemName || "舞蹈品項"}｜場次 ${session.sessionNo}｜${formatAmount(session.amount)}${sessionStatusLabel ? `｜${sessionStatusLabel}` : ""}`
      );
      append(card, "p", "field-help", `參與：${participantNames || "尚未設定"}`);
      if (!isLocked()) {
        const details = document.createElement("details");
        details.className = "payroll-inner-details";
        const summary = document.createElement("summary");
        summary.textContent = "調整參與者";
        details.append(summary);
        const participantGrid = document.createElement("div");
        participantGrid.className = "admin-option-staff-grid";
        participantGrid.dataset.sessionParticipants = session.id;
        (state.snapshot.staffOptions || []).forEach((staff) => {
          const label = document.createElement("label");
          label.className = "checkbox-field";
          label.dataset.staffSearchName = String(staff.name || "").toLowerCase();
          const input = document.createElement("input");
          input.type = "checkbox";
          input.value = staff.id;
          input.checked = (session.participants || []).some(
            (participant) => participant.staffId === staff.id
          );
          const text = document.createElement("span");
          text.textContent = staff.name;
          label.append(input, text);
          participantGrid.append(label);
        });
        const tools = document.createElement("div");
        tools.className = "payroll-participant-tools";
        const selectAll = document.createElement("button");
        selectAll.className = "admin-button admin-button-secondary";
        selectAll.type = "button";
        selectAll.dataset.selectParticipants = session.id;
        selectAll.dataset.checked = "true";
        selectAll.textContent = "全選";
        const clearAll = document.createElement("button");
        clearAll.className = "admin-button admin-button-secondary";
        clearAll.type = "button";
        clearAll.dataset.selectParticipants = session.id;
        clearAll.dataset.checked = "false";
        clearAll.textContent = "清空";
        tools.append(selectAll, clearAll);
        const deleteButton = document.createElement("button");
        deleteButton.className = "admin-button admin-button-secondary";
        deleteButton.type = "button";
        deleteButton.dataset.deleteSession = session.id;
        deleteButton.textContent = "刪除場次";
        const button = document.createElement("button");
        button.className = "admin-button admin-button-secondary";
        button.type = "button";
        button.dataset.saveParticipants = session.id;
        button.textContent = "儲存參與者";
        details.append(tools, participantGrid, button, deleteButton);
        card.append(details);
      }
      danceSessions.append(card);
    });
  };

  const renderEntries = () => {
    unassigned.replaceChildren();
    const unassignedEntries = state.snapshot.unassigned || [];
    if (unassignedEntries.length) {
      append(unassigned, "h4", "", "待分配項目");
      unassignedEntries.forEach((entry) => {
        append(
          unassigned,
          "p",
          "admin-message is-error",
          `${SOURCE_LABELS[entry.sourceType] || entry.sourceType}：${getEntryDisplayName(entry)} / ${formatAmount(entry.amount)}`
        );
      });
    }

    totals.replaceChildren();
    append(totals, "h4", "", "員工合計");
    const totalsList = state.snapshot.totalsByStaff || [];
    if (!totalsList.length) append(totals, "p", "admin-empty", "尚未產生薪資明細。");
    totalsList.forEach((row) => {
      append(totals, "p", "payroll-total-line", `${row.staffName}：${formatAmount(row.amount)}`);
    });

    entries.replaceChildren();
    const table = document.createElement("table");
    table.className = "admin-table";
    const head = document.createElement("thead");
    const headRow = document.createElement("tr");
    ["類型", "員工", "來源", "金額"].forEach((label) =>
      append(headRow, "th", "", label)
    );
    head.append(headRow);
    const body = document.createElement("tbody");
    (state.snapshot.entries || []).forEach((entry) => {
      const row = document.createElement("tr");
      [
        SOURCE_LABELS[entry.sourceType] || entry.sourceType,
        entry.staffName || "待分配",
        getEntryDisplayName(entry),
        formatAmount(entry.amount)
      ].forEach((text) => append(row, "td", "", text));
      body.append(row);
    });
    table.append(head, body);
    entries.append(table);
  };

  const renderAdjustmentOptions = () => {
    adjustmentStaff.replaceChildren();
    (state.snapshot.staffOptions || []).forEach((staff) => {
      const option = document.createElement("option");
      option.value = staff.id;
      option.textContent = staff.name;
      adjustmentStaff.append(option);
    });
  };

  const render = () => {
    renderSummary();
    renderPoolMembers();
    renderDanceItems();
    renderDanceSessions();
    renderEntries();
    renderAdjustmentOptions();
    regenerateButton.disabled = isLocked();
    lockButton.disabled = isLocked();
  };

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    loadBatch();
  });

  shopSelect.addEventListener("change", loadDefaultDate);
  danceItemSelect.addEventListener("change", () => {
    danceAmount.value =
      danceItemSelect.selectedOptions[0]?.dataset.amount || "0";
  });

  const setPoolMemberChecks = (checked) => {
    poolMembers.querySelectorAll("[data-pool-staff-id]").forEach((input) => {
      input.checked = checked;
    });
  };

  poolSelectAllButton.addEventListener("click", () => setPoolMemberChecks(true));
  poolClearButton.addEventListener("click", () => setPoolMemberChecks(false));

  savePoolButton.addEventListener("click", async () => {
    const selectedIds = [
      ...poolMembers.querySelectorAll("[data-pool-staff-id]:checked")
    ].map((input) => input.value);
    setBusy(savePoolButton, true);
    const { data, error } = await state.client.rpc(
      "set_payroll_pool_members",
      {
        p_batch_id: state.snapshot.batch.id,
        p_staff_ids: selectedIds
      }
    );
    setBusy(savePoolButton, false);
    if (error) {
      setMessage(`公池成員儲存失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data);
    setMessage("公池成員已儲存。", "success");
    render();
  });

  danceForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const selectedItem = danceItemSelect.selectedOptions[0];
    const nextSessionNo = getNextDanceSessionNo(danceItemSelect.value);
    const { data, error } = await state.client.rpc("upsert_dance_session", {
      p_batch_id: state.snapshot.batch.id,
      p_order_item_id: danceItemSelect.value,
      p_session_no: nextSessionNo,
      p_amount: Number(danceAmount.value),
      p_status: "active"
    });
    if (error) {
      setMessage(`舞蹈場次儲存失敗：${error.message}`, "error");
      return;
    }
      await setSnapshot(data);
    setMessage(`已新增 ${selectedItem?.textContent || "舞蹈品項"} 的第 ${nextSessionNo} 場。`, "success");
    render();
  });

  danceSessions.addEventListener("click", async (event) => {
    const toggleButton = event.target.closest("[data-select-participants]");
    if (toggleButton) {
      const panel = danceSessions.querySelector(
        `[data-session-participants="${toggleButton.dataset.selectParticipants}"]`
      );
      if (!panel) return;
      const checked = toggleButton.dataset.checked === "true";
      panel.querySelectorAll("input[type='checkbox']").forEach((input) => {
        input.checked = checked;
      });
      return;
    }
    const deleteButton = event.target.closest("[data-delete-session]");
    if (deleteButton) {
      const session = getActiveDanceSessions().find(
        (item) => item.id === deleteButton.dataset.deleteSession
      );
      if (!session) return;
      if (!window.confirm("確定刪除此舞蹈場次？刪除後不會列入薪資計算。")) return;
      const { data, error } = await state.client.rpc("upsert_dance_session", {
        p_batch_id: state.snapshot.batch.id,
        p_order_item_id: session.orderItemId,
        p_session_no: Number(session.sessionNo),
        p_amount: Number(session.amount),
        p_status: "void"
      });
      if (error) {
        setMessage(`舞蹈場次刪除失敗：${error.message}`, "error");
        return;
      }
      await setSnapshot(data);
      setMessage("舞蹈場次已刪除。", "success");
      render();
      return;
    }
    const button = event.target.closest("[data-save-participants]");
    if (!button) return;
    const select = danceSessions.querySelector(
      `[data-session-participants="${button.dataset.saveParticipants}"]`
    );
    const selectedIds = [
      ...select.querySelectorAll("input[type='checkbox']:checked")
    ].map((input) => input.value);
    const { data, error } = await state.client.rpc(
      "set_dance_session_participants",
      {
        p_session_id: button.dataset.saveParticipants,
        p_staff_ids: selectedIds
      }
    );
    if (error) {
      setMessage(`舞蹈參與者儲存失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data);
    setMessage("舞蹈參與者已儲存。", "success");
    render();
  });

  danceAutoCreateButton.addEventListener("click", async () => {
    const targets = (state.snapshot.danceItems || []).filter(
      (item) => Number(item.quantity) === 1 && !getDanceSessionCountByItem().has(item.orderItemId)
    );
    if (!targets.length) {
      setMessage("沒有可批次建立的數量 1 舞蹈品項。", "error");
      return;
    }

    setBusy(danceAutoCreateButton, true, "建立中...");
    for (const item of targets) {
      const nextSessionNo = getNextDanceSessionNo(item.orderItemId);
      const sessionResult = await state.client.rpc("upsert_dance_session", {
        p_batch_id: state.snapshot.batch.id,
        p_order_item_id: item.orderItemId,
        p_session_no: nextSessionNo,
        p_amount: Number(item.amount),
        p_status: "active"
      });
      if (sessionResult.error) {
        setBusy(danceAutoCreateButton, false);
        setMessage(`自動建立舞蹈場次失敗：${sessionResult.error.message}`, "error");
        return;
      }
      await setSnapshot(sessionResult.data);
    }
    setBusy(danceAutoCreateButton, false);
    setMessage(`已批次建立 ${targets.length} 筆空舞蹈場次，請逐場設定參與者。`, "success");
    render();
  });

  regenerateButton.addEventListener("click", async () => {
    setBusy(regenerateButton, true);
    const { data, error } = await state.client.rpc(
      "regenerate_payroll_entries",
      { p_batch_id: state.snapshot.batch.id }
    );
    setBusy(regenerateButton, false);
    if (error) {
      setMessage(`薪資明細重算失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data);
    setMessage("薪資明細已重算。", "success");
    render();
  });

  const buildPayrollCsv = () => {
    const batch = state.snapshot.batch;
    const rows = [
      ["類型", "員工", "來源", "金額", "說明", "營業日", "店別"]
    ];
    rows.push([
      "批次",
      "",
      batch.status === "locked" ? "已鎖定" : "草稿",
      "",
      "",
      batch.businessDate,
      SHOPS[batch.shopKey] || batch.shopKey
    ]);
    (state.snapshot.totalsByStaff || []).forEach((row) => {
      rows.push(["員工合計", row.staffName, "", row.amount || 0, "", batch.businessDate, SHOPS[batch.shopKey] || batch.shopKey]);
    });
    (state.snapshot.entries || []).forEach((entry) => {
      rows.push([
        SOURCE_LABELS[entry.sourceType] || entry.sourceType,
        entry.staffName || "待分配",
        getEntryDisplayName(entry),
        entry.amount || 0,
        "",
        batch.businessDate,
        SHOPS[batch.shopKey] || batch.shopKey
      ]);
    });
    return rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
  };

  const exportCsv = () => {
    if (!state.snapshot) return;
    const batch = state.snapshot.batch;
    const csv = `\uFEFF${buildPayrollCsv()}`;
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `heyotsuki-payroll-${batch.shopKey}-${batch.businessDate}.csv`;
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  };

  const buildTextSummary = () => {
    const batch = state.snapshot.batch;
    const lines = [
      "嘿月湯宿 薪資分潤結算",
      `店別：${SHOPS[batch.shopKey] || batch.shopKey}`,
      `營業日：${batch.businessDate}`,
      `狀態：${batch.status === "locked" ? "已鎖定" : "草稿"}`,
      "",
      "員工合計："
    ];
    (state.snapshot.totalsByStaff || []).forEach((row) => {
      lines.push(`- ${row.staffName}：${formatAmount(row.amount)}`);
    });
    const unassignedEntries = state.snapshot.unassigned || [];
    if (unassignedEntries.length) {
      lines.push("", "待分配：");
      unassignedEntries.forEach((entry) => {
        lines.push(`- ${getEntryDisplayName(entry)}：${formatAmount(entry.amount)}`);
      });
    }
    return lines.join("\n").trim();
  };

  const copySummary = async () => {
    if (!state.snapshot) return;
    const text = buildTextSummary();
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.append(textarea);
      textarea.select();
      document.execCommand("copy");
      textarea.remove();
    }
    setMessage("薪資摘要已複製。", "success");
  };

  csvButton.addEventListener("click", exportCsv);
  copyButton.addEventListener("click", copySummary);

  lockButton.addEventListener("click", async () => {
    if (!window.confirm("鎖定後不可重算或修改，只能新增調整項。確定鎖定？")) return;
    setBusy(lockButton, true);
    const { data, error } = await state.client.rpc("lock_payroll_batch", {
      p_batch_id: state.snapshot.batch.id
    });
    setBusy(lockButton, false);
    if (error) {
      setMessage(`批次鎖定失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data);
    setMessage("薪資批次已鎖定。", "success");
    render();
  });

  adjustmentForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const { data, error } = await state.client.rpc(
      "create_payroll_adjustment",
      {
        p_batch_id: state.snapshot.batch.id,
        p_staff_id: adjustmentStaff.value,
        p_amount: Number(adjustmentAmount.value),
        p_description: adjustmentDescription.value.trim()
      }
    );
    if (error) {
      setMessage(`調整項新增失敗：${error.message}`, "error");
      return;
    }
    await setSnapshot(data);
    adjustmentForm.reset();
    setMessage("調整項已新增。", "success");
    render();
  });

  window.addEventListener("admin-auth-ready", async (event) => {
    state.client = event.detail.client;
    state.profile = event.detail.profile;
    if (!["owner", "admin"].includes(state.profile.role)) {
      deniedPanel.hidden = false;
      return;
    }
    accessPanel.hidden = false;
    await loadDefaultDate();
  }, { once: true });
})();
