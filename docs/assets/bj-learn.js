// Interactive blackjack lessons: [data-bj-values], [data-bj-builder], [data-bj-practice]. Uses picker styles in style.css.
(() => {
  const BASE = document.currentScript ? document.currentScript.src.replace(/bj-learn\.js.*$/, "") : "../assets/";
  const CARDS = BASE + "cards/";
  const SUITS = ["spade", "club", "heart", "diamond"];
  const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
  const RED = { heart: 1, diamond: 1 };
  const NAMES = { A: "Ace", J: "Jack", Q: "Queen", K: "King" };
  const cardHtml = (c, hidden, w) => {
    const st = w ? ` style="width:${w}px"` : "";
    if (hidden) return `<div class="pcard back"${st}><img src="${CARDS}back-4b-logo.webp" alt="Face-down card"></div>`;
    return `<div class="pcard"${st}><img class="pc-bg" src="${CARDS}${RED[c.s] ? "card-tan" : "card-dark"}.webp" alt=""><img class="pc-r" src="${CARDS}${RED[c.s] ? "r" : "w"}-${c.r}.webp" alt="${NAMES[c.r] || c.r}"><img class="pc-sm" src="${CARDS}${c.s}.webp" alt=""><img class="pc-s" src="${CARDS}${c.s}.webp" alt="of ${c.s}s"></div>`;
  };
  const cv = (r) => (r === "A" ? 11 : /[JQK]/.test(r) ? 10 : +r);
  const total = (cs) => { let t = 0, a = 0; cs.forEach((c) => { t += cv(c.r); if (c.r === "A") a++; }); while (t > 21 && a) { t -= 10; a--; } return { t, soft: a > 0 && t <= 21 }; };
  const rnd = (a) => a[Math.floor(Math.random() * a.length)];
  const deck = () => { const d = []; for (let k = 0; k < 4; k++) SUITS.forEach((s) => RANKS.forEach((r) => d.push({ r, s }))); for (let i = d.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [d[i], d[j]] = [d[j], d[i]]; } return d; };
  const chip = "font:inherit;font-size:12px;letter-spacing:0.08em;min-width:44px;height:44px;padding:0 12px;border-radius:12px;border:1px solid rgba(243,228,207,0.18);background:#121010;color:var(--ink);cursor:pointer";

  // 1. Card values
  const values = (root) => {
    const show = ["2", "5", "9", "10", "J", "Q", "K", "A"];
    root.innerHTML = `<div class="bj" style="margin-top:0">
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(72px,1fr));gap:18px 12px;justify-items:center">
      ${show.map((r, i) => `<button type="button" data-r="${r}" style="all:unset;cursor:pointer;display:flex;flex-direction:column;align-items:center;gap:10px" aria-label="${NAMES[r] || r}">${cardHtml({ r, s: SUITS[i % 4] }, false, 64)}<span data-v style="font-family:var(--serif);font-size:24px;color:var(--gold);line-height:1">${r === "A" ? "1 / 11" : cv(r)}</span></button>`).join("")}
      </div>
      <p class="bj-status" data-say style="text-align:left;min-height:3.2em;line-height:1.7">Tap a card to see what it’s worth.</p>
    </div>`;
    const say = root.querySelector("[data-say]");
    const msg = { A: "An Ace counts as 11, unless that would push you over 21. Then it quietly drops to 1. That flexibility makes it the best card in the deck.", J: "Jacks, Queens and Kings are all worth 10. So are the 10s, which is why so many hands land on 20.", Q: "Queens are worth 10, the same as every other picture card.", K: "Kings are worth 10. Suits never matter in blackjack, only the value.", "10": "A 10 is worth 10. With the three picture cards, that’s 16 ten-value cards in every deck." };
    root.querySelectorAll("[data-r]").forEach((b) => b.addEventListener("click", () => { const r = b.dataset.r; say.textContent = msg[r] || `Number cards are worth exactly what they say. A ${r} is worth ${r}.`; }));
  };

  // 2. Hand builder
  const builder = (root) => {
    root.innerHTML = `<div class="bj" style="margin-top:0">
      <div style="display:flex;flex-wrap:wrap;gap:8px">${RANKS.map((r) => `<button type="button" data-add="${r}" style="${chip}">${r}</button>`).join("")}</div>
      <div class="seat" style="min-height:150px"><div class="seat-top"><span class="seat-name">Your hand</span><span class="seat-score" data-t>0</span></div><div class="bj-hand" data-h></div><div class="seat-film" data-note style="white-space:normal">Add cards to build a hand.</div></div>
      <div class="bj-controls" style="justify-content:flex-start"><button type="button" class="bj-clear" data-clear style="white-space:nowrap;flex-shrink:0">Clear hand</button></div>
    </div>`;
    let hand = [];
    const h = root.querySelector("[data-h]"), t = root.querySelector("[data-t]"), note = root.querySelector("[data-note]"), seat = root.querySelector(".seat");
    const render = () => {
      const { t: v, soft } = total(hand);
      t.textContent = v > 21 ? "BUST" : v;
      seat.classList.toggle("bust", v > 21);
      seat.classList.toggle("win", v === 21);
      note.textContent = !hand.length ? "Add cards to build a hand." : v > 21 ? `That’s ${v}. Over 21 is a bust, and the hand is lost.` : v === 21 ? (hand.length === 2 ? "Blackjack! An Ace and a ten-value card on your first two cards is the best hand there is." : "21 exactly. You can’t do better than that, so you’d stand.") : soft ? `Soft ${v}. One Ace is counting as 11, so another card can’t bust you.` : `Hard ${v}.${hand.some((c) => c.r === "A") ? " Your Ace is counting as 1 to keep you under 21." : ""}`;
    };
    root.querySelectorAll("[data-add]").forEach((b) => b.addEventListener("click", () => { if (hand.length >= 8 || total(hand).t > 21) return; const c = { r: b.dataset.add, s: rnd(SUITS) }; hand.push(c); h.insertAdjacentHTML("beforeend", cardHtml(c)); render(); }));
    root.querySelector("[data-clear]").addEventListener("click", () => { hand = []; h.innerHTML = ""; render(); });
  };

  // 3. Practice vs the house
  const advice = (p, up) => {
    const { t, soft } = total(p), d = cv(up.r);
    if (soft) { if (t >= 19) return ["Stand", "Soft 19 or more is strong. Stand."]; if (t === 18) return d <= 8 ? ["Stand", "Soft 18 against a weak or middling house card: stand."] : ["Hit", "Soft 18 against a 9, 10 or Ace: take a card. Your Ace means you can’t bust."]; return ["Hit", "Soft hands under 18 can always take a card safely. Hit."]; }
    if (t <= 11) return ["Hit", `${t} can’t bust with one card. Always hit.`];
    if (t >= 17) return ["Stand", `${t} is a made hand. Stand and let the house take the risk.`];
    if (t === 12) return d >= 4 && d <= 6 ? ["Stand", "12 against a house 4, 5 or 6: stand and hope the house busts."] : ["Hit", "12 against this house card: hit. Only a ten-value card busts you."];
    return d <= 6 ? ["Stand", `${t} against a house ${d === 11 ? "Ace" : d}: stand. The house has to keep drawing and often busts.`] : ["Hit", `${t} against a house ${d === 11 ? "Ace" : d}: hit. The house is likely to finish on 17 or more.`];
  };
  const practice = (root) => {
    root.innerHTML = `<div class="bj" style="margin-top:0;overflow:hidden">
      <img src="${BASE}bj-table-bg.png" alt="" style="position:absolute;left:50%;top:60%;width:min(92%,700px);transform:translate(-50%,-50%);opacity:0.12;pointer-events:none">
      <div style="position:relative;display:flex;flex-direction:column;gap:inherit">
        <div class="bj-top"><span class="eyebrow">Practice table</span><span class="bj-sub" data-tally style="margin:0">Won 0 · Lost 0 · Push 0</span></div>
        <div class="bj-house" style="grid-template-columns:auto minmax(0,1fr) auto"><div style="min-width:0"><div class="bj-house-name">House</div><div class="bj-sub">Stands on 17</div></div><div class="bj-hand" data-hh style="justify-content:flex-end;min-width:0"></div><div class="bj-score" data-hs></div></div>
        <div class="seat" data-seat style="background:rgba(18,16,16,0.7)"><div class="seat-top"><span class="seat-name">You</span><span class="seat-score" data-ps></span></div><div class="bj-hand" data-ph></div></div>
        <div class="bj-status" data-st aria-live="polite">Press deal to start a hand.</div>
        <div data-coach style="font-size:12px;line-height:1.7;color:var(--ink-76);text-align:center;min-height:1.7em"></div>
        <div class="bj-controls" style="flex-wrap:wrap">
          <button type="button" class="pill pill-primary" data-deal>Deal</button>
          <button type="button" class="pill pill-primary" data-hit style="display:none">Hit</button>
          <button type="button" class="pill pill-ghost" data-stand style="display:none">Stand</button>
        </div>
        <label style="display:flex;gap:10px;align-items:center;justify-content:center;font-size:12px;color:var(--ink-66);cursor:pointer"><input type="checkbox" data-tips checked style="accent-color:#e8a13c;width:18px;height:18px"> Show coach tips</label>
      </div>
    </div>`;
    const q = (s) => root.querySelector(s);
    const ui = { hh: q("[data-hh]"), hs: q("[data-hs]"), ph: q("[data-ph]"), ps: q("[data-ps]"), st: q("[data-st]"), coach: q("[data-coach]"), deal: q("[data-deal]"), hit: q("[data-hit]"), stand: q("[data-stand]"), tips: q("[data-tips]"), seat: q("[data-seat]"), tally: q("[data-tally]") };
    let shoe = deck(), P = [], D = [], open = false, live = false; const score = { w: 0, l: 0, p: 0 };
    const draw = () => { if (shoe.length < 20) shoe = deck(); return shoe.pop(); };
    const paint = () => {
      const hole = ui.hh.children[1];
      if (open && hole && hole.classList.contains("back")) hole.outerHTML = cardHtml(D[1]);
      const p = total(P).t; ui.ps.textContent = P.length ? (p > 21 ? "BUST" : p) : "";
      ui.hs.textContent = !D.length ? "" : open ? (total(D).t > 21 ? "BUST" : total(D).t) : cv(D[0].r) + "+";
      ui.seat.classList.toggle("bust", p > 21); ui.seat.classList.toggle("active", live);
      ui.tally.textContent = `Won ${score.w} · Lost ${score.l} · Push ${score.p}`;
      ui.hit.style.display = ui.stand.style.display = live ? "" : "none"; ui.deal.style.display = live ? "none" : "";
      if (live && ui.tips.checked) { const [a, why] = advice(P, D[0]); ui.coach.innerHTML = `<b style="color:var(--gold);font-weight:500">Coach: ${a}.</b> ${why}`; } else if (live) ui.coach.textContent = "";
    };
    const appendOnly = (el, c, hidden) => el.insertAdjacentHTML("beforeend", cardHtml(c, hidden));
    const finish = (msg, res) => { live = false; open = true; if (res) score[res]++; ui.st.textContent = msg; ui.coach.textContent = ""; paint(); ui.seat.classList.toggle("win", res === "w"); ui.deal.textContent = "Deal again"; };
    const houseTurn = () => {
      live = false; open = true; paint(); ui.deal.style.display = "none"; ui.coach.textContent = ""; ui.st.textContent = "House reveals…";
      const step = () => {
        const d = total(D).t;
        if (d < 17) { setTimeout(() => { const c = draw(); D.push(c); appendOnly(ui.hh, c); ui.hs.textContent = total(D).t > 21 ? "BUST" : total(D).t; ui.st.textContent = `House draws… ${total(D).t}`; step(); }, 750); return; }
        setTimeout(() => {
          const p = total(P).t;
          if (d > 21) finish(`House busts with ${d}. You win.`, "w");
          else if (p > d) finish(`${p} beats ${d}. You win.`, "w");
          else if (p < d) finish(`House wins, ${d} to ${p}.`, "l");
          else finish(`Both on ${p}. That’s a push, so nobody wins.`, "p");
        }, 650);
      };
      step();
    };
    ui.deal.addEventListener("click", () => { if (live) return;
      P = [draw(), draw()]; D = [draw(), draw()]; open = false; live = true; ui.seat.classList.remove("win");
      ui.ph.innerHTML = ""; ui.hh.innerHTML = "";
      const order = [[ui.ph, P[0]], [ui.hh, D[0]], [ui.ph, P[1]], [ui.hh, D[1], true]];
      ui.hit.style.display = ui.stand.style.display = ui.deal.style.display = "none"; ui.coach.textContent = ""; ui.st.textContent = "Dealing…";
      order.forEach(([el, c, h], i) => setTimeout(() => { appendOnly(el, c, h); if (i === 3) {
        const pb = total(P).t === 21, db = total(D).t === 21;
        if (pb || db) { open = true; return finish(pb && db ? "You both have blackjack. Push." : pb ? "Blackjack! You win." : "House has blackjack. You lose this one.", pb && db ? "p" : pb ? "w" : "l"); }
        ui.st.textContent = "Your move. Hit or stand?"; paint(); } else { const p = total(P.slice(0, el === ui.ph ? (i === 0 ? 1 : 2) : 0)).t; if (el === ui.ph && p) ui.ps.textContent = p; if (el === ui.hh && i === 1) ui.hs.textContent = cv(D[0].r) + "+"; } }, 280 * i + 100));
    });
    ui.hit.addEventListener("click", () => { if (!live) return; const c = draw(); P.push(c); appendOnly(ui.ph, c); const p = total(P).t; ui.ps.textContent = p > 21 ? "BUST" : p;
      if (p > 21) { open = true; return finish(`Bust on ${p}. The house wins without even playing.`, "l"); }
      if (p === 21) return houseTurn();
      ui.st.textContent = `You’re on ${total(P).soft ? "soft " : ""}${p}. Hit or stand?`; paint(); });
    ui.stand.addEventListener("click", () => { if (live) houseTurn(); });
    ui.tips.addEventListener("change", paint);
  };

  const init = () => {
    document.querySelectorAll("[data-bj-values]").forEach(values);
    document.querySelectorAll("[data-bj-builder]").forEach(builder);
    document.querySelectorAll("[data-bj-practice]").forEach(practice);
  };
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", init) : init();
})();
