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

  const content = document.querySelector("[data-scenery-card-content]");
  const denied = document.querySelector("[data-scenery-card-denied]");
  const message = document.querySelector("[data-scenery-card-message]");
  const newButton = document.querySelector("[data-new-scenery-card]");
  const list = document.querySelector("[data-scenery-card-list]");
  const count = document.querySelector("[data-scenery-card-count]");
  const editor = document.querySelector("[data-scenery-card-editor]");
  const form = document.querySelector("[data-scenery-card-form]");
  const cancelButton = document.querySelector("[data-cancel-scenery-card]");
  const deleteButton = document.querySelector("[data-delete-scenery-card]");
  const fileInput = document.querySelector("[data-scenery-card-image-file]");
  const uploadButton = document.querySelector("[data-upload-scenery-card-image]");
  const submitButton = form?.querySelector('button[type="submit"]');
  const statusFilter = document.querySelector("[data-filter-status]");
  const monthFilter = document.querySelector("[data-filter-month]");
  const searchFilter = document.querySelector("[data-filter-search]");
  const previewImage = document.querySelector("[data-scenery-card-preview-image]");
  const previewEmpty = document.querySelector("[data-scenery-card-preview-empty]");

  let months = [];
  let cards = [];
  let editingCard = null;
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
      const url = new URL(value);
      return url.protocol === "https:" ? url.href : "";
    } catch {
      return "";
    }
  };

  const monthFor = (monthNo) =>
    months.find((month) => Number(month.month_no) === Number(monthNo));

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
    return "scenery-card";
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
          else reject(new Error("無法輸出 WebP 圖片。"));
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
        reject(new Error("圖片讀取失敗。"));
      };
      image.src = url;
    });

  const convertToWebp = async (file) => {
    if (!acceptedTypes.has(file.type)) {
      throw new Error("請上傳 JPG、PNG、WebP 或 GIF 圖片。");
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
    document.querySelector("[data-scenery-card-preview-month]").textContent =
      month?.month_label || "尚未選擇月份";
    document.querySelector("[data-scenery-card-preview-name]").textContent =
      form.elements.name.value.trim() || "月景牌名稱";
    document.querySelector("[data-scenery-card-preview-meta]").textContent =
      `${seasonLabels[month?.season] || "季節"} / ${markLabels[mark] || "印記"}`;
    document.querySelector("[data-scenery-card-preview-title]").textContent =
      form.elements.card_title.value.trim();
    form.elements.season.value = seasonLabels[month?.season] || "";

    if (!pendingImage) {
      setPreviewImage(form.elements.image_url.value.trim());
    }
  };

  const selectImage = async (file) => {
    setMessage("");
    setButtonBusy(uploadButton, true, "處理中...");
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
      setMessage("圖片已轉為 WebP，請上傳或直接儲存。", "success");
    } catch (error) {
      pendingImage = null;
      uploadButton.disabled = true;
      setMessage(error.message || "圖片處理失敗。");
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const uploadPendingImage = async () => {
    if (!pendingImage) {
      return form.elements.image_url.value.trim();
    }

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
      path = `game-scenery/${timestamp}-${slug}.webp`;
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
      throw new Error("無法取得圖片 public URL。");
    }

    form.elements.image_url.value = data.publicUrl;
    setPreviewImage(data.publicUrl);
    URL.revokeObjectURL(pendingImage.previewUrl);
    pendingImage = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    return data.publicUrl;
  };

  const renderSummary = () => {
    const activeCount = cards.filter((card) => card.is_active).length;
    document.querySelector("[data-summary-total]").textContent = cards.length;
    document.querySelector("[data-summary-active]").textContent = activeCount;
    document.querySelector("[data-summary-disabled]").textContent =
      cards.length - activeCount;

    const monthCounts = Object.fromEntries(months.map((month) => [month.month_no, 0]));
    const markCounts = Object.fromEntries(
      Object.keys(markLabels).map((mark) => [mark, 0])
    );
    cards.forEach((card) => {
      if (!card.is_active) return;
      if (monthCounts[card.month_no] !== undefined) monthCounts[card.month_no] += 1;
      if (markCounts[card.mark] !== undefined) markCounts[card.mark] += 1;
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

  const matchesFilters = (card) => {
    const status = statusFilter.value;
    const month = monthFilter.value;
    const search = searchFilter.value.trim().toLocaleLowerCase("zh-Hant");
    if (status === "enabled" && !card.is_active) return false;
    if (status === "disabled" && card.is_active) return false;
    if (month !== "all" && Number(card.month_no) !== Number(month)) return false;
    if (search && !card.name.toLocaleLowerCase("zh-Hant").includes(search)) return false;
    return true;
  };

  const renderList = () => {
    const filteredCards = cards.filter(matchesFilters);
    count.textContent = `顯示 ${filteredCards.length} / ${cards.length} 張`;
    list.innerHTML = filteredCards.length
      ? filteredCards
          .map((card) => {
            const month = monthFor(card.month_no);
            const imageUrl = safeImageUrl(card.image_url);
            const status = card.is_active
              ? '<span class="status-badge status-badge-visible">遊戲啟用</span>'
              : '<span class="status-badge status-badge-hidden">停用</span>';
            return `
              <article class="game-card-admin-row${card.is_active ? "" : " is-hidden"}">
                <div class="staff-thumb game-card-admin-thumb">
                  ${imageUrl ? `<img data-scenery-card-thumb="${escapeHtml(card.id)}" alt="${escapeHtml(card.name)}" loading="lazy" decoding="async">` : "<span>無圖片</span>"}
                </div>
                <div class="staff-summary">
                  <h3>${escapeHtml(card.name)}</h3>
                  <p>${month ? `${escapeHtml(month.month_label)}・${escapeHtml(seasonLabels[month.season])}` : "月份未設定"}</p>
                  <small>${escapeHtml(markLabels[card.mark] || card.mark)}${card.card_title ? `・${escapeHtml(card.card_title)}` : ""}</small>
                </div>
                <div class="staff-visibility">${status}</div>
                <div class="staff-row-actions">
                  <button class="text-button" data-edit-scenery-card="${escapeHtml(card.id)}" type="button">編輯月景牌</button>
                </div>
              </article>`;
          })
          .join("")
      : '<p class="admin-empty">沒有符合條件的月景牌。</p>';

    filteredCards.forEach((card) => {
      const imageUrl = safeImageUrl(card.image_url);
      if (!imageUrl) return;
      const image = list.querySelector(
        `img[data-scenery-card-thumb="${CSS.escape(card.id)}"]`
      );
      if (!image) return;
      image.addEventListener(
        "error",
        () => {
          image.replaceWith(document.createTextNode("圖片載入失敗"));
        },
        { once: true }
      );
      image.src = imageUrl;
    });
  };

  const loadData = async () => {
    const [monthResult, cardResult] = await Promise.all([
      client.rpc("get_game_month_catalog"),
      client
        .from("game_scenery_cards")
        .select("id, name, month_no, mark, card_title, image_url, is_active, sort_order")
        .order("sort_order", { ascending: true })
        .order("created_at", { ascending: true }),
    ]);

    const error = monthResult.error || cardResult.error;
    if (error) throw error;

    months = monthResult.data || [];
    cards = cardResult.data || [];

    const monthOptions = months
      .map(
        (month) =>
          `<option value="${month.month_no}">${escapeHtml(month.month_label)}</option>`
      )
      .join("");
    form.elements.month_no.innerHTML = monthOptions;
    monthFilter.innerHTML =
      '<option value="all">全部月份</option>' + monthOptions;
    renderSummary();
    renderList();
  };

  const resetEditor = () => {
    if (pendingImage?.previewUrl) URL.revokeObjectURL(pendingImage.previewUrl);
    form.reset();
    form.elements.id.value = "";
    form.elements.is_active.checked = true;
    form.elements.sort_order.value = "0";
    pendingImage = null;
    editingCard = null;
    fileInput.value = "";
    uploadButton.disabled = true;
    deleteButton.hidden = true;
    setPreviewImage("");
    renderFormPreview();
  };

  const openEditor = (card = null) => {
    setMessage("");
    resetEditor();
    editingCard = card;
    if (card) {
      form.elements.id.value = card.id;
      form.elements.name.value = card.name;
      form.elements.month_no.value = card.month_no;
      form.elements.mark.value = card.mark;
      form.elements.card_title.value = card.card_title || "";
      form.elements.image_url.value = card.image_url || "";
      form.elements.is_active.checked = card.is_active;
      form.elements.sort_order.value = card.sort_order ?? 0;
      deleteButton.hidden = false;
    }
    document.querySelector("#scenery-card-form-title").textContent = card
      ? `編輯 ${card.name}`
      : "新增月景牌";
    renderFormPreview();
    editor.hidden = false;
    editor.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const closeEditor = () => {
    resetEditor();
    editor.hidden = true;
  };

  const saveCard = async (event) => {
    event.preventDefault();
    setMessage("");
    setButtonBusy(submitButton, true, "儲存中...");
    setButtonBusy(uploadButton, true, "上傳中...");
    try {
      const imageUrl = pendingImage
        ? await uploadPendingImage()
        : form.elements.image_url.value.trim();
      if (!safeImageUrl(imageUrl)) {
        throw new Error("圖片網址必須是 HTTPS 絕對網址。");
      }

      const payload = {
        name: form.elements.name.value.trim(),
        month_no: Number(form.elements.month_no.value),
        mark: form.elements.mark.value,
        card_title: form.elements.card_title.value.trim() || null,
        image_url: imageUrl,
        is_active: form.elements.is_active.checked,
        sort_order: Number(form.elements.sort_order.value || 0),
      };
      const id = form.elements.id.value;
      const result = id
        ? await client.from("game_scenery_cards").update(payload).eq("id", id)
        : await client.from("game_scenery_cards").insert(payload);
      if (result.error) throw result.error;

      closeEditor();
      await loadData();
      setMessage("月景牌已儲存。", "success");
    } catch (error) {
      setMessage(`儲存失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(submitButton, false);
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  };

  const deleteCard = async () => {
    if (!editingCard) return;
    if (!window.confirm(`確定刪除「${editingCard.name}」？已開始的牌局不會被回溯修改。`)) {
      return;
    }
    setMessage("");
    setButtonBusy(deleteButton, true, "刪除中...");
    try {
      const { error } = await client
        .from("game_scenery_cards")
        .delete()
        .eq("id", editingCard.id);
      if (error) throw error;
      closeEditor();
      await loadData();
      setMessage("月景牌已刪除。", "success");
    } catch (error) {
      setMessage(`刪除失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(deleteButton, false);
    }
  };

  const init = async (profile) => {
    if (!editableRoles.has(profile.role)) {
      denied.hidden = false;
      content.hidden = true;
      newButton.hidden = true;
      return;
    }

    content.hidden = false;
    newButton.hidden = false;
    try {
      await loadData();
    } catch (error) {
      setMessage(`月景牌資料載入失敗：${error.message}`);
    }
  };

  previewImage?.addEventListener("error", () => {
    previewImage.hidden = true;
    previewEmpty.textContent = "圖片載入失敗";
    previewEmpty.hidden = false;
  });
  previewImage?.addEventListener("load", () => {
    previewEmpty.textContent = "尚未選擇圖片";
  });
  [statusFilter, monthFilter].forEach((element) =>
    element?.addEventListener("change", renderList)
  );
  searchFilter?.addEventListener("input", renderList);
  form?.elements.name.addEventListener("input", renderFormPreview);
  form?.elements.month_no.addEventListener("change", renderFormPreview);
  form?.elements.mark.addEventListener("change", renderFormPreview);
  form?.elements.card_title.addEventListener("input", renderFormPreview);
  form?.elements.image_url.addEventListener("input", renderFormPreview);
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
      setMessage("圖片已上傳並寫入網址欄位。", "success");
    } catch (error) {
      setMessage(`圖片上傳失敗：${error.message || "請稍後再試。"}`);
    } finally {
      setButtonBusy(uploadButton, false);
      uploadButton.disabled = !pendingImage;
    }
  });
  list?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-scenery-card]");
    if (!button) return;
    const card = cards.find((item) => item.id === button.dataset.editSceneryCard);
    if (card) openEditor(card);
  });
  newButton?.addEventListener("click", () => openEditor());
  cancelButton?.addEventListener("click", closeEditor);
  deleteButton?.addEventListener("click", deleteCard);
  form?.addEventListener("submit", saveCard);

  if (window.ADMIN_PROFILE) {
    init(window.ADMIN_PROFILE);
  } else {
    window.addEventListener("admin-auth-ready", (event) => init(event.detail), {
      once: true,
    });
  }
})();
