(() => {
  const client = window.SUPABASE_CLIENT;
  const statusLabels = {
    pending: "待確認",
    confirmed: "已確認",
    cancelled: "已取消",
    completed: "已完成",
    no_show: "未到場",
  };
  const discordStatusLabels = {
    pending: "待推送",
    sent: "已推送",
    failed: "推送失敗",
    skipped: "已略過",
  };
  const coreFieldKeys = new Set([
    "customer_name",
    "contact",
    "reservation_date",
    "reservation_time",
    "party_size",
    "plan",
    "preferred_staff_name",
    "preferred_staff_2_name",
    "changing_together",
    "photo_service",
    "dessert_service",
    "note",
  ]);

  const workspace = document.querySelector("[data-reservations-workspace]");
  const message = document.querySelector("[data-reservations-message]");
  const list = document.querySelector("[data-reservation-list]");
  const count = document.querySelector("[data-reservation-count]");
  const statusFilter = document.querySelector("[data-status-filter]");
  const searchInput = document.querySelector("[data-reservation-search]");
  const dateSort = document.querySelector("[data-date-sort]");
  const showDeleted = document.querySelector("[data-show-deleted]");

  let reservations = [];
  let canEdit = false;
  let currentUserId = null;

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const setMessage = (text, type = "error") => {
    if (!message) return;
    message.textContent = text;
    message.dataset.type = type;
    message.hidden = !text;
  };

  const formatDateTime = (value) => {
    if (!value) return "無";
    return new Intl.DateTimeFormat("zh-TW", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value));
  };

  const detail = (label, value, full = false) => `
    <div class="reservation-detail${full ? " reservation-detail-full" : ""}">
      <dt>${escapeHtml(label)}</dt>
      <dd>${escapeHtml(value || "無")}</dd>
    </div>`;

  const normalizeFormAnswers = (formAnswers) => {
    if (!formAnswers || typeof formAnswers !== "object") return [];
    return Object.entries(formAnswers)
      .filter(([fieldKey]) => !coreFieldKeys.has(fieldKey))
      .map(([fieldKey, answer]) => {
        if (
          answer &&
          typeof answer === "object" &&
          !Array.isArray(answer)
        ) {
          return {
            fieldKey,
            label: answer.label || fieldKey,
            displayValue:
              answer.display_value ?? answer.value ?? "未填寫",
          };
        }
        return {
          fieldKey,
          label: fieldKey,
          displayValue: answer ?? "未填寫",
        };
      })
      .filter((answer) => String(answer.displayValue || "").trim());
  };

  const renderFormAnswers = (formAnswers) => {
    const answers = normalizeFormAnswers(formAnswers);
    if (!answers.length) return "";
    return `
      <section class="reservation-form-answers">
        <h4>其他表單回覆</h4>
        <dl class="reservation-details">
          ${answers
            .map((answer) =>
              detail(
                answer.label,
                String(answer.displayValue || "未填寫"),
                true
              )
            )
            .join("")}
        </dl>
      </section>`;
  };

  const renderDiscordMeta = (reservation) => {
    const parts = [
      `推送 ${Number(reservation.discord_attempts || 0)} 次`,
      reservation.discord_notified_at
        ? `最後通知 ${formatDateTime(reservation.discord_notified_at)}`
        : "",
    ].filter(Boolean);
    return `
      <div class="reservation-discord-meta">
        <span>${escapeHtml(parts.join("・"))}</span>
        ${
          reservation.discord_last_error
            ? `<span class="reservation-discord-error">${escapeHtml(reservation.discord_last_error)}</span>`
            : ""
        }
      </div>`;
  };

  const getVisibleReservations = () => {
    const query = searchInput.value.trim().toLowerCase();
    return reservations
      .filter((reservation) => {
        if (!showDeleted.checked && reservation.deleted_at) return false;
        if (
          statusFilter.value !== "all" &&
          reservation.status !== statusFilter.value
        ) {
          return false;
        }
        if (!query) return true;
        return [reservation.customer_name, reservation.contact].some((value) =>
          String(value || "").toLowerCase().includes(query)
        );
      })
      .sort((left, right) => {
        const leftValue = `${left.reservation_date} ${left.reservation_time}`;
        const rightValue = `${right.reservation_date} ${right.reservation_time}`;
        return dateSort.value === "desc"
          ? rightValue.localeCompare(leftValue)
          : leftValue.localeCompare(rightValue);
      });
  };

  const renderList = () => {
    const visible = getVisibleReservations();
    count.textContent = `共 ${visible.length} 筆`;
    if (!visible.length) {
      list.innerHTML = '<p class="empty-state">目前沒有符合條件的預約。</p>';
      return;
    }

    list.innerHTML = visible
      .map((reservation) => {
        const deletedBadge = reservation.deleted_at
          ? '<span class="status-badge status-badge-hidden">已刪除</span>'
          : "";
        const discordBadgeClass =
          reservation.discord_status === "sent"
            ? "status-badge-visible"
            : reservation.discord_status === "failed"
              ? "status-badge-hidden"
              : "status-badge-featured";
        const discordBadge = `
          <span class="status-badge ${discordBadgeClass}">
            Discord ${escapeHtml(
              discordStatusLabels[reservation.discord_status] ||
                reservation.discord_status ||
                "待推送"
            )}
          </span>`;
        const editControls =
          canEdit && !reservation.deleted_at
            ? `
              <div class="reservation-admin-edit">
                <div class="field">
                  <label for="status-${escapeHtml(reservation.id)}">預約狀態</label>
                  <select id="status-${escapeHtml(reservation.id)}" data-row-status>
                    ${Object.entries(statusLabels)
                      .map(
                        ([value, label]) =>
                          `<option value="${value}"${reservation.status === value ? " selected" : ""}>${label}</option>`
                      )
                      .join("")}
                  </select>
                </div>
                <div class="field">
                  <label for="note-${escapeHtml(reservation.id)}">管理員備註</label>
                  <textarea id="note-${escapeHtml(reservation.id)}" data-row-admin-note rows="3">${escapeHtml(reservation.admin_note || "")}</textarea>
                </div>
                <div class="reservation-row-actions">
                  <button class="admin-button admin-button-small" data-save-reservation="${escapeHtml(reservation.id)}" type="button">儲存</button>
                  <button class="admin-button admin-button-secondary admin-button-small" data-retry-discord="${escapeHtml(reservation.id)}" type="button">重新推送 Discord</button>
                  <button class="admin-button admin-button-secondary admin-button-small" data-delete-reservation="${escapeHtml(reservation.id)}" type="button">刪除</button>
                </div>
              </div>`
            : detail("管理員備註", reservation.admin_note, true);

        return `
          <article class="reservation-admin-card${reservation.deleted_at ? " is-deleted" : ""}" data-reservation-id="${escapeHtml(reservation.id)}">
            <header class="reservation-admin-card-header">
              <div>
                <p class="reservation-card-date">${escapeHtml(reservation.reservation_date)}・${escapeHtml(reservation.reservation_time)}</p>
                <h3>${escapeHtml(reservation.customer_name)}</h3>
              </div>
              <div class="reservation-card-badges">
                <span class="status-badge reservation-status reservation-status-${escapeHtml(reservation.status)}">${escapeHtml(statusLabels[reservation.status] || reservation.status)}</span>
                ${discordBadge}
                ${deletedBadge}
              </div>
            </header>
            <dl class="reservation-details">
              ${detail("聯絡方式", reservation.contact)}
              ${detail("人數", `${reservation.party_size} 人`)}
              ${detail("方案", reservation.plan)}
              ${detail("第一位指定", reservation.preferred_staff_name)}
              ${detail("第二位指定", reservation.preferred_staff_2_name)}
              ${detail("拍照服務", reservation.photo_service)}
              ${detail("茶點安排", reservation.dessert_service)}
              ${detail("混浴確認", reservation.changing_together)}
              ${detail("建立時間", formatDateTime(reservation.created_at))}
              ${detail("備註", reservation.note, true)}
              ${
                reservation.deleted_at
                  ? detail(
                      "刪除資訊",
                      `${formatDateTime(reservation.deleted_at)}${
                        reservation.delete_reason
                          ? `・${reservation.delete_reason}`
                          : ""
                      }`,
                      true
                    )
                  : ""
              }
            </dl>
            ${renderDiscordMeta(reservation)}
            ${renderFormAnswers(reservation.form_answers)}
            ${editControls}
          </article>`;
      })
      .join("");
  };

  const loadReservations = async () => {
    setMessage("");
    const { data, error } = await client
      .from("reservations")
      .select(
        "id, customer_name, contact, reservation_date, reservation_time, party_size, changing_together, plan, preferred_staff_name, preferred_staff_2_name, photo_service, dessert_service, note, form_answers, status, admin_note, discord_status, discord_attempts, discord_last_error, discord_notified_at, deleted_at, delete_reason, created_at"
      )
      .order("reservation_date", { ascending: true })
      .order("reservation_time", { ascending: true });
    if (error) {
      setMessage(`預約資料載入失敗：${error.message}`);
      return;
    }
    reservations = data || [];
    renderList();
  };

  const saveReservation = async (button) => {
    const id = button.dataset.saveReservation;
    const card = button.closest("[data-reservation-id]");
    const status = card.querySelector("[data-row-status]").value;
    const adminNote = card.querySelector("[data-row-admin-note]").value.trim();
    button.disabled = true;
    const { error } = await client
      .from("reservations")
      .update({ status, admin_note: adminNote || null })
      .eq("id", id);
    button.disabled = false;
    if (error) {
      if (
        error.code === "23505" ||
        /reservations_active_slot_unique_idx|duplicate key/i.test(
          error.message || ""
        )
      ) {
        setMessage(
          "此日期與時段已有其他有效預約，無法改回待確認或已確認。"
        );
        await loadReservations();
        return;
      }
      setMessage(`預約更新失敗：${error.message}`);
      return;
    }
    setMessage("預約資料已更新。", "success");
    await loadReservations();
  };

  const softDeleteReservation = async (button) => {
    const id = button.dataset.deleteReservation;
    const reservation = reservations.find((entry) => entry.id === id);
    if (!reservation) return;
    const confirmed = window.confirm(
      `確定要刪除 ${reservation.customer_name} 於 ${reservation.reservation_date} ${reservation.reservation_time} 的預約嗎？\n\n此操作會將資料標記為已刪除。`
    );
    if (!confirmed) return;
    const reason = window.prompt("刪除原因（可留空）：", "");
    if (reason === null) return;
    if (!currentUserId) {
      setMessage("找不到目前登入者，請重新登入後再試。");
      return;
    }

    button.disabled = true;
    const { error } = await client
      .from("reservations")
      .update({
        deleted_at: new Date().toISOString(),
        deleted_by: currentUserId,
        delete_reason: reason.trim() || null,
      })
      .eq("id", id);
    button.disabled = false;
    if (error) {
      setMessage(`預約刪除失敗：${error.message}`);
      return;
    }
    setMessage("預約已標記為刪除。", "success");
    await loadReservations();
  };

  const retryDiscordNotification = async (button) => {
    const id = button.dataset.retryDiscord;
    const reservation = reservations.find((entry) => entry.id === id);
    if (!reservation || reservation.deleted_at) return;
    const confirmed = window.confirm(
      `確定要重新推送 ${reservation.customer_name} 於 ${reservation.reservation_date} ${reservation.reservation_time} 的 Discord 預約通知嗎？`
    );
    if (!confirmed) return;

    button.disabled = true;
    setMessage("");
    try {
      const { data, error } = await client.functions.invoke(
        "notify-reservation-discord",
        {
          body: {
            reservation_id: reservation.id,
            force: true,
          },
        }
      );
      if (error || data?.error) {
        setMessage(
          `Discord 重新推送失敗：${data?.error || error?.message || "請稍後再試。"}`
        );
        return;
      }
      setMessage("Discord 預約通知已重新推送。", "success");
      await loadReservations();
    } catch (error) {
      console.error("Discord reservation retry failed.", error);
      setMessage(
        `Discord 重新推送失敗：${error?.message || "請稍後再試。"}`
      );
    } finally {
      button.disabled = false;
    }
  };

  const init = async (profile) => {
    canEdit = window.ADMIN_CAN?.("reservations.manage") === true;
    const { data } = await client.auth.getSession();
    currentUserId = data?.session?.user?.id || null;
    workspace.hidden = false;
    await loadReservations();
  };

  [statusFilter, searchInput, dateSort, showDeleted].forEach((control) => {
    control?.addEventListener("input", renderList);
    control?.addEventListener("change", renderList);
  });

  list?.addEventListener("click", (event) => {
    const saveButton = event.target.closest("[data-save-reservation]");
    const retryDiscordButton = event.target.closest("[data-retry-discord]");
    const deleteButton = event.target.closest("[data-delete-reservation]");
    if (saveButton && canEdit) {
      saveReservation(saveButton);
    } else if (retryDiscordButton && canEdit) {
      retryDiscordNotification(retryDiscordButton);
    } else if (deleteButton && canEdit) {
      softDeleteReservation(deleteButton);
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
