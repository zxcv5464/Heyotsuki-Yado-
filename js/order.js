(() => {
  const client = window.SUPABASE_CLIENT;
  const shopKey = document.body.dataset.shopKey;
  const menuRoot = document.querySelector("[data-order-menu]");
  const summaryRoot = document.querySelector("[data-order-summary]");
  const form = document.querySelector("[data-order-form]");
  const message = document.querySelector("[data-order-message]");
  const title = document.querySelector("[data-order-title]");
  const description = document.querySelector("[data-order-description]");
  const submitButton = form?.querySelector('button[type="submit"]');
  const customerLabel = document.querySelector("[data-order-customer-label]");
  const contactField = document.querySelector("[data-order-contact-field]");
  const contactRequired = document.querySelector("[data-order-contact-required]");
  const noteField = document.querySelector("[data-order-note-field]");
  const noteRequired = document.querySelector("[data-order-note-required]");
  const timeField = document.querySelector("[data-order-time-field]");
  const timeLabel = document.querySelector("[data-order-time-label]");
  const timeRequired = document.querySelector("[data-order-time-required]");
  const timeSelect = document.querySelector("[data-order-time-select]");
  const closedPanel = document.querySelector("[data-order-closed-panel]");
  const closedMessage = document.querySelector("[data-order-closed-message]");

  let menuData = null;
  let cartLines = [];

  const setMessage = (text, type = "error") => {
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const setBusy = (busy) => {
    submitButton.disabled =
      busy || menuData?.shop?.order_accepting !== true;
    submitButton.textContent = busy ? "送出中..." : "送出點餐";
  };

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  const createLineId = () =>
    window.crypto?.randomUUID?.() ||
    `line-${Date.now()}-${Math.random().toString(16).slice(2)}`;

  const parsePrice = (price) => {
    const digits = String(price || "").replace(/[^\d]/g, "");
    return digits ? Number(digits) : null;
  };

  const getStaffOptions = (item) => item.staff_options || [];
  const getOrderOptions = (item) => item.order_options || [];
  const getStaffDisplayName = (staff) =>
    String(staff?.display_name || staff?.option_label || "").trim();
  const getItemLines = (itemId) =>
    cartLines.filter((line) => line.menuItemId === itemId);
  const getItemQuantity = (itemId) =>
    getItemLines(itemId).reduce((total, line) => total + line.quantity, 0);
  const allowsItemNote = (item) => item.allow_item_note !== false;
  const isAcceptingOrders = () =>
    menuData?.shop?.order_accepting === true;

  const getSelectedOptions = (line) => {
    const ids = new Set(line.selectedOptionIds || []);
    return getOrderOptions(line.item).filter((option) => ids.has(option.id));
  };

  const getEligibleStaffOptions = (item, selectedOptionIds = []) => {
    let staff = getStaffOptions(item);
    getOrderOptions(item)
      .filter(
        (option) =>
          selectedOptionIds.includes(option.id) &&
          option.requires_staff_capability
      )
      .forEach((option) => {
        const eligible = new Set(option.eligible_staff_ids || []);
        staff = staff.filter((entry) => eligible.has(entry.staff_id));
      });
    return staff;
  };

  const formatDelta = (option) =>
    option.price_delta_text ||
    `${Number(option.price_delta_amount) >= 0 ? "+" : ""}${Number(
      option.price_delta_amount || 0
    ).toLocaleString("en-US")} Gil`;

  const isSoldOut = (item) =>
    item.remaining_quantity != null &&
    Number(item.remaining_quantity) <= 0;

  const remainingForCart = (item) => {
    if (item.remaining_quantity == null) return null;
    return Math.max(
      Number(item.remaining_quantity) - getItemQuantity(item.id),
      0
    );
  };

  const notifyOrderDiscord = async (orderId) => {
    if (!orderId || !client?.functions) {
      console.warn(
        "Discord order notification skipped: missing order id.",
        orderId
      );
      return false;
    }
    try {
      const { data, error } = await client.functions.invoke(
        "notify-order-discord",
        {
          body: { order_id: orderId }
        }
      );
      if (error || data?.status === "failed") {
        console.warn(
          "Discord order notification failed.",
          error || data
        );
        return false;
      }
      return true;
    } catch (error) {
      console.warn("Discord order notification failed.", error);
      return false;
    }
  };

  const getSubmittedOrderId = (data) => {
    const row = Array.isArray(data) ? data[0] : data;
    if (typeof row === "string") return row;
    return row?.order_id || row?.id || null;
  };

  const applyShopFields = () => {
    const shop = menuData.shop;
    const contactVisible = shop.order_contact_visible !== false;
    const noteVisible = shop.order_note_visible !== false;
    const timeVisible = shop.order_time_visible !== false;
    const accepting = shop.order_accepting === true;
    const slots = Array.isArray(shop.order_time_slots)
      ? shop.order_time_slots
      : [];
    customerLabel.textContent = shop.order_customer_label || "角色 ID";
    timeLabel.textContent = shop.order_time_label || "用餐時間";
    timeSelect.required = Boolean(
      timeVisible && shop.order_time_required
    );
    timeRequired.hidden = !(
      timeVisible && shop.order_time_required
    );
    timeSelect.replaceChildren();
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = shop.order_time_required
      ? "請選擇時間"
      : "未指定";
    timeSelect.append(placeholder);
    slots.forEach((slot) => {
      const option = document.createElement("option");
      option.value = String(slot);
      option.textContent = String(slot);
      timeSelect.append(option);
    });
    timeField.hidden = !timeVisible || !accepting;
    timeSelect.disabled = !timeVisible || !accepting;
    closedPanel.hidden = accepting;
    closedMessage.textContent =
      shop.order_closed_reason ||
      "目前非營業時間，暫不開放點餐。";

    contactField.hidden = !contactVisible;
    contactField.querySelector("input").required =
      Boolean(contactVisible && shop.order_contact_required);
    contactRequired.hidden = !(
      contactVisible && shop.order_contact_required
    );

    noteField.hidden = !noteVisible;
    noteField.querySelector("textarea").required =
      Boolean(noteVisible && shop.order_note_required);
    noteRequired.hidden = !(
      noteVisible && shop.order_note_required
    );
    submitButton.disabled =
      !accepting ||
      (
        timeVisible &&
        Boolean(shop.order_time_required) &&
        slots.length === 0
      );
  };

  const addGeneralLine = (
    item,
    quantity,
    itemNote,
    selectedOptionIds = []
  ) => {
    const existing = getItemLines(item.id)[0];
    if (existing) {
      existing.quantity = quantity;
      existing.itemNote = allowsItemNote(item) ? itemNote : "";
      existing.selectedOptionIds = selectedOptionIds;
      return;
    }
    cartLines.push({
      lineId: `item-${item.id}`,
      menuItemId: item.id,
      item,
      quantity,
      itemNote: allowsItemNote(item) ? itemNote : "",
      selectedStaffId: null,
      selectedOptionIds
    });
  };

  const removeLine = (lineId) => {
    cartLines = cartLines.filter((line) => line.lineId !== lineId);
    renderMenu();
    renderSummary();
  };

  const updateLine = (lineId, changes) => {
    const line = cartLines.find((entry) => entry.lineId === lineId);
    if (!line) return;
    Object.assign(line, changes);
    renderSummary();
  };

  const createOptionControls = (item, line, onChange) => {
    const options = getOrderOptions(item);
    if (!options.length) return null;
    const wrap = element("fieldset", "order-option-list");
    wrap.append(element("legend", "", "加購選項"));
    options.forEach((option) => {
      const label = element("label", "order-option");
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = (line.selectedOptionIds || []).includes(option.id);
      checkbox.disabled = !line.lineId || !isAcceptingOrders();
      const text = element(
        "span",
        "",
        `${option.label} ${formatDelta(option)}`
      );
      if (option.description) {
        text.append(element("small", "", option.description));
      }
      checkbox.addEventListener("change", () => {
        const selected = new Set(line.selectedOptionIds || []);
        if (checkbox.checked) selected.add(option.id);
        else selected.delete(option.id);
        onChange([...selected]);
      });
      label.append(checkbox, text);
      wrap.append(label);
    });
    return wrap;
  };

  const createStaffLine = (item, line) => {
    const row = element("div", "order-special-line");
    const quantityLabel = element("label", "order-line-quantity", "數量");
    const quantity = document.createElement("input");
    quantity.type = "number";
    quantity.min = "1";
    quantity.step = "1";
    quantity.value = String(line.quantity);
    quantity.disabled = !isAcceptingOrders();
    if (item.remaining_quantity != null) {
      const otherQuantity = getItemQuantity(item.id) - line.quantity;
      quantity.max = String(
        Math.max(Number(item.remaining_quantity) - otherQuantity, 1)
      );
    }
    quantity.addEventListener("change", () => {
      let value = Math.max(1, Number(quantity.value) || 1);
      if (item.remaining_quantity != null) {
        const otherQuantity = getItemQuantity(item.id) - line.quantity;
        value = Math.min(
          value,
          Math.max(Number(item.remaining_quantity) - otherQuantity, 1)
        );
      }
      updateLine(line.lineId, { quantity: value });
      renderMenu();
    });
    quantityLabel.append(quantity);
    row.append(quantityLabel);

    const eligibleStaff = getEligibleStaffOptions(
      item,
      line.selectedOptionIds || []
    );
    const selectLabel = element(
      "label",
      "order-staff-select",
      item.staff_selection_label || "請選擇湯娘的獨門料理"
    );
    const select = document.createElement("select");
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "請選擇";
    select.append(placeholder);
    select.disabled = !isAcceptingOrders();
    eligibleStaff.forEach((special) => {
      const option = document.createElement("option");
      option.value = special.staff_id;
      option.textContent = getStaffDisplayName(special);
      option.selected = line.selectedStaffId === special.staff_id;
      select.append(option);
    });
    select.addEventListener("change", () => {
      updateLine(line.lineId, { selectedStaffId: select.value || null });
      renderSummary();
    });
    selectLabel.append(select);
    row.append(selectLabel);

    const optionControls = createOptionControls(item, line, (selectedIds) => {
      const eligibleIds = new Set(
        getEligibleStaffOptions(item, selectedIds).map(
          (entry) => entry.staff_id
        )
      );
      const selectedStaffId =
        line.selectedStaffId && eligibleIds.has(line.selectedStaffId)
          ? line.selectedStaffId
          : null;
      updateLine(line.lineId, {
        selectedOptionIds: selectedIds,
        selectedStaffId
      });
      renderMenu();
    });
    if (optionControls) row.append(optionControls);

    if (allowsItemNote(item)) {
      const noteLabel = element("label", "order-item-note", "品項備註");
      const note = document.createElement("input");
      note.type = "text";
      note.value = line.itemNote;
      note.disabled = !isAcceptingOrders();
      note.addEventListener("input", () =>
        updateLine(line.lineId, { itemNote: note.value.trim() })
      );
      noteLabel.append(note);
      row.append(noteLabel);
    }

    const removeButton = element("button", "order-line-remove", "移除此份");
    removeButton.type = "button";
    removeButton.disabled = !isAcceptingOrders();
    removeButton.addEventListener("click", () => removeLine(line.lineId));
    row.append(removeButton);
    return row;
  };

  const createGeneralControls = (item) => {
    const controls = element("div", "order-item-controls");
    const existing = getItemLines(item.id)[0];
    const selected = Boolean(existing);
    const quantityLabel = element("label", "", "數量");
    const quantity = document.createElement("input");
    quantity.type = "number";
    quantity.min = "1";
    quantity.step = "1";
    quantity.value = String(existing?.quantity || 1);
    quantity.disabled = !selected || !isAcceptingOrders();
    if (item.remaining_quantity != null) {
      quantity.max = String(Math.max(Number(item.remaining_quantity), 1));
    }
    quantityLabel.append(quantity);
    controls.append(quantityLabel);

    let note = null;
    if (allowsItemNote(item)) {
      const noteLabel = element("label", "order-item-note", "品項備註");
      note = document.createElement("input");
      note.type = "text";
      note.value = existing?.itemNote || "";
      note.disabled = !selected || !isAcceptingOrders();
      noteLabel.append(note);
      controls.append(noteLabel);
    }

    const draft = existing || {
      item,
      selectedOptionIds: []
    };
    const optionControls = createOptionControls(item, draft, (selectedIds) => {
      if (!getItemLines(item.id)[0]) return;
      updateLine(`item-${item.id}`, { selectedOptionIds: selectedIds });
    });
    if (optionControls) controls.append(optionControls);

    return { controls, quantity, note, optionControls };
  };

  const createItemCard = (item) => {
    const card = element("article", "order-item-card");
    const noSpecials =
      item.requires_staff_selection && getStaffOptions(item).length === 0;
    const unavailable =
      !isAcceptingOrders() || isSoldOut(item) || noSpecials;
    const heading = element("div", "order-item-heading");
    const nameWrap = element("div");
    nameWrap.append(
      element("h3", "", item.name),
      element("p", "", item.description || "")
    );
    const priceWrap = element("div", "order-item-price");
    priceWrap.append(element("strong", "", item.price || ""));
    if (item.remaining_quantity != null) {
      priceWrap.append(
        element(
          "span",
          isSoldOut(item) ? "order-stock is-sold-out" : "order-stock",
          isSoldOut(item)
            ? "售完"
            : `本日剩餘：${item.remaining_quantity}`
        )
      );
    }

    if (item.requires_staff_selection) {
      card.classList.add("is-special-item");
      heading.append(nameWrap, priceWrap);
      const addButton = element("button", "order-add-line", "新增一份");
      addButton.type = "button";
      addButton.disabled = unavailable || remainingForCart(item) === 0;
      addButton.addEventListener("click", () => {
        if (remainingForCart(item) === 0) {
          setMessage("此品項已售完或剩餘數量不足，請重新選擇。");
          return;
        }
        cartLines.push({
          lineId: createLineId(),
          menuItemId: item.id,
          item,
          quantity: 1,
          itemNote: "",
          selectedStaffId: null,
          selectedOptionIds: []
        });
        renderMenu();
        renderSummary();
      });
      const lines = element("div", "order-special-lines");
      getItemLines(item.id).forEach((line) =>
        lines.append(createStaffLine(item, line))
      );
      card.append(heading, addButton, lines);
    } else {
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = getItemLines(item.id).length > 0;
      checkbox.disabled = unavailable;
      checkbox.setAttribute("aria-label", `選擇 ${item.name}`);
      heading.append(checkbox, nameWrap, priceWrap);
      const { controls, quantity, note } = createGeneralControls(item);
      const sync = () => {
        const selected = checkbox.checked;
        quantity.disabled = !selected || !isAcceptingOrders();
        if (note) note.disabled = !selected || !isAcceptingOrders();
        card.classList.toggle("is-selected", selected);
        if (!selected) {
          cartLines = cartLines.filter((line) => line.menuItemId !== item.id);
        } else {
          let value = Math.max(1, Number(quantity.value) || 1);
          if (item.remaining_quantity != null) {
            value = Math.min(value, Number(item.remaining_quantity));
            quantity.value = String(value);
          }
          const selectedOptionIds =
            getItemLines(item.id)[0]?.selectedOptionIds || [];
          addGeneralLine(
            item,
            value,
            note?.value.trim() || "",
            selectedOptionIds
          );
        }
        renderSummary();
      };
      checkbox.addEventListener("change", () => {
        sync();
        renderMenu();
      });
      quantity.addEventListener("input", sync);
      note?.addEventListener("input", sync);
      if (checkbox.checked) card.classList.add("is-selected");
      card.append(heading, controls);
    }

    if (unavailable) {
      card.classList.add("is-unavailable");
      card.append(
        element(
          "p",
          "order-unavailable",
          !isAcceptingOrders()
            ? "目前未開放點餐。"
            : noSpecials
              ? "目前沒有可提供此品項的人員。"
              : "本日已售完。"
        )
      );
    }
    return card;
  };

  const renderMenu = () => {
    menuRoot.replaceChildren();
    const sections = menuData?.sections || [];
    if (!sections.length) {
      menuRoot.append(element("p", "order-empty", "目前沒有可點餐品項。"));
      return;
    }
    sections.forEach((section) => {
      const sectionNode = element("section", "order-section");
      sectionNode.append(element("h2", "", section.title));
      if (section.subtitle) {
        sectionNode.append(
          element("p", "order-section-subtitle", section.subtitle)
        );
      }
      const grid = element("div", "order-item-grid");
      (section.items || []).forEach((item) => grid.append(createItemCard(item)));
      sectionNode.append(grid);
      menuRoot.append(sectionNode);
    });
  };

  const renderSummary = () => {
    summaryRoot.replaceChildren();
    if (!cartLines.length) {
      summaryRoot.append(element("p", "order-empty", "尚未選擇品項。"));
      return;
    }
    let total = 0;
    let hasPrice = false;
    cartLines.forEach((line) => {
      const row = element("div", "order-summary-row");
      const itemText = element(
        "span",
        "",
        `${line.item.name} × ${line.quantity}`
      );
      if (line.selectedStaffId) {
        const special = getStaffOptions(line.item).find(
          (entry) => entry.staff_id === line.selectedStaffId
        );
        if (special) {
          itemText.append(
            element(
              "small",
              "order-summary-detail",
              getStaffDisplayName(special)
            )
          );
        }
      }
      getSelectedOptions(line).forEach((option) => {
        itemText.append(
          element(
            "small",
            "order-summary-detail",
            `加購：${option.label} ${formatDelta(option)}`
          )
        );
      });
      row.append(itemText, element("strong", "", line.item.price || ""));
      summaryRoot.append(row);
      const amount = parsePrice(line.item.price);
      if (amount !== null) {
        const optionsAmount = getSelectedOptions(line).reduce(
          (sum, option) => sum + Number(option.price_delta_amount || 0),
          0
        );
        total += (amount + optionsAmount) * line.quantity;
        hasPrice = true;
      }
    });
    if (hasPrice) {
      const totalRow = element("div", "order-summary-total");
      totalRow.append(
        element("span", "", "預估合計"),
        element("strong", "", `${total.toLocaleString("en-US")} Gil`)
      );
      summaryRoot.append(totalRow);
    }
  };

  const loadMenu = async () => {
    if (!client || !["menu", "menu2"].includes(shopKey)) {
      throw new Error("點餐服務尚未設定完成。");
    }
    const { data, error } = await client.rpc("get_public_order_menu", {
      p_shop_key: shopKey
    });
    if (error) throw error;
    menuData = data;
    if (!data.shop.order_accepting) {
      cartLines = [];
    }
    title.textContent = `${data.shop.short_title || data.shop.title}點餐`;
    description.textContent =
      data.shop.description ||
      "請依照需求選擇餐點與飲品，送出後由現場人員確認。";
    applyShopFields();
    renderMenu();
    renderSummary();
  };

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage("");
    if (!form.reportValidity()) return;
    if (!isAcceptingOrders()) {
      setMessage(
        menuData?.shop?.order_closed_reason ||
        "目前非營業時間，暫不開放點餐。"
      );
      return;
    }
    if (!cartLines.length) {
      setMessage("請至少選擇一個品項。");
      return;
    }
    for (const line of cartLines) {
      if (line.quantity < 1) {
        setMessage("品項數量至少需要 1 份。");
        return;
      }
      if (line.item.requires_staff_selection && !line.selectedStaffId) {
        setMessage(`「${line.item.name}」每一份都需要選擇湯娘或店員。`);
        return;
      }
      const eligibleStaffIds = new Set(
        getEligibleStaffOptions(
          line.item,
          line.selectedOptionIds || []
        ).map((entry) => entry.staff_id)
      );
      if (
        getSelectedOptions(line).some(
          (option) => option.requires_staff_capability
        ) &&
        (!line.selectedStaffId || !eligibleStaffIds.has(line.selectedStaffId))
      ) {
        setMessage(`「${line.item.name}」的加購需要重新選擇合格人員。`);
        return;
      }
      if (
        line.item.remaining_quantity != null &&
        getItemQuantity(line.menuItemId) > Number(line.item.remaining_quantity)
      ) {
        setMessage("此品項已售完或剩餘數量不足，請重新選擇。");
        return;
      }
    }

    const formData = new FormData(form);
    setBusy(true);
    const { data, error } = await client.rpc("submit_order", {
      p_shop_key: shopKey,
      p_customer_name: String(formData.get("customer_name") || "").trim(),
      p_contact: String(formData.get("contact") || "").trim(),
      p_note: String(formData.get("note") || "").trim(),
      p_requested_time: menuData.shop.order_time_visible === false
        ? null
        : String(formData.get("requested_time") || "").trim() || null,
      p_items: cartLines.map((line) => ({
        menu_item_id: line.menuItemId,
        quantity: line.quantity,
        item_note: allowsItemNote(line.item) ? line.itemNote : null,
        selected_staff_id: line.selectedStaffId,
        selected_option_ids: line.selectedOptionIds || []
      }))
    });
    setBusy(false);
    if (error) {
      console.error("Order submission failed.", error);
      if (
        String(error.message || "").includes("目前非營業時間") ||
        String(error.message || "").includes("Requested time")
      ) {
        setMessage(
          String(error.message || "").includes("Requested time")
            ? "請重新選擇可用的用餐時間。"
            : "目前非營業時間，暫不開放點餐。"
        );
        cartLines = [];
        await loadMenu().catch(console.error);
        return;
      }
      if (
        String(error.message || "").includes(
          "此品項已售完或剩餘數量不足"
        )
      ) {
        setMessage("此品項已售完或剩餘數量不足，請重新選擇。");
        cartLines = [];
        await loadMenu().catch(console.error);
        return;
      }
      setMessage(`點餐送出失敗：${error.message || "請稍後再試。"}`);
      return;
    }

    const orderId = getSubmittedOrderId(data);
    cartLines = [];
    form.reset();
    setMessage("已收到您的點餐，請稍候店員確認。", "success");
    console.info("Order submitted.", data);
    await notifyOrderDiscord(orderId);
    try {
      await loadMenu();
    } catch (menuError) {
      console.warn("Order submitted, but menu refresh failed.", menuError);
    }
  });

  loadMenu().catch((error) => {
    console.error("Order menu load failed.", error);
    menuRoot.replaceChildren(
      element(
        "p",
        "order-empty",
        `點餐菜單載入失敗：${error.message || "請稍後再試。"}`
      )
    );
  });
})();
