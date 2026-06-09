(() => {
  const container = document.querySelector("#menu-choice-grid");
  const fallbackMenus = window.SITE_CONFIG?.menus || [];
  if (!container) return;

  const escapeHtml = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (character) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[character]
    );

  const safeHref = (value, fallback = "#") => {
    const href = String(value ?? "").trim();
    if (/^https:\/\//i.test(href)) return href;
    if (
      /^(?:\.{1,2}\/)?[a-z0-9][a-z0-9._~/-]*(?:[?#][^\s]*)?$/i.test(href) &&
      !href.includes("\\") &&
      !href.startsWith("//")
    ) {
      return href;
    }
    return fallback;
  };

  const renderMenus = (menus) => {
    container.innerHTML = menus
      .map((menu, index) => {
        const dark = menu.theme === "dark";
        return `
          <a class="menu-choice-card group relative min-h-[280px] md:min-h-[360px] ${
            dark
              ? "bg-stone-900 text-white border-stone-800 hover:shadow-[0_20px_50px_rgba(45,41,38,0.18)]"
              : "bg-white/70 text-on-surface border-stone-100 hover:shadow-[0_20px_50px_rgba(45,41,38,0.1)]"
          } border shadow-sm p-9 sm:p-12 md:p-16 flex flex-col justify-between overflow-hidden transition-all duration-500 hover:-translate-y-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-800/30 ${
            index > 0 ? "md:mt-12" : ""
          }" href="${escapeHtml(safeHref(menu.href))}">
            <div class="absolute inset-0 washi-grain ${
              dark ? "opacity-20" : ""
            } pointer-events-none"></div>
            <div class="relative z-10">
              <span class="font-label text-[9px] tracking-[0.5em] uppercase ${
                dark ? "text-red-300" : "text-red-800"
              }">${escapeHtml(menu.englishTitle)}</span>
              <h2 class="mt-6 font-headline text-3xl sm:text-4xl font-bold tracking-[0.25em] ${
                dark ? "" : "text-primary"
              }">${escapeHtml(menu.title)}</h2>
              <p class="mt-8 ${
                dark ? "text-stone-400" : "text-stone-500"
              } text-base sm:text-lg leading-[2] tracking-[0.12em]">${escapeHtml(menu.description)}</p>
            </div>
            <div class="relative z-10 mt-12 flex items-center gap-5 ${
              dark ? "text-white" : "text-primary"
            }">
              <span class="font-label text-[10px] tracking-[0.4em] uppercase">查看菜單</span>
              <span class="w-16 h-px ${
                dark
                  ? "bg-stone-600 group-hover:bg-red-400"
                  : "bg-stone-300 group-hover:bg-red-800"
              } group-hover:w-24 transition-all duration-500"></span>
            </div>
          </a>`;
      })
      .join("");
  };

  renderMenus(fallbackMenus);
  window.DATA_PROVIDER?.getMenus().then(renderMenus);
})();
