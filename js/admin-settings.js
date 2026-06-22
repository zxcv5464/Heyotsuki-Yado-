(() => {
  const client = window.SUPABASE_CLIENT;
  const fields = [
    ["bookingUrl", "預約表單網址"],
    ["discordUrl", "Discord 連結"],
    ["threadsUrl", "Threads 連結"],
    ["address", "地址"],
    ["openingDays", "營業日"],
    ["openingHours", "營業時間"],
    ["status", "目前狀態"],
  ];

  const form = document.querySelector("[data-settings-form]");
  const denied = document.querySelector("[data-settings-denied]");
  const message = document.querySelector("[data-settings-message]");
  const submitButton = form?.querySelector('button[type="submit"]');

  const setMessage = (text, type = "error") => {
    if (!message) return;
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const setBusy = (busy, text = "儲存中...") => {
    if (!submitButton) return;
    if (!submitButton.dataset.defaultText) {
      submitButton.dataset.defaultText = submitButton.textContent;
    }
    submitButton.disabled = busy;
    submitButton.textContent = busy
      ? text
      : submitButton.dataset.defaultText;
  };

  const fillForm = (settings) => {
    fields.forEach(([key]) => {
      const input = form?.elements.namedItem(key);
      if (input) {
        input.value = settings[key] ?? window.SITE_CONFIG?.[key] ?? "";
      }
    });
  };

  const loadSettings = async () => {
    setBusy(true, "載入中...");
    const keys = fields.map(([key]) => key);
    const { data, error } = await client
      .from("site_settings")
      .select("key, value")
      .in("key", keys);

    if (error) {
      fillForm({});
      setMessage("設定讀取失敗，已顯示本地預設值。");
    } else {
      fillForm(
        Object.fromEntries(
          (data || []).map((setting) => [setting.key, setting.value])
        )
      );
    }
    setBusy(false);
  };

  const init = async (profile) => {
    if (!window.ADMIN_CAN?.("settings.manage")) {
      if (denied) denied.hidden = false;
      if (form) form.hidden = true;
      return;
    }

    if (form) form.hidden = false;
    await loadSettings();
  };

  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage("");
    setBusy(true);

    const formData = new FormData(form);
    const rows = fields.map(([key, label]) => ({
      key,
      value: String(formData.get(key) || "").trim(),
      description: label,
    }));

    const { error } = await client
      .from("site_settings")
      .upsert(rows, { onConflict: "key" });

    if (error) {
      setMessage(`儲存失敗：${error.message || "請稍後再試。"}`);
      setBusy(false);
      return;
    }

    rows.forEach(({ key, value }) => {
      window.SITE_CONFIG[key] = value;
    });
    setMessage("網站設定已儲存。", "success");
    setBusy(false);
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
