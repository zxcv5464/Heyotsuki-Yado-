(async () => {
  const container = document.querySelector("#menu-sections");
  const menuKey = document.body.dataset.menuKey;
  const data = await window.DATA_PROVIDER?.getMenu(menuKey);
  if (!container || !data) return;

  const title = document.querySelector("#menu-title");
  const subtitle = document.querySelector("#menu-subtitle");
  const footer = document.querySelector("#menu-footer");

  if (title) title.textContent = data.title;
  if (subtitle) subtitle.textContent = data.subtitle;

  const plainText = (value) => {
    const source = String(value ?? "");
    if (!source.includes("<")) return source;
    const documentFragment = new DOMParser().parseFromString(
      source.replace(/<br\s*\/?>/gi, "\n"),
      "text/html"
    );
    return documentFragment.body.textContent || "";
  };

  const escapeHtml = (value) =>
    plainText(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const formatText = (value) =>
    escapeHtml(value).replace(/\r?\n/g, "<br>");

  const sectionHeading = (section, nested = false) => `
    <div class="flex flex-col items-start gap-2 md:flex-row md:items-center md:gap-4 ${nested ? "mb-10 md:mb-12" : "mb-10 md:mb-16"} border-b border-stone-200 pb-4">
      <h2 class="w-full min-w-0 break-words font-headline text-2xl sm:text-3xl font-bold leading-relaxed tracking-[0.16em] sm:tracking-[0.2em] text-primary">
        ${formatText(section.title)}
        ${section.notice ? `<span class="block mt-2 text-base leading-loose font-light tracking-normal md:inline md:mt-0 md:text-lg">${formatText(section.notice)}</span>` : ""}
      </h2>
      ${section.label ? `<span class="font-label text-[10px] tracking-[0.3em] uppercase text-stone-400">${formatText(section.label)}</span>` : ""}
    </div>`;

  const detailedItem = (item) => `
    <div class="group">
      <div class="flex flex-col items-start gap-2 md:grid md:grid-cols-[minmax(0,1fr)_auto] md:items-baseline md:gap-x-6 md:gap-y-3">
        <h3 class="font-bold text-xl sm:text-2xl leading-relaxed tracking-[0.08em] text-primary md:col-start-1 md:row-start-1">${formatText(item.name)}</h3>
        <p class="text-stone-400 text-[13px] sm:text-sm leading-[1.9] tracking-[0.1em] sm:tracking-widest yubaku-spacing md:col-span-2 md:row-start-2">${formatText(item.description)}</p>
        <span class="font-headline text-xl sm:text-2xl text-primary whitespace-nowrap mt-1 md:mt-0 md:col-start-2 md:row-start-1">${formatText(item.price)}</span>
      </div>
    </div>`;

  const compactItem = (item) => `
    <div class="flex flex-col items-start gap-2.5 md:flex-row md:items-center md:gap-0 group">
      <h3 class="text-lg sm:text-xl leading-relaxed tracking-[0.16em] text-primary${item.featured ? " font-bold" : ""}">${formatText(item.name)}</h3>
      <div class="hidden md:block flex-grow mx-4 border-b border-dotted border-stone-300"></div>
      <span class="font-headline text-xl text-primary whitespace-nowrap${item.featured ? " font-bold" : ""}">${formatText(item.price)}</span>
    </div>`;

  const items = (section) => {
    const renderer = section.layout === "compact" ? compactItem : detailedItem;
    const classes =
      section.layout === "compact"
        ? "grid grid-cols-1 md:grid-cols-2 gap-x-24 gap-y-12"
        : "space-y-12";
    return `<div class="${classes}">${section.items.map(renderer).join("")}</div>`;
  };

  const nestedSections = (section) =>
    (section.nestedSections || [])
      .map(
        (nested) => `
          <div class="pt-10 md:pt-12">
            ${sectionHeading(nested, true)}
            ${items(nested)}
          </div>`
      )
      .join("");

  container.innerHTML = data.sections
    .map(
      (section, index) => `
        <section${index < data.sections.length - 1 ? ' class="mb-20 md:mb-32"' : ""}>
          ${sectionHeading(section)}
          ${items(section)}
          ${nestedSections(section)}
        </section>`
    )
    .join("");

  if (footer) {
    footer.innerHTML = data.footer
      .map(
        (line, index) =>
          `<p class="font-headline text-stone-400 ${
            index === 0 ? "tracking-[0.35em]" : "tracking-wider mt-6"
          } text-sm italic leading-loose">${formatText(line)}</p>`
      )
      .join("");
  }
})();
