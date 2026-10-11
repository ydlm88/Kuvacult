// ---- configure -------------------------------------------------------------
const REPO = "ydlm88/Kuvacult";
const SOCIAL = { tiktok: "", instagram: "" }; // paste your profile URLs
const EMAIL = "kuvacult@gmail.com";
// ----------------------------------------------------------------------------
(() => {
  const base = `https://github.com/${REPO}`;
  const links = { windows: `${base}/releases/latest`, releases: `${base}/releases`, repo: base, issues: `mailto:${EMAIL}?subject=Kuvacult%20bug%20report` };
  const apply = () => {
    document.querySelectorAll("[data-link]").forEach((a) => { if (links[a.dataset.link]) a.href = links[a.dataset.link]; });
    document.querySelectorAll("[data-social]").forEach((a) => { const u = SOCIAL[a.dataset.social]; if (u) { a.href = u; a.target = "_blank"; a.rel = "noopener"; } });
  };
  apply();
  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : Promise.reject()))
    .then((rel) => {
      const win = (rel.assets || []).find((a) => /\.(exe|msix|msi|zip)$/i.test(a.name));
      if (win) links.windows = win.browser_download_url;
      apply();
      const el = document.getElementById("release");
      if (!el) return;
      const parts = [`Latest ${rel.tag_name}`];
      if (rel.published_at) parts.push(new Date(rel.published_at).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }));
      if (win) parts.push(`${Math.round(win.size / 1048576)} MB`);
      parts.push("free");
      el.textContent = parts.join(" · ");
    })
    .catch(() => {});

  const nav = document.getElementById("nav"), burger = document.getElementById("burger");
  const setOpen = (o) => { nav.classList.toggle("open", o); document.body.classList.toggle("menu-open", o); burger.setAttribute("aria-expanded", o); burger.setAttribute("aria-label", o ? "Close menu" : "Open menu"); };
  burger.addEventListener("click", () => setOpen(!nav.classList.contains("open")));
  document.querySelectorAll("#menu a").forEach((a) => a.addEventListener("click", () => setOpen(false)));
  addEventListener("keydown", (e) => { if (e.key === "Escape") setOpen(false); });
  addEventListener("resize", () => { if (innerWidth > 860) setOpen(false); });
  document.querySelectorAll(".dd").forEach((dd) => {
    const b = dd.querySelector(".dd-btn");
    b.addEventListener("click", (e) => { e.stopPropagation(); const o = !dd.classList.contains("open"); dd.classList.toggle("open", o); b.setAttribute("aria-expanded", o); });
    document.addEventListener("click", (e) => { if (!dd.contains(e.target)) { dd.classList.remove("open"); b.setAttribute("aria-expanded", "false"); } });
  });
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 40);
  addEventListener("scroll", onScroll, { passive: true }); onScroll();

  document.querySelectorAll("[data-copy]").forEach((b) => b.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy); } catch { const t = document.createElement("textarea"); t.value = b.dataset.copy; document.body.appendChild(t); t.select(); document.execCommand("copy"); t.remove(); }
    const old = b.textContent; b.textContent = "Copied"; setTimeout(() => (b.textContent = old), 1600);
  }));

  const lb = document.getElementById("lb");
  if (lb) {
    const img = document.getElementById("lb-img");
    document.addEventListener("click", (e) => {
      const z = e.target.closest("[data-zoom]"); if (!z) return;
      const src = z.querySelector("img"); img.src = src.currentSrc || src.src; img.alt = src.alt;
      lb.showModal(); lb.querySelector(".lb-scroll").scrollLeft = 0;
    });
    lb.querySelector(".lb-x").addEventListener("click", () => lb.close());
    lb.addEventListener("click", (e) => { if (e.target === lb || e.target.classList.contains("lb-scroll")) lb.close(); });
  }
  const openHash = () => { const d = location.hash && document.querySelector("details" + CSS.escape(location.hash)); if (d) d.open = true; };
  openHash(); addEventListener("hashchange", openHash); // details[id] deep links
})();
