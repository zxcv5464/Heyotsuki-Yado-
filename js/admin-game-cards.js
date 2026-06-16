(() => {
  const client = window.SUPABASE_CLIENT;
  const bucket = "heyotsuki-images";
  const editableRoles = new Set(["owner", "admin"]);
  const acceptedTypes = new Set([
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/gif",
  ]);
  const IMAGE_CACHE_CONTROL = "31536000";
  const IMAGE_MAX_WIDTH = 600;
  const IMAGE_MAX_HEIGHT = 800;
  const IMAGE_WEBP_QUALITY = 0.76;
  const markLabels = {
    moon: "月印",
    bell: "鈴印",
    fan: "扇印",
    knot: "結印",
  };
  const seasonLabels = {
    spring: "春",
    summer: "夏",
    autumn: "秋",
    winter: "冬",
  };

  const content = document.querySelector("[data-game-card-content]");
  const denied = document.querySelector("[data-game-card-denied]");
  const message = document.querySelector("[data-game-card-message]");
  const autoAssignButton = document.querySelector("[data-auto-assign]");
  const list = document.querySelector("[data-game-card-list]");
  const count = document.querySelector("[data-game-card-count]");
  const editor = document.querySelector("[data-game-card-editor]");
  const form = document.querySelector("[data-game-card-form]");
  const cancelButton = document.querySelector("[data-cancel-game-card]");
  const fileInput = document.querySelector("[data-game-card-image-file]");
  const uploadButton = document.querySelector("[data-upload-game-card-image]");
  const submitButton = form?.querySelector('button[type="submit"]');
  const statusFilter = document.querySelector("[data-filter-status]");
  const visibilityFilter = document.querySelector("[data-filter-visibility]");
  const searchFilter = document.querySelector("[data-filter-search]");
  const previewImage = document.querySelector("[data-game-card-preview-image]");
  const previewEmpty = document.querySelector("[data-game-card-preview-empty]");

  let months = [];
  let members = [];
  let pendingImage = null;
  let editingMember = null;
  let uploadSequence = 0;

  const setMessage = (text, type = "error") => {
    if (!message) return;
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const setButtonBusy = (button, busy, busyText) => {
    if (!button) return;
    if (!button.dataset.defaultText) {
      button.dataset.defaultText = button.textContent;
    }
    button.disabled = busy;
    button.textContent = busy ? busyText : button.dataset.defaultText;
  };

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const safeImageUrl = (value) => {
    try {
      const baseUrl = new URL("../", window.location.href);
      const url = new URL(value, baseUrl);
      return ["http:", "https:"].includes(url.protocol) ? url.href : "";
    } catch {
      return "";
    }
  };

  const effectiveImageUrl = (member) =>
    safeImageUrl(member?.settings?.card_image_url) ||
    safeImageUrl(member?.image_url);

  const monthFor = (monthNo) =>
    months.find((month) => Number(month.month_no) === Number(monthNo));

  const isActiveCard = (member) =>
    Boolean(
      member.is_visible &&
      member.settings?.is_game_enabled &&
      monthFor(member.settings.month_no) &&
      markLabels[member.settings.mark] &&
      effectiveImageUrl(member)
    );

  const normalizeSlug = (...values) => {
    for (const value of values) {
      const slug = String(value || "")
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 48);
      if (slug) return slug;
    }
    return "game-card";
  };

  const formatTimestamp = (date) => {
    const pad = (number) => String(number).padStart(2, "0");
    return [
      date.getFullYear(),
      pad(date.getMonth() + 1),
      pad(date.getDate()),
      "-",
      pad(date.getHours()),
      pad(date.getMinutes()),
      pad(date.getSeconds()),
    ].join("");
  };

  const canvasToBlob = (canvas) =>
    new Promise((resolve, reject) => {
      canvas.toBlob(
        (blob) => {
          if (blob) resolve(blob);
          else reject(new Error("瀏覽器無法將圖片轉成 WebP。"));
        },
        "image/webp",
        IMAGE_WEBP_QUALITY
      );
    });

  const loadImage = (file) =>
    new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const image = new Image();
      image.onload = () => resolve({ image, url });
      image.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error("無法讀取選擇的圖片。"));
      };
      image.src = url;
    });

  const convertToWebp = async (file) => {
    if (!acceptedTypes.has(file.type)) {
      throw new Error("僅支援 JPG、PNG、WebP 或 GIF 圖片。");
    }

    const { image, url } = await loadImage(file);
    try {
      const scale = Math.min(
        1,
        IMAGE_MAX_WIDTH / image.naturalWidth,
        IMAGE_MAX_HEIGHT / image.naturalHeight
      );
      const width = Math.max(1, Math.round(image.naturalWidth * scale));
      const height = Math.max(1, Math.round(image.naturalHeight * scale));
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext("2d", { alpha: true });
      context.clearRect(0, 0, width, height);
      context.drawImage(image, 0, 0, width, height);
      return await canvasToBlob(canvas);
    } finally {
      URL.revokeObjectURL(url);
    }
  };

  const setPreviewImage = (url) => {
    const previewUrl = String(url || "").startsWith("blob:")
      ? String(url)
      : safeImageUrl(url);
    if (!previewUrl) {
      previewImage.hidden = true;
      previewImage.removeAttribute("src");
      previewEmpty.hidden = false;
      return;
    }
    previewImage.src = previewUrl;
    previewImage.hidden = false;
    previewEmpty.hidden = true;
  };

  const renderFormPreview = () => {
    const month = monthFor(form.elements.month_no.value);
    const mark = form.elements.mark.value;
    document.querySelector("[data-game-card-preview-month]").textContent =
      month?.month_label || "月份未設定";
    document.querySelector("[data-game-card-preview-name]").textContent =
      editingMember?.name || "湯娘名稱";
    document.querySelector("[data-game-card-preview-meta]").textContent =
      `${seasonLabels[month?.season] || "季節"}・${markLabels[mark] || "印記"}`;
    document.querySelector("[data-game-card-preview-title]").textContent =
      form.elements.card_title.value.trim();
    form.elements.season.value = seasonLabels[month?.season] || "";

    if (!pendingImage) {
      setPreviewImage(
        form.elements.card_image_url.value.trim() || editingMember?.image_url
      );
    }
  };

  const selectImage = async (file) => {
    setMessage("");
    setButtonBusy(uploadButton, true, "轉換中...");
    try {
      const blob = await convertToWebp(file);
      if (pendingImage?.previewUrl) {
        URL.revokeObjectURL(pendingImage.previewUrl);
      }
      pendingImage = {
        blob,
        originalName: file.name,
        previewUrl: URL.createObjectURL(blob),
      };
      setPreviewImage(pendingImage.previewUrl);
      uploadButton.disabled = false;
      setMessage("專用卡面已轉成 WebP，尚未上傳。", "success");
    } catch (error) {
      pendingImage = null;
      uploadButton.disabled = true;
      setMessage(error.message || "圖片轉換失敗。");
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const uploadPendingImage = async () => {
    if (!pendingImage) {
      return form.elements.card_image_url.value.trim();
    }

    const slug = normalizeSlug(
      editingMember?.name,
      pendingImage.originalName.replace(/\.[^.]+$/, "")
    );
    let path = "";
    let uploadError = null;

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const timestamp = formatTimestamp(
        new Date(Date.now() + (uploadSequence + attempt) * 1000)
      );
      path = `game-cards/${timestamp}-${slug}.webp`;
      const { error } = await client.storage
        .from(bucket)
        .upload(path, pendingImage.blob, {
          contentType: "image/webp",
          cacheControl: IMAGE_CACHE_CONTROL,
          upsert: false,
        });
      uploadError = error;
      if (!error) {
        uploadError = null;
        uploadSequence += attempt + 1;
        break;
      }
      const conflict =
        error.statusCode === "409" ||
        error.status === 409 ||
        /already exists|duplicate/i.test(error.message || "");
      if (!conflict) throw error;
    }
    if (uploadError) throw uploadError;

    const { data } = client.storage.from(bucket).getPublicUrl(path);
    if (!data?.publicUrl) {
      throw new Error("圖片已上傳，但無法取得 public URL。");
    }

    form.elements.card_image_url.value = data.publicUrl;
    setPreviewImage(data.publicUrl);
    URL.revokeObjectURL(pendingImage.previewUrl);
    pendingImage = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    return data.publicUrl;
  };

  const renderSummary = () => {
    const activeCount = members.filter(isActiveCard).length;
    const unsetCount = members.filter((member) => !member.settings).length;
    document.querySelector("[data-summary-total]").textContent = members.length;
    document.querySelector("[data-summary-active]").textContent = activeCount;
    document.querySelector("[data-summary-unset]").textContent = unsetCount;

    const monthCounts = Object.fromEntries(months.map((month) => [month.month_no, 0]));
    const markCounts = Object.fromEntries(
      Object.keys(markLabels).map((mark) => [mark, 0])
    );
    members.forEach((member) => {
      if (!member.settings?.is_game_enabled) return;
      if (monthCounts[member.settings.month_no] !== undefined) {
        monthCounts[member.settings.month_no] += 1;
      }
      if (markCounts[member.settings.mark] !== undefined) {
        markCounts[member.settings.mark] += 1;
      }
    });

    document.querySelector("[data-month-distribution]").innerHTML = months
      .map(
        (month) => `
          <div>
            <span>${escapeHtml(month.month_label)}</span>
            <strong>${monthCounts[month.month_no]}</strong>
          </div>`
      )
      .join("");
    document.querySelector("[data-mark-distribution]").innerHTML = Object.entries(
      markLabels
    )
      .map(
        ([mark, label]) => `
          <div>
            <span>${escapeHtml(label)}</span>
            <strong>${markCounts[mark]}</strong>
          </div>`
      )
      .join("");
  };

  const matchesFilters = (member) => {
    const status = statusFilter.value;
    const visibility = visibilityFilter.value;
    const search = searchFilter.value.trim().toLocaleLowerCase("zh-Hant");
    if (status === "unset" && member.settings) return false;
    if (status === "enabled" && !member.settings?.is_game_enabled) return false;
    if (status === "disabled" && member.settings?.is_game_enabled !== false) {
      return false;
    }
    if (visibility === "visible" && !member.is_visible) return false;
    if (visibility === "hidden" && member.is_visible) return false;
    if (search && !member.name.toLocaleLowerCase("zh-Hant").includes(search)) {
      return false;
    }
    return true;
  };

  const renderList = () => {
    const filteredMembers = members.filter(matchesFilters);
    count.textContent = `顯示 ${filteredMembers.length} / ${members.length} 筆`;
    list.innerHTML = filteredMembers.length
      ? filteredMembers
          .map((member) => {
            const settings = member.settings;
            const month = monthFor(settings?.month_no);
            const imageUrl = effectiveImageUrl(member);
            const status = !settings
              ? '<span class="status-badge status-badge-featured">未設定</span>'
              : settings.is_game_enabled
                ? '<span class="status-badge status-badge-visible">遊戲啟用</span>'
                : '<span class="status-badge status-badge-hidden">遊戲停用</span>';
            const visibility = member.is_visible
              ? '<span class="status-badge status-badge-visible">官網顯示</span>'
              : '<span class="status-badge status-badge-hidden">官網隱藏</span>';
            const eligibility = isActiveCard(member)
              ? '<span class="status-badge status-badge-visible">可進卡池</span>'
              : '<span class="status-badge status-badge-hidden">不可進卡池</span>';
            return `
              <article class="game-card-admin-row${member.is_visible ? "" : " is-hidden"}">
                <div class="staff-thumb game-card-admin-thumb">
                  ${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(member.name)}" loading="lazy">` : "<span>無圖片</span>"}
                </div>
                <div class="staff-summary">
                  <h3>${escapeHtml(member.name)}</h3>
                  <p>${month ? `${escapeHtml(month.month_label)}・${escapeHtml(seasonLabels[month.season])}` : "月份未設定"}</p>
                  <small>${settings ? escapeHtml(markLabels[settings.mark] || settings.mark) : "印記未設定"}${settings?.card_title ? `・${escapeHtml(settings.card_title)}` : ""}</small>
                </div>
                <div class="staff-visibility">${status}${visibility}${eligibility}</div>
                <div class="staff-row-actions">
                  <button class="text-button" data-edit-game-card="${escapeHtml(member.id)}" type="button">${settings ? "編輯卡片" : "設定卡片"}</button>
                </div>
              </article>`;
          })
          .join("")
      : '<p class="admin-empty">沒有符合條件的湯娘。</p>';
  };

  const loadData = async () => {
    const [monthResult, staffResult, settingsResult] = await Promise.all([
      client.rpc("get_game_month_catalog"),
      client
        .from("staff_members")
        .select("id, name, image_url, is_visible, sort_order")
        .order("sort_order", { ascending: true }),
      client
        .from("game_staff_card_settings")
        .select(
          "staff_id, month_no, mark, card_title, card_image_url, is_game_enabled"
        ),
    ]);

    const error = monthResult.error || staffResult.error || settingsResult.error;
    if (error) throw error;

    months = monthResult.data || [];
    const settingsByStaff = new Map(
      (settingsResult.data || []).map((settings) => [settings.staff_id, settings])
    );
    members = (staffResult.data || []).map((member) => ({
      ...member,
      settings: settingsByStaff.get(member.id) || null,
    }));

    form.elements.month_no.innerHTML = months
      .map(
        (month) =>
          `<option value="${month.month_no}">${escapeHtml(month.month_label)}</option>`
      )
      .join("");
    renderSummary();
    renderList();
  };

  const resetEditor = () => {
    if (pendingImage?.previewUrl) {
      URL.revokeObjectURL(pendingImage.previewUrl);
    }
    form.reset();
    form.elements.staff_id.value = "";
    form.elements.is_game_enabled.checked = true;
    pendingImage = null;
    editingMember = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    setPreviewImage("");
  };

  const closeEditor = () => {
    resetEditor();
    editor.hidden = true;
  };

  const openEditor = (member) => {
    setMessage("");
    resetEditor();
    editingMember = member;
    form.elements.staff_id.value = member.id;
    form.elements.staff_name.value = member.name;
    form.elements.month_no.value = member.settings?.month_no || months[0]?.month_no;
    form.elements.mark.value = member.settings?.mark || "moon";
    form.elements.card_title.value = member.settings?.card_title || "";
    form.elements.card_image_url.value =
      member.settings?.card_image_url || "";
    form.elements.is_game_enabled.checked =
      member.settings?.is_game_enabled ?? true;
    document.querySelector("#game-card-form-title").textContent =
      `${member.settings ? "編輯" : "設定"} ${member.name} 的遊戲卡`;
    renderFormPreview();
    editor.hidden = false;
    editor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const saveSettings = async (event) => {
    event.preventDefault();
    setMessage("");
    setButtonBusy(submitButton, true, "儲存中...");
    setButtonBusy(uploadButton, true, "處理圖片中...");
    try {
      const cardImageUrl = pendingImage
        ? await uploadPendingImage()
        : form.elements.card_image_url.value.trim();
      const payload = {
        staff_id: form.elements.staff_id.value,
        month_no: Number(form.elements.month_no.value),
        mark: form.elements.mark.value,
        card_title: form.elements.card_title.value.trim() || null,
        card_image_url: cardImageUrl || null,
        is_game_enabled: form.elements.is_game_enabled.checked,
      };
      const { error } = await client
        .from("game_staff_card_settings")
        .upsert(payload, { onConflict: "staff_id" });
      if (error) throw error;

      closeEditor();
      await loadData();
      setMessage("遊戲卡設定已儲存。", "success");
    } catch (error) {
      setMessage(`儲存失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(submitButton, false);
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const autoAssign = async () => {
    const unsetCount = members.filter((member) => !member.settings).length;
    if (!unsetCount) {
      setMessage("目前沒有未設定的湯娘。", "success");
      return;
    }
    if (
      !window.confirm(
        `將為 ${unsetCount} 位未設定湯娘永久分配月份與印記，既有設定不會變更。是否繼續？`
      )
    ) {
      return;
    }

    setMessage("");
    setButtonBusy(autoAssignButton, true, "分配中...");
    try {
      const { data, error } = await client.rpc(
        "auto_assign_unset_game_staff_cards"
      );
      if (error) throw error;
      await loadData();
      setMessage(`已完成 ${data?.length || 0} 位湯娘的遊戲卡分配。`, "success");
    } catch (error) {
      setMessage(`自動分配失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(autoAssignButton, false);
    }
  };

  const init = async (profile) => {
    if (!editableRoles.has(profile.role)) {
      denied.hidden = false;
      content.hidden = true;
      autoAssignButton.hidden = true;
      return;
    }

    content.hidden = false;
    autoAssignButton.hidden = false;
    try {
      await loadData();
      const requestedStaffId = new URLSearchParams(window.location.search).get(
        "staff"
      );
      const requestedMember = members.find(
        (member) => member.id === requestedStaffId
      );
      if (requestedMember) openEditor(requestedMember);
    } catch (error) {
      setMessage(`遊戲卡資料讀取失敗：${error.message}`);
    }
  };

  previewImage?.addEventListener("error", () => {
    previewImage.hidden = true;
    previewEmpty.textContent = "圖片預覽載入失敗";
    previewEmpty.hidden = false;
  });
  previewImage?.addEventListener("load", () => {
    previewEmpty.textContent = "沒有可用圖片";
  });
  [statusFilter, visibilityFilter].forEach((element) =>
    element?.addEventListener("change", renderList)
  );
  searchFilter?.addEventListener("input", renderList);
  form?.elements.month_no.addEventListener("change", renderFormPreview);
  form?.elements.mark.addEventListener("change", renderFormPreview);
  form?.elements.card_title.addEventListener("input", renderFormPreview);
  form?.elements.card_image_url.addEventListener("input", renderFormPreview);
  fileInput?.addEventListener("change", () => {
    const file = fileInput.files?.[0];
    if (file) selectImage(file);
  });
  uploadButton?.addEventListener("click", async () => {
    if (!pendingImage) return;
    setMessage("");
    setButtonBusy(uploadButton, true, "上傳中...");
    try {
      await uploadPendingImage();
      setMessage("專用卡面已上傳並填入 public URL。", "success");
    } catch (error) {
      setMessage(`圖片上傳失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  });
  list?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-game-card]");
    if (!button) return;
    const member = members.find(
      (item) => item.id === button.dataset.editGameCard
    );
    if (member) openEditor(member);
  });
  autoAssignButton?.addEventListener("click", autoAssign);
  cancelButton?.addEventListener("click", closeEditor);
  form?.addEventListener("submit", saveSettings);

  if (window.ADMIN_PROFILE) {
    init(window.ADMIN_PROFILE);
  } else {
    window.addEventListener("admin-auth-ready", (event) => init(event.detail), {
      once: true,
    });
  }
})();
