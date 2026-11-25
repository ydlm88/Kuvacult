// Patch notes demos: roulette spin + watchlist screen.
// Mount with <div data-roulette-demo> and <div data-watchlist-demo>. Plays only while on screen.
(() => {
  const BASE = document.currentScript ? document.currentScript.src.replace(/patch-demo\.js.*$/, "") : "assets/";
  const P = BASE + "patch/", POSTERS = BASE + "posters/";
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // [title, director, year, genre, a24 poster #]
  const FILMS = [
    ["Under the Skin", "Jonathan Glazer", 2014, "Sci-fi", 1],
    ["The Witch", "Robert Eggers", 2016, "Horror", 2],
    ["Green Room", "Jeremy Saulnier", 2016, "Thriller", 3],
    ["It Comes at Night", "Trey Edward Shults", 2017, "Horror", 4],
    ["The Killing of a Sacred Deer", "Yorgos Lanthimos", 2017, "Thriller", 5],
    ["Hereditary", "Ari Aster", 2018, "Horror", 6],
    ["Opus", "Mark Anthony Green", 2025, "Horror", 22],
    ["Talk to Me", "Danny & Michael Philippou", 2023, "Horror", 17],
    ["Midsommar", "Ari Aster", 2019, "Horror", 9],
    ["The Lighthouse", "Robert Eggers", 2019, "Drama", 10],
    ["Saint Maud", "Rose Glass", 2021, "Horror", 11],
    ["Heretic", "Scott Beck & Bryan Woods", 2024, "Horror", 19],
  ].map(([t, d, y, g, n]) => ({ t, d, y, g: g.toUpperCase(), src: `${POSTERS}a24-${String(n).padStart(2, "0")}.webp` }));
  const TABS = [
    { label: "Want to Watch", ids: [5, 6, 7, 9, 10, 11, 3, 2] },
    { label: "Watching", ids: [8] },
    { label: "Watched", ids: [0, 1, 4] },
  ];
  const WANT = TABS[0].ids;
  const AV = ["avatar-yoshua.png", "avatar-pickle.png", "avatar-silver.jpg"].map((f) => P + f);
  const RED = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");

  // Chalk boil: three frames swapped every 140ms (420ms cycle, same as the app).
  // Any <img data-boil="ball|wheel_icon|pocket_red|..."> and <path data-chalk> follows it.
  const frame = (k, f) => `${P}${k}_f${f + 1}.png`;
  // Tab underline, matching ChalkLine(strokeWidth: 3, amplitude: 0.55, step: 3).
  const chalk = (seed, amp, dy) => {
    let r = seed; const rnd = () => ((r = (r * 9301 + 49297) % 233280) / 233280);
    let d = "";
    for (let x = 0; x <= 200; x += 3) d += (x ? " L" : "M") + x + " " + (5 + dy + Math.sin((x / 200) * Math.PI) * 0.5 + (rnd() - 0.5) * 2 * amp).toFixed(2);
    return d;
  };
  const CHALK = [[11, 23, 37].map((s) => chalk(s, 0.55, 0)), [5, 17, 29].map((s) => chalk(s, 0.7, -0.6))];
  let f = 0;
  const boil = () => {
    document.querySelectorAll("img[data-boil]").forEach((el) => { el.src = frame(el.dataset.boil, f); });
    document.querySelectorAll("path[data-chalk]").forEach((el) => el.setAttribute("d", CHALK[+el.dataset.chalk][f]));
  };
  if (!reduce) {
    ["ball", "wheel_icon", "pocket_red", "pocket_black", "pocket_green"].forEach((k) => [0, 1, 2].forEach((i) => { new Image().src = frame(k, i); }));
    setInterval(() => { f = (f + 1) % 3; boil(); }, 140);
  }

  // Runs `cycle(at)` while the element is on screen; `at(ms, fn)` timers are cleared when it leaves.
  const whileVisible = (root, cycle, still) => {
    if (reduce) { still(); return; }
    let timers = [];
    const at = (ms, fn) => timers.push(setTimeout(fn, ms));
    new IntersectionObserver(([e]) => {
      timers.forEach(clearTimeout); timers = [];
      if (e.isIntersecting) cycle(at); else still();
    }, { threshold: 0.25 }).observe(root);
  };

  // Phones: lay the demo out at a fixed design width and scale it down, so it never reflows or overflows.
  const DESIGN_W = 620;
  const fitStage = (root, fixedH) => {
    const stage = root.querySelector(".pn-stage");
    const fit = () => {
      const s = Math.min(1, root.clientWidth / DESIGN_W);
      if (s < 1) {
        stage.style.width = DESIGN_W + "px";
        if (fixedH) stage.style.height = fixedH + "px";
        stage.style.transform = `scale(${s})`;
        root.style.height = Math.ceil(stage.offsetHeight * s) + "px";
      } else {
        stage.style.width = stage.style.height = stage.style.transform = root.style.height = "";
      }
    };
    // Watch the parent's width only: fit() writes root's height, so observing root would loop.
    let lastW = -1, raf = 0;
    const schedule = () => {
      const w = root.clientWidth;
      if (w === lastW) return;
      lastW = w;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(fit);
    };
    new ResizeObserver(schedule).observe(root.parentElement);
    addEventListener("resize", schedule, { passive: true });
    fit(); lastW = root.clientWidth;
  };

  /* ───────────── Roulette ───────────── */
  const roulette = (root) => {
    root.classList.add("pn-frame", "pd-rl");
    root.innerHTML = `<div class="pn-stage">
      <div class="pd-rl-bar"><span class="pd-rl-cap">1 in ${WANT.length} from all of Want to Watch</span><span class="pd-wl-spin"><img data-boil="wheel_icon" src="${frame("wheel_icon", 0)}" alt="" width="28" height="28"><span>Spin the wheel</span></span></div>
      <div class="pd-rl-grid">${WANT.map((id, i) => `
        <div class="pd-pc"><div class="pd-pc-p"><img src="${FILMS[id].src}" alt="" loading="lazy" decoding="async"><span class="pd-pc-n">${i + 1}</span>${i === 0 ? '<span class="pd-pc-next">NEXT</span>' : ""}<img class="pd-pc-ball" data-boil="ball" src="${frame("ball", 0)}" alt="" width="22" height="22"></div><span class="pd-pc-t">${esc(FILMS[id].t)}</span></div>`).join("")}
      </div>
      <div class="pd-tk-scrim"><div class="pd-tk">
        <div class="pd-tk-top"><span class="pd-tk-eyebrow">Tonight’s pick</span><div class="pd-tk-poster"><img class="pd-tk-img" alt=""><img class="pd-tk-av" alt=""></div></div>
        <div class="pd-tk-tear"></div>
        <div class="pd-tk-bot">
          <div class="pd-tk-row"><div class="pd-tk-pocket"><img data-boil="pocket_black" src="${frame("pocket_black", 0)}" alt="" width="48" height="48"><span></span></div><div class="pd-tk-info"><span class="pd-tk-title"></span><span class="pd-tk-meta"></span></div></div>
          <span class="pd-tk-odds">1 in ${WANT.length} · Want to Watch</span>
          <div class="pd-tk-btns">
            <span class="pd-tk-btn pd-tk-next"><img data-boil="pocket_black" src="${frame("pocket_black", 0)}" alt="" width="24" height="24">Make it next</span>
            <div class="pd-tk-pair"><span class="pd-tk-btn pd-tk-again"><img data-boil="wheel_icon" src="${frame("wheel_icon", 0)}" alt="" width="22" height="22">Spin again</span><span class="pd-tk-btn pd-tk-not">Not tonight</span></div>
          </div>
        </div>
      </div></div></div>`;
    fitStage(root, 0);
    const cells = [...root.querySelectorAll(".pd-pc")];
    const cap = root.querySelector(".pd-rl-cap"), btn = root.querySelector(".pd-rl-bar .pd-wl-spin"), btnLabel = btn.lastElementChild;
    const pocketImg = root.querySelector(".pd-tk-pocket img"), pocketNum = root.querySelector(".pd-tk-pocket span");
    const hop = (i) => cells.forEach((c, k) => c.classList.toggle("hot", k === i));
    const setSpinning = (on) => { btn.classList.toggle("on", on); btnLabel.textContent = on ? "Spinning" : "Spin the wheel"; cap.textContent = on ? "Spinning…" : `1 in ${WANT.length} from all of Want to Watch`; };
    const fillTicket = (w, pocket) => {
      const m = FILMS[WANT[w]];
      root.querySelector(".pd-tk-img").src = m.src;
      root.querySelector(".pd-tk-av").src = AV[w % 3];
      root.querySelector(".pd-tk-title").textContent = m.t;
      root.querySelector(".pd-tk-meta").textContent = `${m.d} · ${m.y}`;
      pocketImg.dataset.boil = "pocket_" + (pocket === 0 ? "green" : RED.has(pocket) ? "red" : "black");
      pocketImg.src = frame(pocketImg.dataset.boil, f);
      pocketNum.textContent = pocket;
    };
    const still = () => { hop(-1); setSpinning(false); fillTicket(3, 31); root.classList.add("ticket"); };
    const cycle = (at) => {
      const N = WANT.length;
      const w = 1 + Math.floor(Math.random() * (N - 1)); // Next Up is excluded from the pool
      const pocket = Math.floor(Math.random() * 37);
      root.classList.remove("ticket"); hop(-1); setSpinning(false);
      let d = 1400;
      at(d, () => setSpinning(true));
      // Phase 1: fast walk at 35ms per hop, ~2s, at least one lap
      const walk = Math.max(N, Math.min(57, Math.round(2000 / 35)));
      for (let i = 0; i < walk; i++) { d += 35; const k = i % N; at(d, () => hop(k)); }
      // Phase 2: 16 decelerating hops over ~3.2s (growth 1.15), ending on the winner
      const hops = 16, g = 1.15, base = 3200 / ((Math.pow(g, hops) - 1) / (g - 1));
      for (let k = 0; k < hops; k++) {
        d += base * Math.pow(g, k);
        const idx = (((w - (hops - 1 - k)) % N) + N) % N;
        at(d, () => hop(idx));
      }
      // 420ms after the last hop: clear and open the ticket
      at(d + 420, () => { hop(-1); setSpinning(false); fillTicket(w, pocket); root.classList.add("ticket"); });
      at(d + 5200, () => root.classList.remove("ticket"));
      at(d + 5800, () => cycle(at));
    };
    whileVisible(root, cycle, still);
  };

  /* ───────────── Watchlist screen ───────────── */
  const watchlist = (root) => {
    root.classList.add("pn-frame", "pd-wl");
    root.innerHTML = `<div class="pn-stage">
      <div class="pd-wl-top">
        <div class="pd-wl-bar1"><span class="pd-wl-back pd-ms">arrow_back_ios_new</span><div class="pd-wl-avs">${AV.map((a) => `<img src="${a}" alt="">`).join("")}</div><span class="pd-wl-invite"><span class="pd-ms">person_add</span>Invite</span></div>
        <div class="pd-wl-eyebrow"><span>THE QUEUE  ·  12 FILMS  ·  B47KGL</span><b class="pd-wl-ordered">ORDERED</b></div>
        <div class="pd-wl-title">A24 Horror Movies in Order</div>
      </div>
      <div class="pd-wl-tools">
        <div class="pd-wl-toggle"><span class="pd-ms" data-v="grid">grid_view</span><span class="pd-ms" data-v="list">view_agenda</span></div>
        <span class="pd-wl-div"></span>
        <span class="pd-wl-chip"><span class="pd-ms">tune</span>Filter</span>
        <span class="pd-wl-chip"><span class="pd-ms">sort</span>List Order</span>
        <span class="pd-wl-chip"><span class="pd-ms">format_list_numbered</span>Reorder</span>
        <span class="pd-wl-grow"></span>
        <span class="pd-wl-spin"><img data-boil="wheel_icon" src="${frame("wheel_icon", 0)}" alt="" width="26" height="26">Spin the wheel</span>
      </div>
      <div class="pd-wl-tabs">${TABS.map((t, i) => `<div class="pd-wl-tab" data-i="${i}"><b>${t.label}</b><small>${t.ids.length}</small><svg viewBox="0 0 200 10" preserveAspectRatio="none" aria-hidden="true"><path data-chalk="0" d="${CHALK[0][0]}" fill="none" stroke="#E9B53F" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/><path data-chalk="1" d="${CHALK[1][0]}" fill="none" stroke="#F2C95C" stroke-opacity="0.55" stroke-width="1.4" stroke-linecap="round" vector-effect="non-scaling-stroke"/></svg></div>`).join("")}</div>
      <div class="pd-wl-search"><span class="pd-ms">search</span>Search movies…</div>
      <div class="pd-wl-body"></div>
      <div class="pd-wl-fade"></div></div>`;
    fitStage(root, 760);
    const body = root.querySelector(".pd-wl-body");
    const tabs = [...root.querySelectorAll(".pd-wl-tab")], segs = [...root.querySelectorAll(".pd-wl-toggle span")];
    const nextUp = () => `
      <div class="pd-nu pd-wl-anim"><img class="pd-nu-bg" src="${FILMS[5].src}" alt=""><div class="pd-nu-shade"></div><span class="pd-pc-n">1</span><img class="pd-nu-av" src="${AV[0]}" alt="">
        <div class="pd-nu-c"><img class="pd-nu-thumb" src="${FILMS[5].src}" alt=""><div class="pd-nu-t"><span class="pd-nu-pill">NEXT UP</span><span class="pd-nu-meta">ARI ASTER · 2018</span><span class="pd-nu-title">Hereditary</span><div class="pd-nu-g"><span class="pd-gp">HORROR</span><span class="pd-gp">DRAMA</span></div></div></div>
      </div>`;
    const row = (id, n, i) => { const m = FILMS[id]; return `
      <div class="pd-wr pd-wl-anim" style="--d:${(i + 1) * 90}ms"><div class="pd-wr-th"><img src="${m.src}" alt=""><span class="pd-pc-n">${n}</span></div><div class="pd-wr-c"><span class="pd-wr-y">${m.y}</span><span class="pd-wr-t">${esc(m.t)}</span><span class="pd-wr-d">${esc(m.d)}</span></div><span class="pd-gp">${m.g}</span><img class="pd-wr-av" src="${AV[(id + i) % 3]}" alt=""></div>`; };
    const cell = (id, n, i, next) => `
      <div class="pd-pc pd-wl-anim" style="--d:${i * 60}ms"><div class="pd-pc-p"><img src="${FILMS[id].src}" alt=""><span class="pd-pc-n">${n}</span>${next ? '<span class="pd-pc-next">NEXT</span>' : ""}</div><span class="pd-pc-t">${esc(FILMS[id].t)}</span></div>`;
    const render = ({ tab, view, loading }) => {
      tabs.forEach((t, i) => t.classList.toggle("on", i === tab));
      segs.forEach((s) => s.classList.toggle("on", s.dataset.v === view));
      body.classList.remove("in");
      const ids = TABS[tab].ids;
      if (loading) { body.innerHTML = `<div class="pd-wl-loader"><img src="${P}kuvacult_loader.webp" alt="" width="140" height="140"></div>`; return; }
      if (view === "grid") body.innerHTML = `<div class="pd-wg">${ids.map((id, i) => cell(id, i + 1, i, tab === 0 && i === 0)).join("")}</div>`;
      else {
        const list = tab === 0 ? ids.slice(1, 4) : ids.slice(0, 4), off = tab === 0 ? 2 : 1;
        body.innerHTML = (tab === 0 ? nextUp() : "") + `<div class="pd-wr-list">${list.map((id, i) => row(id, i + off, i)).join("")}</div>`;
      }
      requestAnimationFrame(() => requestAnimationFrame(() => body.classList.add("in")));
    };
    const still = () => render({ tab: 0, view: "list", loading: false });
    // Section boot loader (~2s on first visit to a non-empty tab) → content staggers in → grid → Watched → Watching
    const cycle = (at) => {
      render({ tab: 0, view: "list", loading: true });
      at(2000, () => render({ tab: 0, view: "list", loading: false }));
      at(6000, () => render({ tab: 0, view: "grid", loading: false }));
      at(9600, () => render({ tab: 2, view: "grid", loading: true }));
      at(11600, () => render({ tab: 2, view: "grid", loading: false }));
      at(14600, () => render({ tab: 1, view: "list", loading: false }));
      at(18000, () => cycle(at));
    };
    whileVisible(root, cycle, still);
  };

  const init = () => {
    document.querySelectorAll("[data-roulette-demo]").forEach(roulette);
    document.querySelectorAll("[data-watchlist-demo]").forEach(watchlist);
  };
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", init) : init();
})();
