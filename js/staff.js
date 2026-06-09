(async () => {
  const grid = document.querySelector("#staff-grid");
  if (!grid || !window.DATA_PROVIDER) return;

  const escapeHtml = (value) =>
    String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const formatQuote = (value) =>
    escapeHtml(String(value ?? "").replace(/<br\s*\/?>/gi, "\n")).replace(
      /\r?\n/g,
      "<br>"
    );

  const safeImageUrl = (value) => {
    try {
      const url = new URL(value, window.location.href);
      return ["http:", "https:"].includes(url.protocol) ? url.href : "";
    } catch {
      return "";
    }
  };

  const staff = await window.DATA_PROVIDER.getStaff();
  if (!staff.length) return;

  grid.innerHTML = staff.map(
    (member) => {
      const image = safeImageUrl(member.image);
      const name = escapeHtml(member.name);
      return `
      <div class="book-card perspective-1000 h-[520px] group cursor-pointer opacity-0 animate-reveal stagger-${member.stagger}">
        <div class="book-inner relative w-full h-full transition-transform duration-1000 transform-style-3d shadow-sm group-hover:shadow-xl">
          <div class="absolute inset-0 w-full h-full backface-hidden bg-white overflow-hidden flex flex-col border border-stone-100">
            <div class="h-[75%] w-full overflow-hidden">
              ${image ? `<img class="w-full h-full object-cover object-center" src="${escapeHtml(image)}" alt="${name}" loading="lazy" decoding="async">` : ""}
            </div>
            <div class="flex-1 p-8 flex flex-col justify-center border-l-4 border-red-900">
              <h3 class="font-headline text-xl font-bold text-primary tracking-widest">${name}</h3>
              <p class="text-[10px] font-label uppercase tracking-[0.3em] text-stone-400 mt-2">${escapeHtml(member.subtitle)}</p>
            </div>
          </div>
          <div class="absolute inset-0 w-full h-full backface-hidden rotate-y-180 bg-stone-900 p-10 border-r-8 border-red-900 flex flex-col justify-between text-stone-200">
            <div>
              <span class="text-[9px] uppercase tracking-[0.4em] text-red-800 font-bold block mb-4">湯語</span>
              <p class="font-headline text-lg leading-relaxed tracking-wider italic">${formatQuote(member.quote)}</p>
            </div>
            <div class="text-[10px] tracking-[0.4em] text-stone-500 border-t border-stone-800 pt-6 uppercase">${escapeHtml(member.role)}</div>
          </div>
        </div>
      </div>`;
    }
  ).join("");
})();
