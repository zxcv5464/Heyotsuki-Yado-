(() => {
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

  const renderSite = (config, menuData = config?.menus || []) => {
    if (!config) return;

    const menus = Array.isArray(menuData) ? menuData : [];
    document.querySelectorAll("[data-config-href]").forEach((link) => {
      const configKey = link.dataset.configHref;
      const href = config[configKey];
      if (typeof href === "string" && href) {
        link.href = safeHref(href);
      }
    });

    const page = document.body.dataset.page;
    const bookingUrl = safeHref(config.bookingUrl);
    const threadsUrl = safeHref(config.threadsUrl);
    const discordUrl = safeHref(config.discordUrl);
    const links = [
      ["index", "index.html", "首頁"],
      ["rules", "rules.html", "入場規範"],
      ["staff", "staff.html", "湯娘"],
    ];
    const menuPages = ["menus", ...menus.map((menu) => menu.key)];
    const isMenuPage = menuPages.includes(page);
    const activeClass = "text-primary border-b-2 border-red-800 px-2 py-1";
    const defaultClass =
      "text-stone-800 hover:text-primary hover:bg-stone-800/5 px-4 py-2 transition-all duration-300 rounded-sm";
    const icons = {
      home: '<svg aria-hidden="true" class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m3 10 9-7 9 7"/><path d="M5 9v11h14V9"/><path d="M9 20v-7h6v7"/></svg>',
      rules: '<svg aria-hidden="true" class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4.5A2.5 2.5 0 0 1 7.5 2H20v17H7.5A2.5 2.5 0 0 0 5 21.5z"/><path d="M5 4.5v17"/><path d="M9 7h7M9 11h7"/></svg>',
      booking: '<svg aria-hidden="true" class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="16" rx="1"/><path d="M7 3v4M17 3v4M3 10h18"/><path d="m9 15 2 2 4-4"/></svg>',
      staff: '<svg aria-hidden="true" class="w-6 h-6" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg>',
      menu: '<svg aria-hidden="true" class="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 3v7a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2V3M6.5 3v18M14 3v8a3 3 0 0 0 3 3h1V3v18"/></svg>',
      event: '<svg aria-hidden="true" class="w-4 h-4 group-hover:rotate-12 transition-transform duration-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="16" rx="1"/><path d="M7 3v4M17 3v4M3 10h18"/><path d="m9 15 2 2 4-4"/></svg>',
    };

    const header = document.querySelector("[data-site-header]");
    if (header) {
      header.innerHTML = `
        <header class="fixed w-full z-50 bg-white/40 backdrop-blur-md top-0 border-b border-stone-200/30">
          <nav class="flex justify-between items-center w-full px-8 md:px-16 py-8 max-w-screen-2xl mx-auto">
            <a class="flex items-center gap-4 group cursor-pointer" href="index.html">
              <img alt="Logo" class="h-12 w-12 object-contain filter grayscale group-hover:grayscale-0 transition-all duration-300" src="assets/images/brand/brand-logo-primary.webp">
              <div class="flex flex-col">
                <span class="font-headline font-bold tracking-[0.4em] text-primary text-xl">${escapeHtml(config.siteName)}</span>
                <span class="font-label text-[9px] tracking-[0.5em] uppercase text-[#2D2926]">${escapeHtml(config.subtitle)}</span>
              </div>
            </a>
            <div class="hidden md:flex items-center gap-10 font-headline tracking-[0.3em] text-xs uppercase">
              ${links
                .map(
                  ([key, href, label]) =>
                    `<a class="${key === page ? activeClass : defaultClass}" href="${escapeHtml(safeHref(href))}">${escapeHtml(label)}</a>`
                )
                .join("")}
              <div class="menu-dropdown relative">
                <a aria-haspopup="true" class="${isMenuPage ? activeClass : defaultClass} inline-flex items-center gap-2" href="menus.html">
                  菜單
                  <svg aria-hidden="true" class="w-3.5 h-3.5 transition-transform duration-300 menu-dropdown-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m7 10 5 5 5-5"/></svg>
                </a>
                <div class="menu-dropdown-panel absolute right-0 top-full pt-4 w-52">
                  <div class="bg-white/95 backdrop-blur-xl border border-stone-200/80 shadow-[0_16px_40px_rgba(45,41,38,0.12)] p-2">
                    ${menus
                      .map(
                        (menu, index) => `
                          ${index > 0 ? '<div class="h-px bg-stone-100 mx-3"></div>' : ""}
                          <a class="block px-5 py-4 text-stone-600 hover:text-red-900 hover:bg-stone-50 transition-colors duration-300" href="${escapeHtml(safeHref(menu.href))}">
                            <span class="block tracking-[0.2em]">${escapeHtml(menu.title)}</span>
                            <span class="block mt-1 font-label text-[8px] tracking-[0.25em] text-stone-300">${escapeHtml(menu.englishTitle)}</span>
                          </a>`
                      )
                      .join("")}
                  </div>
                </div>
              </div>
            </div>
            <div class="w-10 h-10 hidden md:block"></div>
          </nav>
        </header>`;
    }

    const footer = document.querySelector("[data-site-footer]");
    if (footer) {
      const tagline =
        page === "index" ? config.taglines?.index : config.taglines?.default;
      footer.innerHTML = `
        <footer class="bg-white border-t border-stone-100 relative">
          <div class="grid grid-cols-1 md:grid-cols-3 items-start gap-20 px-8 md:px-16 py-32 max-w-screen-2xl mx-auto">
            <div class="flex flex-col gap-6">
              <a class="text-xl font-headline font-bold tracking-[0.4em] text-primary hover:text-red-900 transition-colors duration-300" href="index.html">${escapeHtml(config.siteName)}</a>
              <p class="font-body text-[13px] leading-loose tracking-[0.2em] text-stone-500">
                ${escapeHtml(config.address)}<br>${escapeHtml(tagline)}
              </p>
            </div>
            <div class="flex flex-col gap-8">
              <span class="font-label text-[10px] tracking-[0.5em] text-stone-300 uppercase">Contact</span>
              <div class="flex flex-col gap-4 font-headline text-sm tracking-[0.2em]">
                <a class="text-red-800 hover:tracking-[0.4em] transition-all duration-700" href="${escapeHtml(bookingUrl)}" target="_blank" rel="noopener noreferrer">線上預約</a>
                <a class="text-stone-500 hover:text-primary transition-all duration-500" href="${escapeHtml(threadsUrl)}" target="_blank" rel="noopener noreferrer">Threads 追蹤</a>
                <a class="text-stone-500 hover:text-primary transition-all duration-500" href="${escapeHtml(discordUrl)}" target="_blank" rel="noopener noreferrer">Discord 社群</a>
              </div>
            </div>
            <div class="md:text-right flex flex-col md:items-end gap-8">
              <span class="font-label text-[10px] tracking-[0.5em] text-stone-300 uppercase">Opening Hours</span>
              <div class="font-headline text-[13px] tracking-[0.2em] text-stone-700 leading-relaxed">
                ${escapeHtml(config.openingDays)}<br>${escapeHtml(config.openingHours)}<br>${escapeHtml(config.status)}
              </div>
              <div class="flex md:justify-end gap-3 mt-4">
                <span class="w-1.5 h-1.5 rounded-full bg-red-800/10"></span>
                <span class="w-1.5 h-1.5 rounded-full bg-red-800/30"></span>
                <span class="w-1.5 h-1.5 rounded-full bg-red-800/50"></span>
              </div>
            </div>
          </div>
          <div class="max-w-screen-2xl mx-auto px-8 md:px-16 py-10 border-t border-stone-50 text-center">
            <p class="font-label text-[9px] tracking-[0.4em] text-stone-300 uppercase">© 2026 ${escapeHtml(config.subtitle)}. All Rights Reserved.</p>
          </div>
        </footer>`;
    }

    const mobileNav = document.querySelector("[data-mobile-nav]");
    if (mobileNav) {
      const mobileLinks = [
        ["index", "index.html", "首頁", icons.home],
        ["menus", "menus.html", "菜單", icons.menu],
        ["booking", bookingUrl, "預約", icons.booking],
        ["staff", "staff.html", "湯娘", icons.staff],
        ["rules", "rules.html", "規範", icons.rules],
      ];
      mobileNav.innerHTML = `
        <nav class="mobile-bottom-nav md:hidden fixed inset-x-0 bottom-0 bg-white/95 backdrop-blur-xl border-t border-stone-100 grid items-stretch z-50">
          ${mobileLinks
            .map(([key, href, label, icon]) => {
              const external =
                key === "booking"
                  ? ' target="_blank" rel="noopener noreferrer"'
                  : "";
              const isActive = key === "menus" ? isMenuPage : key === page;
              const stateClass = isActive
                ? "text-red-800 bg-red-50/80"
                : "text-stone-400 hover:text-stone-700";
              return `<a aria-label="${escapeHtml(label)}" class="${stateClass} flex flex-col items-center justify-center gap-1.5 px-1 py-2.5 transition-all duration-300" href="${escapeHtml(safeHref(href))}"${external}>${icon}<span class="font-label text-[10px] leading-none tracking-[0.12em]">${escapeHtml(label)}</span></a>`;
            })
            .join("")}
        </nav>`;
    }

    const booking = document.querySelector("[data-booking-sidebar]");
    if (booking) {
      booking.innerHTML = `
        <a class="hidden md:flex fixed right-0 top-1/2 -translate-y-1/2 z-[60] bg-primary text-white py-10 px-4 vertical-text font-headline tracking-[0.4em] text-xs hover:bg-stone-800 transition-all duration-500 shadow-[-4px_0_20px_rgba(0,0,0,0.15)] border-l border-stone-700/50 items-center gap-5 group" href="${escapeHtml(bookingUrl)}" target="_blank" rel="noopener noreferrer">
          ${icons.event}
          <span class="font-medium">立即預約</span>
          <span class="w-[1px] h-8 bg-white/20 mt-2"></span>
        </a>`;
    }
  };

  const fallback = window.SITE_CONFIG;
  if (!fallback) return;

  renderSite(fallback, fallback.menus);
  if (!window.DATA_PROVIDER) {
    window.ACTIVE_SITE_CONFIG = fallback;
    return;
  }

  Promise.all([
    window.DATA_PROVIDER.getSiteConfig(),
    window.DATA_PROVIDER.getMenus(),
  ]).then(([config, menus]) => {
    const activeConfig = {
      ...config,
      menus,
    };
    window.ACTIVE_SITE_CONFIG = activeConfig;
    renderSite(activeConfig, menus);
  });
})();
