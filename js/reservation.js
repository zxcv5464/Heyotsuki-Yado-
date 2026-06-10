(() => {
  const client = window.SUPABASE_CLIENT;
  const form = document.querySelector("[data-reservation-form]");
  const fieldsContainer = document.querySelector("[data-reservation-fields]");
  const title = document.querySelector("[data-reservation-title]");
  const description = document.querySelector("[data-reservation-description]");
  const message = document.querySelector("[data-reservation-message]");
  const fallback = document.querySelector("[data-reservation-fallback]");
  const fallbackLink = document.querySelector("[data-reservation-fallback-link]");
  const submitButton = form?.querySelector('button[type="submit"]');

  let settings = null;
  let fields = [];
  let options = [];
  let staffMembers = [];
  let availability = [];

  const safeExternalHref = (value) => {
    try {
      const url = new URL(String(value || ""));
      return url.protocol === "https:" ? url.href : "#";
    } catch {
      return "#";
    }
  };

  const setMessage = (text, type = "error") => {
    if (!message) return;
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const setBusy = (busy) => {
    if (!submitButton) return;
    submitButton.disabled = busy || !availability.length;
    submitButton.textContent = busy ? "送出中..." : "送出預約";
  };

  const createHelp = (text) => {
    if (!text) return null;
    const help = document.createElement("p");
    help.className = "reservation-help";
    help.textContent = text;
    return help;
  };

  const setCommonAttributes = (input, field) => {
    input.name = field.field_key;
    input.required = Boolean(field.required);
    input.id = `reservation-${field.field_key}`;
  };

  const normalizeSlots = (value) => {
    if (Array.isArray(value)) return value;
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  };

  const normalizeAvailability = (rows) =>
    (rows || []).map((row) => ({
      reservationDate: row.reservation_date,
      displayLabel: row.display_label,
      availableSlots: normalizeSlots(row.available_slots),
    }));

  const getFieldOptions = (field) =>
    options
      .filter((option) => option.field_id === field.id)
      .map((option) => ({ label: option.label, value: option.value }));

  const addOptions = (select, entries) => {
    entries.forEach((entry) => {
      const option = document.createElement("option");
      option.value = entry.value;
      option.textContent = entry.label;
      select.append(option);
    });
  };

  const createSelect = (field, entries, placeholderText) => {
    const select = document.createElement("select");
    setCommonAttributes(select, field);
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent =
      placeholderText || (field.required ? "請選擇" : "無指定");
    select.append(placeholder);
    addOptions(select, entries);
    return select;
  };

  const createRadioGroup = (field, entries) => {
    const group = document.createElement("div");
    group.className = "reservation-radio-group";
    group.id = `reservation-${field.field_key}`;
    group.setAttribute("role", "radiogroup");
    entries.forEach((entry) => {
      const label = document.createElement("label");
      label.className = "reservation-radio";
      const input = document.createElement("input");
      input.type = "radio";
      input.name = field.field_key;
      input.value = entry.value;
      input.required = Boolean(field.required);
      const syncRadioState = () => {
        group.querySelectorAll(".reservation-radio").forEach((option) => {
          option.classList.toggle(
            "is-selected",
            option.querySelector("input").checked
          );
        });
      };
      input.addEventListener("change", syncRadioState);
      input.addEventListener("click", syncRadioState);
      input.addEventListener("focus", () => {
        label.classList.add("is-focus-visible");
      });
      input.addEventListener("blur", () => {
        label.classList.remove("is-focus-visible");
      });
      const text = document.createElement("span");
      text.textContent = entry.label;
      label.append(input, text);
      group.append(label);
    });
    return group;
  };

  const syncAllRadioStates = () => {
    form
      ?.querySelectorAll(".reservation-radio-group")
      .forEach((group) => {
        group.querySelectorAll(".reservation-radio").forEach((option) => {
          const input = option.querySelector('input[type="radio"]');
          option.classList.toggle("is-selected", Boolean(input?.checked));
          option.classList.remove("is-focus-visible");
        });
      });
  };

  const populateTimeSelect = (dateValue, selectedValue = "") => {
    const select = form?.elements.namedItem("reservation_time");
    if (!(select instanceof HTMLSelectElement)) return;
    select.replaceChildren();
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = dateValue ? "請選擇時段" : "請先選擇日期";
    select.append(placeholder);
    const date = availability.find(
      (entry) => entry.reservationDate === dateValue
    );
    addOptions(select, date?.availableSlots || []);
    select.disabled = !date;
    if (
      selectedValue &&
      date?.availableSlots.some((slot) => slot.value === selectedValue)
    ) {
      select.value = selectedValue;
    }
  };

  const createDateSelect = (field) => {
    const select = createSelect(
      field,
      availability.map((entry) => ({
        label: entry.displayLabel,
        value: entry.reservationDate,
      })),
      availability.length ? "請選擇可預約日期" : "目前沒有可預約日期"
    );
    select.disabled = !availability.length;
    select.addEventListener("change", () => {
      populateTimeSelect(select.value);
    });
    return select;
  };

  const createTimeSelect = (field) => {
    const select = createSelect(field, [], "請先選擇日期");
    select.disabled = true;
    return select;
  };

  const createStaffSelect = (name, id, labelText) => {
    const group = document.createElement("div");
    group.className = "reservation-staff-select";
    const label = document.createElement("label");
    label.className = "reservation-sub-label";
    label.htmlFor = id;
    label.textContent = labelText;
    const select = document.createElement("select");
    select.name = name;
    select.id = id;
    const empty = document.createElement("option");
    empty.value = "";
    empty.textContent = "無指定";
    select.append(empty);
    addOptions(
      select,
      staffMembers.map((member) => ({
        label: member.name,
        value: member.id,
      }))
    );
    group.append(label, select);
    return group;
  };

  const createStaffControls = (field) => {
    const controls = document.createElement("div");
    controls.className = "reservation-staff-grid";
    controls.append(
      createStaffSelect(
        "preferred_staff_name",
        "reservation-preferred_staff_name",
        "第一位指定湯娘"
      ),
      createStaffSelect(
        "preferred_staff_2_name",
        "reservation-preferred_staff_2_name",
        "第二位指定湯娘（選填）"
      )
    );
    return controls;
  };

  const createFieldControl = (field) => {
    if (field.field_key === "reservation_date") {
      return createDateSelect(field);
    }
    if (field.field_key === "reservation_time") {
      return createTimeSelect(field);
    }
    if (field.field_type === "staff_select") {
      return createStaffControls(field);
    }
    if (field.field_type === "textarea") {
      const textarea = document.createElement("textarea");
      textarea.rows = 5;
      setCommonAttributes(textarea, field);
      return textarea;
    }
    if (field.field_type === "select") {
      return createSelect(field, getFieldOptions(field));
    }
    if (field.field_type === "radio") {
      return createRadioGroup(field, getFieldOptions(field));
    }
    const input = document.createElement("input");
    input.type = field.field_type === "number" ? "number" : "text";
    setCommonAttributes(input, field);
    return input;
  };

  const renderFields = () => {
    fieldsContainer.replaceChildren();
    fields.forEach((field) => {
      const wrapper = document.createElement("div");
      wrapper.className = "reservation-field";
      const label = document.createElement("label");
      label.className = "reservation-label";
      label.htmlFor = `reservation-${field.field_key}`;
      label.textContent = field.label;
      if (field.required) {
        const required = document.createElement("span");
        required.textContent = " 必填";
        label.append(required);
      }
      wrapper.append(label, createFieldControl(field));
      const help = createHelp(field.help_text);
      if (help) wrapper.append(help);
      fieldsContainer.append(wrapper);
    });
  };

  const showFallback = (text) => {
    setMessage(text);
    form.hidden = true;
    fallback.hidden = false;
    fallbackLink.href = safeExternalHref(window.SITE_CONFIG?.bookingUrl);
  };

  const loadAvailability = async () => {
    const { data, error } = await client.rpc(
      "get_public_reservation_availability",
      {
        p_days: Number(settings?.booking_window_days) || 60,
      }
    );
    if (error) throw error;
    availability = normalizeAvailability(data);
  };

  const loadForm = async () => {
    if (!client) {
      showFallback("Supabase 尚未設定，無法載入站內預約表。");
      return;
    }

    const [settingsResult, fieldsResult, optionsResult, staffResult] =
      await Promise.all([
        client
          .from("reservation_form_settings")
          .select(
            "title, description, allowed_weekdays, min_days_before, booking_window_days, is_active"
          )
          .eq("id", "default")
          .maybeSingle(),
        client
          .from("reservation_form_fields")
          .select(
            "id, field_key, label, help_text, field_type, required, sort_order"
          )
          .eq("is_visible", true)
          .order("sort_order", { ascending: true }),
        client
          .from("reservation_form_options")
          .select("field_id, label, value, sort_order")
          .eq("is_visible", true)
          .order("sort_order", { ascending: true }),
        client
          .from("staff_members")
          .select("id, name, sort_order")
          .eq("is_visible", true)
          .eq("is_reservable", true)
          .order("sort_order", { ascending: true })
          .order("name", { ascending: true }),
      ]);

    const error = [settingsResult, fieldsResult, optionsResult, staffResult].find(
      (result) => result.error
    )?.error;
    if (error) {
      showFallback(`預約表載入失敗：${error.message || "請稍後再試。"}`);
      return;
    }
    if (!settingsResult.data) {
      title.textContent = "目前未開放線上預約";
      description.textContent = "";
      form.hidden = true;
      fallback.hidden = true;
      setMessage("目前未開放線上預約，請留意網站最新公告。");
      return;
    }
    if (!fieldsResult.data?.length) {
      showFallback("目前沒有可用的預約表欄位。");
      return;
    }

    settings = settingsResult.data;
    fields = fieldsResult.data;
    options = optionsResult.data || [];
    staffMembers = staffResult.data || [];
    await loadAvailability();
    title.textContent = settings.title || "嘿月湯宿 預約表";
    description.textContent = settings.description || "";
    renderFields();
    setBusy(false);
    fallback.hidden = true;
    form.hidden = false;
    if (!availability.length) {
      setMessage("目前預約期間內沒有可預約日期。");
    }
  };

  const refreshAvailability = async (preferredDate = "") => {
    await loadAvailability();
    const dateSelect = form?.elements.namedItem("reservation_date");
    if (!(dateSelect instanceof HTMLSelectElement)) return;
    dateSelect.replaceChildren();
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = availability.length
      ? "請選擇可預約日期"
      : "目前沒有可預約日期";
    dateSelect.append(placeholder);
    addOptions(
      dateSelect,
      availability.map((entry) => ({
        label: entry.displayLabel,
        value: entry.reservationDate,
      }))
    );
    dateSelect.disabled = !availability.length;
    if (
      preferredDate &&
      availability.some((entry) => entry.reservationDate === preferredDate)
    ) {
      dateSelect.value = preferredDate;
    }
    populateTimeSelect(dateSelect.value);
    setBusy(false);
  };

  const getAnswerValue = (formData, fieldKey) => {
    const value = formData.get(fieldKey);
    return typeof value === "string" ? value.trim() : "";
  };

  const getAnswerDisplayValue = (field, value) => {
    if (!value) return "";
    if (
      field.field_key !== "reservation_time" &&
      ["radio", "select"].includes(field.field_type)
    ) {
      return (
        getFieldOptions(field).find((option) => option.value === value)?.label ||
        value
      );
    }
    return value;
  };

  const createAnswerSnapshot = (field, value, displayValue = value) => ({
    label: field.label,
    type: field.field_type,
    value,
    display_value: displayValue,
  });

  const buildFormAnswers = (formData, firstStaff, secondStaff) => {
    const snapshots = {};
    fields.forEach((field) => {
      if (field.field_type === "staff_select") {
        snapshots.preferred_staff_name = createAnswerSnapshot(
          {
            ...field,
            label: "第一位指定湯娘",
          },
          firstStaff?.name || "無指定"
        );
        snapshots.preferred_staff_2_name = createAnswerSnapshot(
          {
            ...field,
            label: "第二位指定湯娘",
          },
          secondStaff?.name || "無指定"
        );
        return;
      }

      const value = getAnswerValue(formData, field.field_key);
      snapshots[field.field_key] = createAnswerSnapshot(
        field,
        value,
        getAnswerDisplayValue(field, value)
      );
    });
    return snapshots;
  };

  const findStaff = (id) =>
    staffMembers.find((member) => member.id === id) || null;

  const normalizeReservationDate = (value) =>
    /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : "";

  const isSlotConflict = (error) =>
    error?.code === "23505" ||
    /reservations_active_slot_unique_idx|duplicate key/i.test(
      error?.message || ""
    );

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage("");
    if (!form.reportValidity()) return;

    const formData = new FormData(form);
    const reservationDate = normalizeReservationDate(
      getAnswerValue(formData, "reservation_date")
    );
    const reservationTime = getAnswerValue(formData, "reservation_time");
    const dateAvailability = availability.find(
      (entry) => entry.reservationDate === reservationDate
    );
    const slotAvailable = dateAvailability?.availableSlots.some(
      (slot) => slot.value === reservationTime
    );
    if (!slotAvailable) {
      setMessage("此日期或時段已無法預約，請重新選擇。");
      await refreshAvailability();
      return;
    }

    const firstStaffId = getAnswerValue(formData, "preferred_staff_name");
    const secondStaffId = getAnswerValue(formData, "preferred_staff_2_name");
    if (firstStaffId && secondStaffId && firstStaffId === secondStaffId) {
      setMessage("第一位與第二位指定湯娘不可選擇同一人。");
      return;
    }
    const firstStaff = findStaff(firstStaffId);
    const secondStaff = findStaff(secondStaffId);
    const rawAnswers = Object.fromEntries(
      fields
        .filter((field) => field.field_type !== "staff_select")
        .map((field) => [
          field.field_key,
          getAnswerValue(formData, field.field_key),
        ])
    );
    const formAnswers = buildFormAnswers(formData, firstStaff, secondStaff);
    const customerName = String(rawAnswers.customer_name || "").trim();
    const contactField = fields.find((field) => field.field_key === "contact");
    const contact = String(rawAnswers.contact || "").trim();
    const partySize = Number(rawAnswers.party_size);
    if (!customerName) {
      setMessage("請填寫預約人姓名。");
      return;
    }
    if (contactField?.required && !contact) {
      setMessage("請填寫聯絡方式。");
      return;
    }
    if (!reservationDate || !reservationTime || !Number.isInteger(partySize) || partySize < 1) {
      setMessage("預約日期、時段或人數格式不正確，請重新選擇。");
      return;
    }

    const reservationId = crypto.randomUUID();
    const payload = {
      id: reservationId,
      customer_name: customerName,
      contact: contact || "未提供",
      reservation_date: reservationDate,
      reservation_time: reservationTime,
      party_size: partySize,
      changing_together: rawAnswers.changing_together || null,
      plan: rawAnswers.plan || null,
      preferred_staff_name: firstStaff?.name || "無指定",
      preferred_staff_id: firstStaff?.id || null,
      preferred_staff_2_name: secondStaff?.name || "無指定",
      preferred_staff_2_id: secondStaff?.id || null,
      photo_service: rawAnswers.photo_service || null,
      dessert_service: rawAnswers.dessert_service || null,
      note: rawAnswers.note || null,
      form_answers: formAnswers,
    };

    setBusy(true);
    const { error } = await client.from("reservations").insert(payload);
    setBusy(false);
    if (error) {
      console.error("Supabase reservation insert failed.", {
        error,
        payload,
      });
      if (isSlotConflict(error)) {
        setMessage("此時段剛被預約，請重新選擇日期與時段。");
      } else {
        setMessage(`預約送出失敗：${error.message || "請稍後再試。"}`);
      }
      await refreshAvailability(reservationDate);
      return;
    }

    try {
      const { data: notifyData, error: notifyError } =
        await client.functions.invoke("notify-reservation-discord", {
          body: {
            reservation_id: reservationId,
            force: false,
          },
        });
      if (notifyError || notifyData?.status === "failed") {
        console.warn("Discord reservation notification failed.", {
          error: notifyError,
          data: notifyData,
          reservationId,
        });
      }
    } catch (notifyError) {
      console.warn("Discord reservation notification failed.", {
        error: notifyError,
        reservationId,
      });
    }

    form.reset();
    syncAllRadioStates();
    await refreshAvailability();
    setMessage("已收到您的預約，請等待店家確認。", "success");
    message.scrollIntoView({ behavior: "smooth", block: "center" });
  });

  form?.addEventListener("reset", () => {
    requestAnimationFrame(syncAllRadioStates);
  });

  loadForm().catch((error) => {
    showFallback(`預約表載入失敗：${error.message || "請稍後再試。"}`);
  });
})();
