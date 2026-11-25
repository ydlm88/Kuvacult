// Séance demo: the candle lights and the LIVE badge appears. Mount with <div data-seance-demo> inside a sized container.
(() => {
  const BASE = document.currentScript ? document.currentScript.src.replace(/seance-demo\.js.*$/, "") : "assets/";
  const W = 1600, H = 834;
  const clip = (x0, y0, x1, y1) => `inset(${(y0 / H * 100).toFixed(2)}% ${(100 - x1 / W * 100).toFixed(2)}% ${(100 - y1 / H * 100).toFixed(2)}% ${(x0 / W * 100).toFixed(2)}%)`;
  const pct = (v, t) => (v / t * 100).toFixed(2) + "%";
  const layer = (c, extra = "") => `<img src="${BASE}ritual.webp" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:top;clip-path:${c};opacity:0;pointer-events:none;${extra}">`;

  const build = (root) => {
    const base = root.querySelector("img");
    if (base) base.src = BASE + "ritual-unlit.webp";
    root.style.position = "relative";
    root.insertAdjacentHTML("beforeend",
      layer(clip(28, 140, 430, 332), "") +                                    // glow
      layer(clip(72, 150, 136, 212), `transform-origin:${pct(104, W)} ${pct(211, H)}`) + // flame
      layer(clip(284, 208, 354, 236)) +                                       // LIVE
      layer(clip(174, 242, 606, 272)) +                                       // subtitle
      layer(clip(1381, 254, 1514, 282)) +                                     // blow it out
      `<div style="position:absolute;left:${pct(1348, W)};top:${pct(195, H)};width:${pct(202, W)};height:${pct(54, H)};border-radius:10px;background:rgba(233,196,104,0.22);opacity:0;pointer-events:none"></div>` +
      `<div style="position:absolute;left:${pct(295, W)};top:${pct(222, H)};width:${pct(10, W)};aspect-ratio:1;border-radius:50%;transform:translate(-50%,-50%);border:1px solid rgba(70,215,120,0.9);box-sizing:border-box;opacity:0;pointer-events:none"></div>`);
    const L = [...root.querySelectorAll("img")].slice(-5);
    const [glow, flame, live, sub, blow] = L;
    const kids = root.children, press = kids[kids.length - 2], ring = kids[kids.length - 1];
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) { L.forEach((e) => (e.style.opacity = 1)); return; }

    let anims = [], timers = [], running = false;
    const at = (ms, fn) => timers.push(setTimeout(fn, ms));
    const anim = (el, kf, o) => { const a = el.animate(kf, { fill: "forwards", easing: "ease", ...o }); anims.push(a); return a; };
    const cycle = () => {
      anims.forEach((a) => a.cancel()); anims = [];
      [glow, flame, live, sub, blow].forEach((e) => (e.style.opacity = 0));
      at(1100, () => anim(press, [{ opacity: 0 }, { opacity: 1 }, { opacity: 0 }], { duration: 420 }));
      at(1450, () => {
        anim(flame, [{ opacity: 0, transform: "scale(0.35, 0.15)" }, { opacity: 0.85, transform: "scale(0.8, 0.7)", offset: 0.35 }, { opacity: 1, transform: "scale(1, 1)" }], { duration: 1300, easing: "cubic-bezier(.25,.6,.3,1)" });
        anim(glow, [{ opacity: 0 }, { opacity: 0.6, offset: 0.4 }, { opacity: 1 }], { duration: 2000, delay: 200, easing: "ease-out" });
      });
      at(2750, () => {
        anim(flame, [{ transform: "scale(1, 1) skewX(0deg)" }, { transform: "scale(0.99, 1.025) skewX(-0.6deg)", offset: 0.3 }, { transform: "scale(1.005, 0.985) skewX(0.5deg)", offset: 0.65 }, { transform: "scale(1, 1) skewX(0deg)" }], { duration: 2800, iterations: Infinity, easing: "ease-in-out" });
      });
      at(3650, () => {
        anim(glow, [{ opacity: 1 }, { opacity: 0.9 }, { opacity: 1 }], { duration: 3200, iterations: Infinity, easing: "ease-in-out" });
      });
      at(2600, () => {
        anim(live, [{ opacity: 0 }, { opacity: 1 }], { duration: 600 });
        ring.style.opacity = 1;
        anim(ring, [{ transform: "translate(-50%,-50%) scale(1)", opacity: 0.5 }, { transform: "translate(-50%,-50%) scale(2.6)", opacity: 0 }], { duration: 1400, iterations: Infinity, easing: "ease-out" });
      });
      at(2950, () => anim(sub, [{ opacity: 0 }, { opacity: 1 }], { duration: 600 }));
      at(3250, () => anim(blow, [{ opacity: 0 }, { opacity: 1 }], { duration: 600 }));
      at(8200, () => {
        anims.forEach((a) => a.cancel()); anims = [];
        [glow, flame, live, sub, blow].forEach((e) => (e.style.opacity = 1));
        ring.style.opacity = 0;
        anim(flame, [{ opacity: 1, transform: "scale(1, 1)" }, { opacity: 0, transform: "scale(0.5, 0.25)" }], { duration: 700, easing: "ease-in" });
        anim(glow, [{ opacity: 1 }, { opacity: 0 }], { duration: 1100, easing: "ease-in-out" });
        [live, sub, blow].forEach((e) => anim(e, [{ opacity: 1 }, { opacity: 0 }], { duration: 700, delay: 150 }));
      });
      at(9900, cycle);
    };
    const play = () => { if (running) return; running = true; cycle(); };
    const pause = () => { running = false; timers.forEach(clearTimeout); timers = []; anims.forEach((a) => a.cancel()); anims = []; [glow, flame, live, sub, blow].forEach((e) => (e.style.opacity = 1)); ring.style.opacity = 0; };
    new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? play() : pause())), { threshold: 0.3 }).observe(root);
  };
  const init = () => document.querySelectorAll("[data-seance-demo]").forEach(build);
  document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", init) : init();
})();
