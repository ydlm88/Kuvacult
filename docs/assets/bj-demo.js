// Animated blackjack demo. Mount with <div data-bj-demo></div>; uses the picker styles in style.css.
(() => {
  const BASE = document.currentScript ? document.currentScript.src.replace(/bj-demo\.js.*$/, "") : "../assets/";
  const CARDS = BASE + "cards/";
  const RED = { heart: 1, diamond: 1 };
  const card = (r, s) => ({ r, s });
  const face = (c) => `<img class="pc-bg" src="${CARDS}${RED[c.s] ? "card-tan" : "card-dark"}.webp" alt=""><img class="pc-r" src="${CARDS}${RED[c.s] ? "r" : "w"}-${c.r}.webp" alt=""><img class="pc-sm" src="${CARDS}${c.s}.webp" alt=""><img class="pc-s" src="${CARDS}${c.s}.webp" alt="">`;
  const back = `<img src="${CARDS}back-4b-logo.webp" alt="">`;
  const val = (cs) => { let t = 0, a = 0; cs.forEach((c) => { if (c.r === "A") { a++; t += 11; } else t += /[JQK]/.test(c.r) ? 10 : +c.r; }); while (t > 21 && a--) t -= 10; return t; };
  const EASE = "cubic-bezier(.2,.75,.25,1)";

  const PLAYERS = [
    { name: "You", film: "Animals", deal: [card("8", "club"), card("10", "spade")] },
    { name: "Josh", film: "Spider-Man: Brand New Day", deal: [card("2", "diamond"), card("3", "spade")] },
    { name: "Nastia", film: "The Thing", deal: [card("9", "heart"), card("8", "club")] },
  ];
  const HOUSE = [card("5", "club"), card("10", "diamond")];

  const build = (root) => {
    root.innerHTML = `<div class="bj" style="margin-top:0;overflow:hidden" aria-hidden="true">
      <img src="${BASE}bj-table-bg.png" alt="" style="position:absolute;left:50%;top:58%;width:min(92%,760px);transform:translate(-50%,-50%);opacity:0.13;pointer-events:none;z-index:0">
      <div style="position:relative;z-index:1;display:flex;flex-direction:column;gap:inherit">
        <div class="bj-top"><span class="eyebrow">Blackjack tiebreaker</span></div>
        <div class="bj-house" style="grid-template-columns:auto minmax(0,1fr) auto"><div style="min-width:0"><div class="bj-house-name">House</div><div class="bj-sub">Dealer</div></div><div class="bj-hand" data-h style="justify-content:flex-end;min-width:0"></div><div class="bj-score" data-hs></div></div>
        <div class="bj-table" style="background:rgba(11,10,9,0.35);grid-template-columns:repeat(auto-fill,minmax(min(100%,150px),1fr));min-height:0">${PLAYERS.map((p, i) => `<div class="seat" data-seat="${i}"><div class="seat-top"><span class="seat-name">${p.name}</span><span class="seat-score"></span></div><div class="bj-hand"></div><div class="seat-film">→ ${p.film}</div></div>`).join("")}</div>
        <div class="bj-status" data-st></div>
        <div class="bj-result" data-res hidden><div class="eyebrow">Tonight you’re watching</div><div class="bj-winner"></div></div>
      </div>
    </div>`;
    const q = (s) => root.querySelector(s);
    const table = q(".bj");
    const seats = [...root.querySelectorAll(".seat")];
    const houseHand = q("[data-h]");
    let hands, house, timer, running = false, step = 0;
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

    // Deal a card from the shoe (top-right of the table) into a hand.
    const deal = (handEl, c, hidden) => {
      const el = document.createElement("div");
      el.className = "pcard" + (hidden ? " back" : "");
      el.style.animation = "none";
      el.innerHTML = hidden ? back : face(c);
      handEl.appendChild(el);
      if (reduce) return el;
      const t = table.getBoundingClientRect(), r = el.getBoundingClientRect();
      const dx = t.right - 70 - r.left, dy = t.top + 20 - r.top;
      el.style.transition = "none";
      el.style.opacity = "0";
      el.style.transform = `translate(${dx}px, ${dy}px) rotate(-18deg) scale(0.9)`;
      el.offsetWidth;
      el.style.transition = `transform 560ms ${EASE}, opacity 200ms ease`;
      el.style.opacity = "1";
      el.style.transform = `rotate(${(Math.random() * 4 - 2).toFixed(1)}deg)`;
      return el;
    };
    // Flip the hole card over.
    const flip = (el, c) => {
      if (reduce) { el.className = "pcard"; el.innerHTML = face(c); return; }
      el.style.transition = `transform 180ms ease-in`;
      el.style.transform = "scaleX(0)";
      setTimeout(() => { el.className = "pcard"; el.innerHTML = face(c); el.style.transition = `transform 220ms ${EASE}`; el.style.transform = "scaleX(1)"; }, 180);
    };

    const status = (t) => { q("[data-st]").textContent = t; };
    const score = (i) => { const v = val(hands[i]); const s = seats[i]; s.querySelector(".seat-score").textContent = v > 21 ? "BUST" : v; s.classList.toggle("bust", v > 21); };
    const give = (i, c) => { hands[i].push(c); deal(seats[i].querySelector(".bj-hand"), c); setTimeout(() => score(i), reduce ? 0 : 420); };
    const active = (i) => seats.forEach((s, k) => s.classList.toggle("active", k === i));
    const houseScore = (open) => { q("[data-hs]").textContent = open ? (val(house) > 21 ? "BUST" : val(house)) : val([house[0]]) + "+"; };
    const reset = () => {
      hands = PLAYERS.map(() => []); house = [];
      houseHand.innerHTML = ""; q("[data-hs]").textContent = "";
      seats.forEach((s) => { s.className = "seat"; s.querySelector(".bj-hand").innerHTML = ""; s.querySelector(".seat-score").textContent = ""; });
      q("[data-res]").hidden = true; status("3 players at the table. Dealing…");
    };

    const script = [
      [900, reset],
      [700, () => { house.push(HOUSE[0]); deal(houseHand, HOUSE[0]); setTimeout(() => houseScore(false), reduce ? 0 : 420); }],
      ...PLAYERS.map((p, i) => [420, () => give(i, p.deal[0])]),
      [420, () => { house.push(HOUSE[1]); deal(houseHand, HOUSE[1], true); }],
      ...PLAYERS.map((p, i) => [420, () => give(i, p.deal[1])]),
      [1000, () => { active(0); status("Your turn. Hit or stand?"); }],
      [1400, () => { give(0, card("6", "club")); status("You hit…"); }],
      [800, () => status("…and bust.")],
      [1100, () => { active(1); status("Josh’s turn…"); }],
      [1100, () => give(1, card("5", "spade"))],
      [1100, () => give(1, card("K", "club"))],
      [1000, () => status("Josh stands on 20.")],
      [1100, () => { active(2); status("Nastia’s turn, from her phone…"); }],
      [1400, () => status("Nastia stands on 17.")],
      [1000, () => { active(-1); status("House reveals…"); flip(houseHand.lastChild, HOUSE[1]); setTimeout(() => houseScore(true), reduce ? 0 : 400); }],
      [1300, () => { const c = card("7", "spade"); house.push(c); deal(houseHand, c); setTimeout(() => { houseScore(true); status("House busts."); }, reduce ? 0 : 450); }],
      [1500, () => { seats[1].classList.add("win"); status("Josh wins with 20."); }],
      [900, () => { q("[data-res] .bj-winner").textContent = PLAYERS[1].film; q("[data-res]").hidden = false; }],
      [4500, () => {}],
    ];
    const tick = () => {
      if (!running) return;
      script[step][1]();
      step = (step + 1) % script.length;
      timer = setTimeout(tick, script[step][0]);
    };
    let first = true;
    const play = () => { if (running) return; running = true; if (first) { first = false; step = 1; timer = setTimeout(tick, 150); return; } timer = setTimeout(tick, script[step][0]); };
    const pause = () => { running = false; clearTimeout(timer); };

    if (reduce) { script.forEach(([, fn]) => fn()); return; }
    reset();
    new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? play() : pause())), { threshold: 0.05, rootMargin: "0px 0px 120px 0px" }).observe(root);
  };

  const init = () => document.querySelectorAll("[data-bj-demo]").forEach(build);
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", init) : init();
})();
