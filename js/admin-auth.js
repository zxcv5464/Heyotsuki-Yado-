(() => {
  const client = window.SUPABASE_CLIENT;
  const page = document.body.dataset.adminPage;
  const allowedRoles = new Set(["owner", "admin", "staff"]);

  window.addEventListener("pageshow", (event) => {
    if (
      [
        "dashboard",
        "settings",
        "staff",
        "game-cards",
        "scenery-cards",
        "menu",
        "reservations",
        "reservation-form",
        "orders",
        "order-specials",
        "reports",
        "payroll",
      ].includes(page) &&
      event.persisted
    ) {
      window.location.reload();
    }
  });

  const redirect = (target) => {
    window.location.replace(target);
  };

  const setMessage = (message, type = "error") => {
    const element = document.querySelector("[data-auth-message]");
    if (!element) return;

    element.textContent = message;
    element.dataset.type = type;
    element.hidden = !message;
  };

  const setBusy = (button, busy, busyText) => {
    if (!button) return;
    if (!button.dataset.defaultText) {
      button.dataset.defaultText = button.textContent;
    }
    button.disabled = busy;
    button.textContent = busy ? busyText : button.dataset.defaultText;
  };

  const requireClient = () => {
    if (client) return true;
    setMessage("Supabase 尚未正確設定，請聯絡網站管理員。");
    return false;
  };

  const signOutAndReturn = async (reason) => {
    if (client) {
      await client.auth.signOut();
    }
    const query = reason ? `?reason=${encodeURIComponent(reason)}` : "";
    redirect(`login.html${query}`);
  };

  const initLogin = async () => {
    if (!requireClient()) return;

    const reason = new URLSearchParams(window.location.search).get("reason");
    if (reason) setMessage(reason);

    const { data, error } = await client.auth.getSession();
    if (!error && data.session) {
      redirect("index.html");
      return;
    }

    const form = document.querySelector("[data-login-form]");
    const submitButton = form?.querySelector('button[type="submit"]');
    form?.addEventListener("submit", async (event) => {
      event.preventDefault();
      setMessage("");
      setBusy(submitButton, true, "登入中...");

      const formData = new FormData(form);
      const email = String(formData.get("email") || "").trim();
      const password = String(formData.get("password") || "");

      const { error: signInError } = await client.auth.signInWithPassword({
        email,
        password,
      });

      if (signInError) {
        setMessage("登入失敗，請確認 Email 與密碼。");
        setBusy(submitButton, false);
        return;
      }

      redirect("index.html");
    });
  };

  const initProtectedPage = async () => {
    if (!requireClient()) return;

    const { data, error } = await client.auth.getSession();
    const session = data?.session;
    if (error || !session) {
      redirect("login.html");
      return;
    }

    const { data: profile, error: profileError } = await client
      .from("admin_profiles")
      .select("display_name, role, is_active")
      .eq("id", session.user.id)
      .maybeSingle();

    if (profileError || !profile) {
      await signOutAndReturn("此帳號尚未建立後台權限。");
      return;
    }

    if (!profile.is_active) {
      await signOutAndReturn("此帳號已停用。");
      return;
    }

    if (!allowedRoles.has(profile.role)) {
      await signOutAndReturn("此帳號沒有後台存取權限。");
      return;
    }

    const nameElement = document.querySelector("[data-admin-name]");
    const roleElement = document.querySelector("[data-admin-role]");
    if (nameElement) nameElement.textContent = profile.display_name;
    if (roleElement) roleElement.textContent = profile.role;

    document.body.dataset.authReady = "true";
    window.ADMIN_PROFILE = profile;
    window.dispatchEvent(
      new CustomEvent("admin-auth-ready", {
        detail: { ...profile, profile, session, client },
      })
    );

    const signOutButton = document.querySelector("[data-sign-out]");
    signOutButton?.addEventListener("click", async () => {
      setBusy(signOutButton, true, "登出中...");
      await signOutAndReturn("");
    });

    client.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        redirect("login.html");
      }
    });
  };

  if (page === "login") {
    initLogin();
  } else if (
    [
      "dashboard",
      "settings",
      "staff",
      "game-cards",
      "scenery-cards",
      "menu",
      "reservations",
      "reservation-form",
      "orders",
      "order-specials",
      "reports",
      "payroll",
    ].includes(page)
  ) {
    initProtectedPage();
  }
})();
