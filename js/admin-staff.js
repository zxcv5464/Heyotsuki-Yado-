(() => {
  const client = window.SUPABASE_CLIENT;
  const bucket = "heyotsuki-images";
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

  const form = document.querySelector("[data-staff-form]");
  const editor = document.querySelector("[data-staff-editor]");
  const denied = document.querySelector("[data-staff-denied]");
  const message = document.querySelector("[data-staff-message]");
  const listSection = document.querySelector("[data-staff-list-section]");
  const list = document.querySelector("[data-staff-list]");
  const count = document.querySelector("[data-staff-count]");
  const newButton = document.querySelector("[data-new-staff]");
  const cancelButton = document.querySelector("[data-cancel-edit]");
  const uploadButton = document.querySelector("[data-upload-image]");
  const fileInput = document.querySelector("[data-image-file]");
  const preview = document.querySelector("[data-image-preview]");
  const previewEmpty = document.querySelector("[data-image-empty]");
  const submitButton = form?.querySelector('button[type="submit"]');

  let members = [];
  let pendingImage = null;
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

  const showPreview = (url) => {
    const safeUrl = safeImageUrl(url);
    if (!safeUrl) {
      preview.hidden = true;
      preview.removeAttribute("src");
      previewEmpty.hidden = false;
      return;
    }
    preview.src = safeUrl;
    preview.hidden = false;
    previewEmpty.hidden = true;
  };

  preview?.addEventListener("error", () => {
    preview.hidden = true;
    previewEmpty.textContent = "圖片預覽載入失敗";
    previewEmpty.hidden = false;
  });

  preview?.addEventListener("load", () => {
    previewEmpty.textContent = "尚未選擇圖片";
  });

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
    return "staff";
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

  const selectImage = async (file) => {
    setMessage("");
    setButtonBusy(uploadButton, true, "轉換中...");
    try {
      const blob = await convertToWebp(file);
      if (pendingImage?.previewUrl) {
        URL.revokeObjectURL(pendingImage.previewUrl);
      }
      const previewUrl = URL.createObjectURL(blob);
      pendingImage = {
        blob,
        originalName: file.name,
        previewUrl,
      };
      preview.src = previewUrl;
      preview.hidden = false;
      previewEmpty.hidden = true;
      uploadButton.disabled = false;
      setMessage("圖片已轉成 WebP，尚未上傳。", "success");
    } catch (error) {
      pendingImage = null;
      setMessage(error.message || "圖片轉換失敗。");
      uploadButton.disabled = true;
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const uploadPendingImage = async () => {
    if (!pendingImage) return form.elements.image_url.value.trim();

    const slug = normalizeSlug(
      form.elements.name.value,
      pendingImage.originalName.replace(/\.[^.]+$/, "")
    );
    let path = "";
    let uploadError = null;

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const timestamp = formatTimestamp(
        new Date(Date.now() + (uploadSequence + attempt) * 1000)
      );
      path = `staff/${timestamp}-${slug}.webp`;
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

    form.elements.image_url.value = data.publicUrl;
    showPreview(data.publicUrl);
    URL.revokeObjectURL(pendingImage.previewUrl);
    pendingImage = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    return data.publicUrl;
  };

  const resetForm = () => {
    if (pendingImage?.previewUrl) {
      URL.revokeObjectURL(pendingImage.previewUrl);
    }
    form.reset();
    form.elements.id.value = "";
    form.elements.is_visible.checked = true;
    form.elements.is_reservable.checked = true;
    pendingImage = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    document.querySelector("#staff-form-title").textContent = "新增湯娘";
    showPreview("");
  };

  const openEditor = (member = null) => {
    setMessage("");
    resetForm();
    if (member) {
      document.querySelector("#staff-form-title").textContent = "編輯湯娘";
      form.elements.id.value = member.id;
      form.elements.name.value = member.name || "";
      form.elements.subtitle.value = member.subtitle || "";
      form.elements.quote.value = String(member.quote || "").replace(
        /<br\s*\/?>/gi,
        "\n"
      );
      form.elements.role.value = member.role || "";
      form.elements.image_url.value = member.image_url || "";
      form.elements.is_visible.checked = Boolean(member.is_visible);
      form.elements.is_reservable.checked = Boolean(member.is_reservable);
      form.elements.sort_order.value = member.sort_order ?? "";
      showPreview(member.image_url);
    }
    editor.hidden = false;
    editor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const closeEditor = () => {
    resetForm();
    editor.hidden = true;
  };

  const renderList = () => {
    count.textContent = `共 ${members.length} 筆`;
    list.innerHTML = members
      .map((member) => {
        const imageUrl = safeImageUrl(member.image_url);
        const gameSettings = member.gameSettings;
        const visibility = member.is_visible
          ? '<span class="status-badge status-badge-visible">顯示中</span>'
          : '<span class="status-badge status-badge-hidden">已隱藏</span>';
        const reservable = member.is_reservable
          ? '<span class="status-badge status-badge-visible">可指定</span>'
          : '<span class="status-badge status-badge-hidden">不開放指定</span>';
        const gameStatus = !gameSettings
          ? '<span class="status-badge status-badge-featured">遊戲卡未設定</span>'
          : gameSettings.is_game_enabled
            ? '<span class="status-badge status-badge-visible">遊戲卡啟用</span>'
            : '<span class="status-badge status-badge-hidden">遊戲卡停用</span>';
        return `
          <article class="staff-admin-row${member.is_visible ? "" : " is-hidden"}">
            <div class="staff-order">${escapeHtml(member.sort_order)}</div>
            <div class="staff-thumb">
              ${imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(member.name)}" loading="lazy">` : "<span>無圖片</span>"}
            </div>
            <div class="staff-summary">
              <h3>${escapeHtml(member.name)}</h3>
              <p>${escapeHtml(member.subtitle)}</p>
              <small>${escapeHtml(member.role)}</small>
            </div>
            <div class="staff-visibility">${visibility}${reservable}${gameStatus}</div>
            <div class="staff-row-actions">
              <button class="text-button" data-edit-id="${escapeHtml(member.id)}" type="button">編輯</button>
              <button class="text-button" data-toggle-id="${escapeHtml(member.id)}" type="button">${member.is_visible ? "隱藏" : "顯示"}</button>
              <a class="text-button text-button-link" href="game-cards.html?staff=${encodeURIComponent(member.id)}">遊戲卡</a>
            </div>
          </article>`;
      })
      .join("");
  };

  const loadMembers = async () => {
    const [staffResult, settingsResult] = await Promise.all([
      client
        .from("staff_members")
        .select(
          "id, name, subtitle, quote, role, image_url, is_visible, is_reservable, sort_order"
        )
        .order("sort_order", { ascending: true }),
      client
        .from("game_staff_card_settings")
        .select("staff_id, is_game_enabled"),
    ]);

    if (staffResult.error) {
      setMessage(`湯娘資料讀取失敗：${staffResult.error.message}`);
      return;
    }
    if (settingsResult.error) {
      console.warn("遊戲卡設定讀取失敗，湯娘 CRUD 仍可繼續。", settingsResult.error);
    }
    const settingsByStaff = new Map(
      (settingsResult.data || []).map((settings) => [settings.staff_id, settings])
    );
    members = (staffResult.data || []).map((member) => ({
      ...member,
      gameSettings: settingsByStaff.get(member.id) || null,
    }));
    renderList();
  };

  const saveMember = async (event) => {
    event.preventDefault();
    setMessage("");
    setButtonBusy(submitButton, true, "儲存中...");
    setButtonBusy(uploadButton, true, "處理圖片中...");

    try {
      const imageUrl = pendingImage
        ? await uploadPendingImage()
        : form.elements.image_url.value.trim();
      const id = form.elements.id.value;
      const sortInput = form.elements.sort_order.value.trim();
      const maxSort = members.reduce(
        (maximum, member) => Math.max(maximum, Number(member.sort_order) || 0),
        0
      );
      const payload = {
        name: form.elements.name.value.trim(),
        subtitle: form.elements.subtitle.value.trim(),
        quote: form.elements.quote.value.trim(),
        role: form.elements.role.value.trim(),
        image_url: imageUrl,
        is_visible: form.elements.is_visible.checked,
        is_reservable: form.elements.is_reservable.checked,
        sort_order: sortInput ? Number(sortInput) : maxSort + 10,
      };

      const query = id
        ? client.from("staff_members").update(payload).eq("id", id)
        : client.from("staff_members").insert(payload);
      const { error } = await query;
      if (error) throw error;

      setMessage("湯娘資料已儲存。", "success");
      closeEditor();
      await loadMembers();
    } catch (error) {
      setMessage(`儲存失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(submitButton, false);
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const toggleVisibility = async (id) => {
    const member = members.find((item) => item.id === id);
    if (!member) return;

    const { error } = await client
      .from("staff_members")
      .update({ is_visible: !member.is_visible })
      .eq("id", id);
    if (error) {
      setMessage(`狀態更新失敗：${error.message}`);
      return;
    }
    setMessage(member.is_visible ? "湯娘已隱藏。" : "湯娘已顯示。", "success");
    await loadMembers();
  };

  const init = async (profile) => {
    if (!window.ADMIN_CAN?.("staff.manage")) {
      denied.hidden = false;
      editor.hidden = true;
      listSection.hidden = true;
      newButton.hidden = true;
      return;
    }

    newButton.hidden = false;
    listSection.hidden = false;
    await loadMembers();
  };

  newButton?.addEventListener("click", () => openEditor());
  cancelButton?.addEventListener("click", closeEditor);
  fileInput?.addEventListener("change", () => {
    const file = fileInput.files?.[0];
    if (file) selectImage(file);
  });
  form?.elements.image_url.addEventListener("input", (event) => {
    if (!pendingImage) showPreview(event.target.value);
  });
  uploadButton?.addEventListener("click", async () => {
    if (!pendingImage) return;
    setMessage("");
    setButtonBusy(uploadButton, true, "上傳中...");
    try {
      await uploadPendingImage();
      setMessage("圖片已上傳並填入 public URL。", "success");
    } catch (error) {
      setMessage(`圖片上傳失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  });
  form?.addEventListener("submit", saveMember);
  list?.addEventListener("click", (event) => {
    const editButton = event.target.closest("[data-edit-id]");
    const toggleButton = event.target.closest("[data-toggle-id]");
    if (editButton) {
      openEditor(members.find((member) => member.id === editButton.dataset.editId));
    } else if (toggleButton) {
      toggleVisibility(toggleButton.dataset.toggleId);
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
