(() => {
  "use strict";

  const SHOPS = {
    menu: "湯宿",
    menu2: "喫茶"
  };

  const state = {
    client: null,
    session: null,
    profile: null,
    shops: [],
    report: null
  };

  const accessPanel = document.querySelector("[data-reports-access]");
  const deniedPanel = document.querySelector("[data-reports-denied]");
  const form = document.querySelector("[data-report-form]");
  const shopSelect = document.querySelector("[data-report-shop]");
  const dateFrom = document.querySelector("[data-report-date-from]");
  const dateTo = document.querySelector("[data-report-date-to]");
  const statusInputs = [...document.querySelectorAll("[data-report-status]")];
  const submitButton = document.querySelector("[data-report-submit]");
  const message = document.querySelector("[data-report-message]");
  const result = document.querySelector("[data-report-result]");
  const summary = document.querySelector("[data-report-summary]");
  const warnings = document.querySelector("[data-report-warnings]");
  const sections = document.querySelector("[data-report-sections]");
  const csvButton = document.querySelector("[data-report-csv]");
  const copyButton = document.querySelector("[data-report-copy]");

  const setMessage = (text, type = "") => {
    message.textContent = text || "";
    message.className = "admin-message";
    if (type) message.classList.add(`is-${type}`);
  };

  const setBusy = (busy) => {
    submitButton.disabled = busy;
    submitButton.textContent = busy ? "產生中…" : "產生報表";
  };

  const formatAmount = (value) =>
    `${Number(value || 0).toLocaleString("en-US")} Gil`;

  const formatDateRange = (range) =>
    range.from === range.to ? range.from : `${range.from} ～ ${range.to}`;

  const selectedStatuses = () =>
    statusInputs.filter((input) => input.checked).map((input) => input.value);

  const appendTextElement = (parent, tag, className, text) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text;
    parent.append(element);
    return element;
  };

  const renderReport = () => {
    const report = state.report;
    result.hidden = !report;
    if (!report) return;

    summary.replaceChildren();
    [
      ["店別", report.shop?.title || SHOPS[report.shop?.key] || report.shop?.key],
      ["日期區間", formatDateRange(report.date_range)],
      ["訂單數", String(report.order_count || 0)],
      ["品項數量", String(report.quantity || 0)],
      ["總金額", formatAmount(report.grand_total)]
    ].forEach(([label, value]) => {
      const card = document.createElement("article");
      card.className = "admin-report-summary-card";
      appendTextElement(card, "span", "", label);
      appendTextElement(card, "strong", "", value);
      summary.append(card);
    });

    const reportWarnings = Array.isArray(report.warnings)
      ? report.warnings
      : [];
    warnings.replaceChildren();
    warnings.hidden = reportWarnings.length === 0;
    reportWarnings.forEach((warning) =>
      appendTextElement(warnings, "p", "", warning)
    );

    sections.replaceChildren();
    const reportSections = Array.isArray(report.sections)
      ? report.sections
      : [];
    if (!reportSections.length) {
      appendTextElement(sections, "p", "admin-empty", "此條件沒有可統計的訂單。");
      return;
    }

    reportSections.forEach((section) => {
      const card = document.createElement("article");
      card.className = "admin-report-section";
      const heading = document.createElement("div");
      heading.className = "admin-report-section-heading";
      appendTextElement(heading, "h3", "", section.section_title);
      appendTextElement(
        heading,
        "strong",
        "",
        formatAmount(section.subtotal)
      );
      card.append(heading);

      const table = document.createElement("div");
      table.className = "admin-report-item-list";
      (section.items || []).forEach((item) => {
        const row = document.createElement("div");
        row.className = "admin-report-item";
        appendTextElement(row, "span", "", item.item_name);
        appendTextElement(row, "span", "", `× ${item.quantity}`);
        appendTextElement(row, "strong", "", formatAmount(item.subtotal));
        table.append(row);
      });
      card.append(table);
      sections.append(card);
    });
  };

  const loadPermissions = async () => {
    if (["owner", "admin"].includes(state.profile.role)) {
      state.shops = Object.keys(SHOPS);
      return;
    }
    const { data, error } = await state.client
      .from("admin_shop_permissions")
      .select("shop_key, can_view_orders")
      .eq("user_id", state.session.user.id)
      .eq("can_view_orders", true);
    if (error) throw error;
    state.shops = (data || [])
      .map((row) => row.shop_key)
      .filter((shopKey) =>
        Object.prototype.hasOwnProperty.call(SHOPS, shopKey)
      );
  };

  const taipeiToday = () => {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Asia/Taipei",
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).formatToParts(new Date());
    const values = Object.fromEntries(
      parts.map((part) => [part.type, part.value])
    );
    return `${values.year}-${values.month}-${values.day}`;
  };

  const loadDefaultBusinessDate = async () => {
    const shopKey = shopSelect.value;
    if (!shopKey) return;
    setMessage("正在取得目前營業日…");
    const { data, error } = await state.client.rpc(
      "get_order_report_default_business_date",
      { p_shop_key: shopKey }
    );
    const fallback = taipeiToday();
    const businessDate = error || !data ? fallback : data;
    dateFrom.value = businessDate;
    dateTo.value = businessDate;
    setMessage(error ? "無法取得營業日，已使用台灣今日日期。" : "");
  };

  const generateReport = async () => {
    const statuses = selectedStatuses();
    if (!statuses.length) {
      setMessage("請至少選擇一個訂單狀態。", "error");
      return;
    }
    if (!dateFrom.value || !dateTo.value) {
      setMessage("請選擇起始與結束營業日。", "error");
      return;
    }
    if (dateTo.value < dateFrom.value) {
      setMessage("結束營業日不可早於起始營業日。", "error");
      return;
    }

    setBusy(true);
    setMessage("正在產生報表…");
    const { data, error } = await state.client.rpc("get_order_sales_report", {
      p_shop_key: shopSelect.value,
      p_business_date_from: dateFrom.value,
      p_business_date_to: dateTo.value,
      p_statuses: statuses
    });
    setBusy(false);
    if (error) {
      console.error("報表產生失敗", error);
      setMessage(`報表產生失敗：${error.message}`, "error");
      return;
    }
    state.report = data;
    renderReport();
    setMessage("報表已產生。", "success");
  };

  const protectSpreadsheetCell = (value) => {
    const text = String(value ?? "");
    return /^[=+\-@]/.test(text) ? `'${text}` : text;
  };

  const csvCell = (value) =>
    `"${protectSpreadsheetCell(value).replace(/"/g, '""')}"`;

  const buildCsv = () => {
    const report = state.report;
    const rows = [["層級", "大項", "小項", "數量", "金額", "備註"]];
    rows.push(["總計", "", "", report.quantity || 0, report.grand_total || 0, ""]);
    (report.sections || []).forEach((section) => {
      rows.push([
        "大項",
        section.section_title,
        "",
        section.quantity || 0,
        section.subtotal || 0,
        ""
      ]);
      (section.items || []).forEach((item) => {
        rows.push([
          "小項",
          section.section_title,
          item.item_name,
          item.quantity || 0,
          item.subtotal || 0,
          ""
        ]);
      });
    });
    (report.warnings || []).forEach((warning) => {
      rows.push(["警告", "", "", "", "", warning]);
    });
    return rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
  };

  const exportCsv = () => {
    if (!state.report) return;
    const csv = `\uFEFF${buildCsv()}`;
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    const range = state.report.date_range;
    const datePart =
      range.from === range.to ? range.from : `${range.from}-${range.to}`;
    link.href = url;
    link.download =
      `heyotsuki-order-report-${state.report.shop.key}-${datePart}.csv`;
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  };

  const buildTextSummary = () => {
    const report = state.report;
    const lines = [
      "嘿月湯宿 點餐銷售報表",
      `店別：${report.shop?.title || SHOPS[report.shop?.key] || report.shop?.key}`,
      `日期：${formatDateRange(report.date_range)}`,
      `訂單數：${report.order_count || 0}`,
      `總金額：${formatAmount(report.grand_total)}`,
      ""
    ];
    (report.sections || []).forEach((section) => {
      lines.push(`【${section.section_title}】${formatAmount(section.subtotal)}`, "");
      (section.items || []).forEach((item) => {
        lines.push(
          `• ${item.item_name} × ${item.quantity}：${formatAmount(item.subtotal)}`
        );
      });
      lines.push("");
    });
    return lines.join("\n").trim();
  };

  const copySummary = async () => {
    if (!state.report) return;
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
    setMessage("文字摘要已複製。", "success");
  };

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    generateReport();
  });
  shopSelect.addEventListener("change", async () => {
    state.report = null;
    renderReport();
    await loadDefaultBusinessDate();
  });
  csvButton.addEventListener("click", exportCsv);
  copyButton.addEventListener("click", copySummary);

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
      shopSelect.replaceChildren(
        ...state.shops.map((shopKey) => {
          const option = document.createElement("option");
          option.value = shopKey;
          option.textContent = SHOPS[shopKey];
          return option;
        })
      );
      accessPanel.hidden = false;
      await loadDefaultBusinessDate();
    } catch (error) {
      console.error("報表頁初始化失敗", error);
      accessPanel.hidden = false;
      setMessage(`報表頁載入失敗：${error.message}`, "error");
    }
  });
})();
