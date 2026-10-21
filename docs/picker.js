// Movie night picker — blackjack tiebreaker. Local pass-and-play or online rooms via Supabase Realtime.
const SUPABASE_URL = "https://yckvotxsknnhoqndboht.supabase.co";
const SUPABASE_KEY = "sb_publishable_hEEU8_mEDR9Ai8OsaK3vYQ_zd1Wq1z4"; // publishable key, safe in the browser

(() => {
  const $ = (id) => document.getElementById(id);
  const CARDS = "../assets/cards/";
  const SUITS = [["spade", "b"], ["club", "b"], ["heart", "r"], ["diamond", "r"]];
  const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
  const me = (sessionStorage.kvId ||= Math.random().toString(36).slice(2, 10));
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  let mode = null;       // "local" | "host" | "guest"
  let S = null;          // game state (authoritative on host/local)
  let channel = null, code = "", hostId = null, busy = false;
  let localPlayers = [{ id: "p0", name: "You", film: "The Thing" }, { id: "p1", name: "Josh", film: "Spider-Man: Brand New Day" }];

  // ---------- rules ----------
  const value = (h) => { let t = 0, a = 0; h.forEach((c) => { if (c.r === "A") { a++; t += 11; } else t += "JQK".includes(c.r) ? 10 : +c.r; }); while (t > 21 && a) { t -= 10; a--; } return t; };
  const newDeck = () => { const d = []; SUITS.forEach(([s, col]) => RANKS.forEach((r) => d.push({ r, s, col }))); for (let i = d.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [d[i], d[j]] = [d[j], d[i]]; } return d; };

  const deal = (players, only) => {
    const deck = newDeck();
    const hands = players.map((p, i) => { const inn = !only || only.includes(i); return { cards: inn ? [deck.pop(), deck.pop()] : [], done: !inn, out: !inn, win: false }; });
    const st = { phase: "play", players, hands, house: [deck.pop(), deck.pop()], houseOpen: false, deck, turn: 0, status: "", winner: null };
    skip(st); return st;
  };
  const isMe = (p) => p && (p.name === "You" || (mode !== "local" && p.id === me));
  const skip = (st) => { while (st.turn < st.players.length && st.hands[st.turn].done) st.turn++; const p = st.players[st.turn]; if (p) st.status = isMe(p) ? "Your turn" : `${p.name}’s turn`; };
  const act = async (type, by) => {
    if (!S || S.phase !== "play" || busy) return;
    const p = S.players[S.turn]; if (!p || (mode === "host" && p.id !== by)) return;
    const h = S.hands[S.turn];
    if (type === "hit") { h.cards.push(S.deck.pop()); const v = value(h.cards); if (v >= 21) { h.done = true; S.status = v > 21 ? (isMe(p) ? "You bust." : `${p.name} busts.`) : (isMe(p) ? "You hit 21!" : `${p.name} hits 21!`); push(); busy = true; await wait(900); busy = false; S.turn++; skip(S); } }
    else { h.done = true; S.turn++; skip(S); }
    if (S.turn >= S.players.length) return finish();
    push();
  };
  const finish = async () => {
    S.houseOpen = true; S.status = "House reveals…"; push(); busy = true;
    while (value(S.house) < 17) { await wait(650); S.house.push(S.deck.pop()); push(); }
    await wait(500); busy = false;
    const live = S.hands.map((h, i) => ({ i, v: value(h.cards), h })).filter((x) => !x.h.out && x.v <= 21);
    if (!live.length) { S.status = "Everyone bust. Dealing again…"; push(); await wait(1400); S = deal(S.players); return push(); }
    const best = Math.max(...live.map((x) => x.v)), top = live.filter((x) => x.v === best);
    if (top.length > 1) { S.status = `${top.map((x) => S.players[x.i].name).join(" and ")} tied on ${best}. Dealing them again…`; push(); await wait(1700); S = deal(S.players, top.map((x) => x.i)); return push(); }
    const w = top[0]; S.hands[w.i].win = true; S.phase = "done"; S.winner = { name: S.players[w.i].name, film: S.players[w.i].film, v: best };
    S.status = isMe(S.players[w.i]) ? `You win with ${best}.` : `${S.winner.name} wins with ${best}.`; push();
  };

  // ---------- network ----------
  const push = () => { render(); if (mode === "host" && channel) channel.send({ type: "broadcast", event: "state", payload: { ...S, deck: undefined } }); };
  const loadSdk = () => window.supabase ? Promise.resolve() : new Promise((res, rej) => { const s = document.createElement("script"); s.src = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
  const makeCode = () => Array.from({ length: 4 }, () => "ABCDEFGHJKLMNPQRSTUVWXYZ"[Math.floor(Math.random() * 24)]).join("");

  const connect = async (roomCode, profile, asHost) => {
    await loadSdk();
    const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    code = roomCode; mode = asHost ? "host" : "guest"; hostId = asHost ? me : null;
    channel = sb.channel("kv-bj-" + code, { config: { broadcast: { self: false }, presence: { key: me } } });
    channel.on("presence", { event: "sync" }, () => {
      const ps = channel.presenceState();
      const list = Object.entries(ps).map(([id, arr]) => ({ id, ...arr[0] })).sort((a, b) => a.t - b.t);
      if (mode === "host" && (!S || S.phase === "lobby")) { S = { phase: "lobby", players: list.slice(0, 8).map(({ id, name, film, host }) => ({ id, name, film, host })) }; push(); }
      else if (mode === "host" && S) {
        let changed = false;
        list.forEach(({ id, name, film, host }) => { if (!S.players.some((p) => p.id === id) && S.players.length < 8) { S.players.push({ id, name, film, host }); S.hands.push({ cards: [], done: true, out: true, late: true, win: false }); changed = true; } });
        if (changed) push();
      }
      if (mode === "guest") { const h = list.find((p) => p.host); if (hostId && !h) { show("left"); } if (h) hostId = h.id; }
    });
    channel.on("broadcast", { event: "state" }, ({ payload }) => { if (mode === "guest") { S = payload; render(); } });
    channel.on("broadcast", { event: "action" }, ({ payload }) => { if (mode === "host") act(payload.type, payload.id); });
    channel.on("broadcast", { event: "hello" }, () => { if (mode === "host") push(); });
    await new Promise((res, rej) => channel.subscribe(async (st) => {
      if (st === "SUBSCRIBED") { await channel.track({ ...profile, host: asHost, t: Date.now() }); if (!asHost) channel.send({ type: "broadcast", event: "hello", payload: {} }); res(); }
      if (st === "CHANNEL_ERROR" || st === "TIMED_OUT") rej(new Error(st));
    }));
    history.replaceState(null, "", "?room=" + code);
  };
  const leave = () => { if (channel) channel.unsubscribe(); channel = null; mode = null; S = null; history.replaceState(null, "", location.pathname); };

  // ---------- rendering ----------
  const cardHtml = (c, hidden) => {
    if (hidden) return `<div class="pcard back"><img src="${CARDS}back-4b-logo.webp" alt="Face-down card"></div>`;
    const red = c.col === "r";
    return `<div class="pcard"><img class="pc-bg" src="${CARDS}${red ? "card-tan" : "card-dark"}.webp" alt=""><img class="pc-r" src="${CARDS}${red ? "r" : "w"}-${c.r}.webp" alt="${c.r}"><img class="pc-sm" src="${CARDS}${c.s}.webp" alt=""><img class="pc-s" src="${CARDS}${c.s}.webp" alt="of ${c.s}s"></div>`;
  };
  const views = ["mode", "local", "create", "join", "lobby", "game", "left"];
  const show = (v) => views.forEach((x) => { const el = $("bj-" + x); if (el) el.hidden = x !== v; });

  const renderRows = () => {
    $("bj-rows").innerHTML = localPlayers.map((p, i) => `<div class="bj-row"><input aria-label="Player name" maxlength="14" value="${esc(p.name)}" data-i="${i}" data-k="name"><input aria-label="Film" maxlength="60" placeholder="Film title" value="${esc(p.film)}" data-i="${i}" data-k="film">${i > 1 ? `<button type="button" aria-label="Remove player" data-rm="${i}">×</button>` : "<span></span>"}</div>`).join("");
    $("bj-add").disabled = localPlayers.length >= 6;
  };

  const render = () => {
    if (!S) return;
    if (S.phase === "lobby") {
      show("lobby");
      $("bj-code").textContent = code;
      $("bj-lobby-list").innerHTML = S.players.map((p) => `<li><span>${esc(p.name)}${p.host ? ' <em>host</em>' : ""}</span><span>${esc(p.film)}</span></li>`).join("");
      const n = S.players.length;
      $("bj-start").hidden = mode !== "host"; $("bj-start").disabled = n < 2;
      $("bj-lobby-note").textContent = mode === "host" ? (n < 2 ? "Waiting for at least one friend to join…" : `${n} players ready.`) : "Waiting for the host to deal…";
      if (mode === "host" && n >= 2) $("bj-lobby-note").textContent += " More friends can still join after you deal.";
      return;
    }
    show("game");
    $("bj-house-hand").innerHTML = S.house.map((c, i) => cardHtml(c, i === 1 && !S.houseOpen)).join("");
    $("bj-house-score").textContent = S.houseOpen ? value(S.house) : value([S.house[0]]) + "+";
    $("bj-table").innerHTML = S.players.map((p, i) => {
      const h = S.hands[i], v = value(h.cards), active = S.phase === "play" && i === S.turn && !h.done;
      const cls = ["seat", h.out && "out", active && "active", v > 21 && "bust", h.win && "win", p.id === me && mode !== "local" && "mine"].filter(Boolean).join(" ");
      return `<div class="${cls}"><div class="seat-top"><span class="seat-name">${esc(p.name)}</span><span class="seat-score">${h.out ? "—" : v > 21 ? "BUST" : v}</span></div><div class="bj-hand">${h.cards.map((c) => cardHtml(c)).join("")}</div><div class="seat-film">${h.late ? "Joins next hand" : "→ " + esc(p.film || "Untitled")}</div></div>`;
    }).join("");
    const cur = S.players[S.turn], mine = S.phase === "play" && cur && (mode === "local" || cur.id === me) && !busy;
    $("bj-status").textContent = S.phase === "play" && cur && mode !== "local" && cur.id === me ? "Your turn. Hit or stand?" : S.status;
    $("bj-controls").hidden = !mine;
    if (mine && mode === "local" && !isMe(cur)) { $("bj-hit").textContent = `Hit for ${cur.name}`; $("bj-stand").textContent = `${cur.name} stands`; } else { $("bj-hit").textContent = "Hit"; $("bj-stand").textContent = "Stand"; }
    $("bj-result").hidden = S.phase !== "done";
    if (S.winner) $("bj-winner").textContent = S.winner.film || "Untitled";
    $("bj-again").hidden = mode === "guest";
    $("bj-room-tag").hidden = mode === "local"; $("bj-room-tag").textContent = "Room " + code;
  };

  // ---------- events ----------
  const send = (type) => { if (mode === "guest") channel.send({ type: "broadcast", event: "action", payload: { type, id: me } }); else act(type, me); };
  $("bj-hit").onclick = () => send("hit");
  $("bj-stand").onclick = () => send("stand");
  $("bj-again").onclick = () => { S = deal(S.players); push(); };
  $("bj-start").onclick = () => { S = deal(S.players); push(); };
  document.querySelectorAll("[data-go]").forEach((b) => (b.onclick = () => { if (b.dataset.go === "mode") leave(); show(b.dataset.go); }));
  $("bj-rows").addEventListener("input", (e) => { const t = e.target; if (t.dataset.k) localPlayers[+t.dataset.i][t.dataset.k] = t.value; });
  $("bj-rows").addEventListener("click", (e) => { const r = e.target.dataset.rm; if (r) { localPlayers.splice(+r, 1); renderRows(); } });
  $("bj-add").onclick = () => { if (localPlayers.length < 6) { localPlayers.push({ id: "p" + Date.now(), name: "Player " + (localPlayers.length + 1), film: "" }); renderRows(); } };
  $("bj-local-deal").onclick = () => {
    const ps = localPlayers.map((p) => ({ ...p, name: p.name.trim() || "Player" }));
    const empty = [...$("bj-rows").querySelectorAll('input[data-k="film"]')].find((x) => !x.value.trim());
    if (empty) return empty.focus();
    mode = "local"; S = deal(ps); render();
  };
  const err = (id, m) => ($(id).textContent = m);
  $("bj-create-go").onclick = async () => {
    const name = $("bj-c-name").value.trim(), film = $("bj-c-film").value.trim();
    if (!name || !film) return err("bj-c-err", "Add your name and your film.");
    err("bj-c-err", "Opening room…");
    try { await connect(makeCode(), { name, film }, true); err("bj-c-err", ""); } catch (e) { leave(); err("bj-c-err", "Couldn’t open a room. Try again, or play on one device."); }
  };
  $("bj-join-go").onclick = async () => {
    const c = $("bj-j-code").value.trim().toUpperCase(), name = $("bj-j-name").value.trim(), film = $("bj-j-film").value.trim();
    if (c.length !== 4 || !name || !film) return err("bj-j-err", "Enter the 4-letter code, your name and your film.");
    err("bj-j-err", "Joining…");
    try { await connect(c, { name, film }, false); err("bj-j-err", ""); if (!S) { show("lobby"); $("bj-code").textContent = c; $("bj-lobby-note").textContent = "Waiting for the host…"; $("bj-start").hidden = true; } } catch (e) { leave(); err("bj-j-err", "Couldn’t join that room. Check the code."); }
  };
  $("bj-copy-link").onclick = async () => { const url = location.origin + location.pathname + "?room=" + code; try { await navigator.clipboard.writeText(url); $("bj-copy-link").textContent = "Link copied"; setTimeout(() => ($("bj-copy-link").textContent = "Copy invite link"), 1600); } catch {} };
  // ---------- shareable result card ----------
  const loadImg = (src) => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
  const wrap = (x, text, max) => { const words = text.split(" "), lines = []; let cur = ""; words.forEach((w) => { const t = cur ? cur + " " + w : w; if (x.measureText(t).width > max && cur) { lines.push(cur); cur = w; } else cur = t; }); lines.push(cur); return lines; };
  const shareCard = async () => {
    if (!S || !S.winner) return;
    await document.fonts.ready;
    const W = 1080, H = 1350, c = document.createElement("canvas"); c.width = W; c.height = H; const x = c.getContext("2d");
    const g = x.createRadialGradient(W / 2, 520, 40, W / 2, 520, 820); g.addColorStop(0, "#2a1d10"); g.addColorStop(1, "#080707"); x.fillStyle = g; x.fillRect(0, 0, W, H);
    x.strokeStyle = "rgba(233,196,104,0.5)"; x.lineWidth = 3; x.strokeRect(48, 48, W - 96, H - 96);
    try { const logo = await loadImg("../assets/logo.webp"); x.drawImage(logo, W / 2 - 90, 120, 180, 180); } catch {}
    x.textAlign = "center"; x.fillStyle = "#e8a13c"; x.font = "500 30px 'JetBrains Mono', monospace"; x.fillText("TONIGHT WE’RE WATCHING", W / 2, 400);
    x.fillStyle = "#f7ecdc"; x.font = "120px 'Instrument Serif', Georgia, serif";
    let lines = wrap(x, S.winner.film || "Untitled", W - 200); if (lines.length > 3) { x.font = "88px 'Instrument Serif', Georgia, serif"; lines = wrap(x, S.winner.film, W - 200).slice(0, 4); }
    const lh = parseInt(x.font) * 1.02, y0 = 560; lines.forEach((l, i) => x.fillText(l, W / 2, y0 + i * lh));
    const yb = y0 + lines.length * lh + 50;
    x.fillStyle = "#E9C468"; x.font = "italic 54px 'Instrument Serif', Georgia, serif"; x.fillText(S.winner.name + " won with " + S.winner.v, W / 2, yb);
    x.fillStyle = "rgba(243,228,207,0.7)"; x.font = "28px 'JetBrains Mono', monospace";
    const others = S.players.map((pl, i) => ({ pl, v: S.hands[i].cards.length ? value(S.hands[i].cards) : null })).filter((o) => o.pl.name !== S.winner.name && o.v !== null).slice(0, 4);
    others.forEach((o, i) => x.fillText(o.pl.name + " · " + (o.v > 21 ? "bust" : o.v) + " · " + (o.pl.film || "").slice(0, 28), W / 2, yb + 90 + i * 46));
    x.fillStyle = "#f3e4cf"; x.font = "500 30px 'JetBrains Mono', monospace"; x.fillText("Settled with blackjack on KUVACULT", W / 2, H - 150);
    x.fillStyle = "rgba(243,228,207,0.6)"; x.font = "26px 'JetBrains Mono', monospace"; x.fillText(location.host + "/tools/movie-night-picker", W / 2, H - 100);
    const blob = await new Promise((r) => c.toBlob(r, "image/png"));
    const file = new File([blob], "kuvacult-movie-night.png", { type: "image/png" });
    const text = "Tonight we’re watching " + (S.winner.film || "a movie") + ". Settled with blackjack on Kuvacult.";
    const url = location.origin + location.pathname;
    if (navigator.canShare && navigator.canShare({ files: [file] })) { try { await navigator.share({ files: [file], text, url }); return; } catch (e) { if (e.name === "AbortError") return; } }
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = file.name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    $("bj-share").textContent = "Image saved"; setTimeout(() => ($("bj-share").textContent = "Share result"), 1800);
  };
  $("bj-share").onclick = shareCard;
  addEventListener("beforeunload", () => channel && channel.unsubscribe());

  renderRows();
  const q = new URLSearchParams(location.search).get("room");
  if (q) { $("bj-j-code").value = q.toUpperCase(); show("join"); } else show("mode");
})();
