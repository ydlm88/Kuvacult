(() => {
  const F = (g, list) => list.map(([t, y, ...extra]) => ({ t, y, g: [g, ...extra] }));
  const FILMS = [
    ...F('Horror', [['The Thing',1982,'Sci-fi'],['The Shining',1980],['Evil Dead II',1987,'Comedy'],['Suspiria',1977],['The Texas Chain Saw Massacre',1974],['An American Werewolf in London',1981,'Comedy'],['Night of the Living Dead',1968],['Dawn of the Dead',1978],['Rosemary’s Baby',1968,'Thriller'],['The Wicker Man',1973,'Thriller'],['Halloween',1978],['Re-Animator',1985,'Comedy'],['Hereditary',2018],['The Witch',2015],['It Follows',2014]]),
    ...F('Comedy', [['The Big Lebowski',1998,'Crime'],['Monty Python and the Holy Grail',1975,'Fantasy'],['This Is Spinal Tap',1984],['Office Space',1999],['Shaun of the Dead',2004,'Horror'],['Hot Fuzz',2007,'Action','Crime'],['Withnail and I',1987,'Drama'],['Airplane!',1980],['Groundhog Day',1993,'Romance','Fantasy'],['What We Do in the Shadows',2014,'Horror'],['Dr. Strangelove',1964],['Rushmore',1998,'Drama'],['The Royal Tenenbaums',2001,'Drama'],['Dazed and Confused',1993]]),
    ...F('Sci-fi', [['Blade Runner',1982,'Thriller'],['Brazil',1985,'Comedy'],['Donnie Darko',2001,'Thriller'],['RoboCop',1987,'Action'],['Stalker',1979,'Drama'],['Gattaca',1997,'Drama'],['Children of Men',2006,'Thriller'],['Primer',2004,'Thriller'],['Moon',2009,'Drama'],['12 Monkeys',1995,'Thriller'],['Alien',1979,'Horror'],['Videodrome',1983,'Horror'],['The Matrix',1999,'Action'],['Ex Machina',2014,'Thriller']]),
    ...F('Thriller', [['Memento',2000],['Fight Club',1999,'Drama'],['Se7en',1995,'Crime'],['Blue Velvet',1986,'Crime'],['Mulholland Drive',2001,'Drama'],['Zodiac',2007,'Crime'],['Nightcrawler',2014,'Crime'],['Rear Window',1954],['The Vanishing',1988],['Prisoners',2013,'Crime'],['Taxi Driver',1976,'Crime','Drama'],['Parasite',2019,'Drama','Comedy']]),
    ...F('Drama', [['Harold and Maude',1971,'Comedy','Romance'],['Paris, Texas',1984],['The Shawshank Redemption',1994],['One Flew Over the Cuckoo’s Nest',1975],['Requiem for a Dream',2000],['Trainspotting',1996,'Comedy','Crime'],['Lost in Translation',2003,'Romance'],['Magnolia',1999],['Synecdoche, New York',2008],['There Will Be Blood',2007],['Whiplash',2014],['Moonlight',2016],['Aftersun',2022]]),
    ...F('Action', [['Mad Max: Fury Road',2015,'Sci-fi'],['Mad Max 2: The Road Warrior',1981,'Sci-fi'],['Die Hard',1988],['John Wick',2014,'Crime'],['The Raid',2011],['Big Trouble in Little China',1986,'Comedy','Fantasy'],['Hard Boiled',1992,'Crime'],['Kill Bill: Vol. 1',2003,'Crime'],['Terminator 2: Judgment Day',1991,'Sci-fi'],['Aliens',1986,'Sci-fi'],['Predator',1987,'Sci-fi'],['Enter the Dragon',1973],['Seven Samurai',1954,'Drama'],['Crouching Tiger, Hidden Dragon',2000,'Fantasy','Romance']]),
    ...F('Animation', [['Akira',1988,'Sci-fi','Action'],['Ghost in the Shell',1995,'Sci-fi'],['Perfect Blue',1997,'Thriller','Horror'],['Paprika',2006,'Sci-fi'],['Spirited Away',2001,'Fantasy'],['Princess Mononoke',1997,'Fantasy','Action'],['My Neighbor Totoro',1988,'Fantasy'],['Nausicaä of the Valley of the Wind',1984,'Fantasy','Sci-fi'],['Grave of the Fireflies',1988,'Drama'],['The Iron Giant',1999,'Sci-fi'],['Fantastic Planet',1973,'Sci-fi'],['Fantastic Mr. Fox',2009,'Comedy'],['Coraline',2009,'Fantasy','Horror'],['Spider-Man: Into the Spider-Verse',2018,'Action']]),
    ...F('Romance', [['Before Sunrise',1995,'Drama'],['In the Mood for Love',2000,'Drama'],['Eternal Sunshine of the Spotless Mind',2004,'Sci-fi','Drama'],['Amélie',2001,'Comedy'],['Chungking Express',1994,'Drama'],['Punch-Drunk Love',2002,'Comedy'],['True Romance',1993,'Crime','Action'],['Her',2013,'Sci-fi','Drama'],['Wings of Desire',1987,'Fantasy','Drama'],['Portrait of a Lady on Fire',2019,'Drama'],['Say Anything...',1989,'Comedy'],['Edward Scissorhands',1990,'Fantasy']]),
    ...F('Crime', [['Pulp Fiction',1994,'Thriller'],['Reservoir Dogs',1992,'Thriller'],['Goodfellas',1990,'Drama'],['Fargo',1996,'Comedy','Thriller'],['The Godfather',1972,'Drama'],['City of God',2002,'Drama'],['Lock, Stock and Two Smoking Barrels',1998,'Comedy'],['Snatch',2000,'Comedy'],['Scarface',1983,'Drama'],['The Usual Suspects',1995,'Thriller'],['Chinatown',1974,'Thriller'],['Jackie Brown',1997],['Léon: The Professional',1994,'Action','Thriller'],['Heat',1995,'Action'],['Drive',2011,'Thriller','Action']]),
    ...F('Fantasy', [['The Princess Bride',1987,'Comedy','Romance'],['Pan’s Labyrinth',2006,'Drama'],['Labyrinth',1986],['The Dark Crystal',1982],['Big Fish',2003,'Drama'],['Beetlejuice',1988,'Comedy','Horror'],['The NeverEnding Story',1984],['The Fall',2006,'Drama'],['Howl’s Moving Castle',2004,'Animation','Romance'],['The Lord of the Rings: The Fellowship of the Ring',2001,'Action']])
  ];
  const GENRES = ['Horror','Comedy','Sci-fi','Thriller','Drama','Action','Animation','Romance','Crime','Fantasy'];
  const ORDER = [0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26];
  const REDS = new Set([1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]);
  const RED = '#7d2620', BLACK = '#141110', GREEN = '#2c5a40';
  const SEG = 360 / ORDER.length;
  const colorOf = n => n === 0 ? 'green' : REDS.has(n) ? 'red' : 'black';
  const $ = id => document.getElementById(id);

  const wheel = $('rw-wheel'), ballRing = $('rw-ball'), chips = $('rw-genres'), poolEl = $('rw-pool');
  const spinBtn = $('rw-spin'), result = $('rw-result'), ownBox = $('rw-own');
  if (!wheel) return;

  wheel.style.background = 'conic-gradient(' + ORDER.map((n, i) => {
    const c = n === 0 ? GREEN : REDS.has(n) ? RED : BLACK;
    return `${c} ${i * SEG}deg ${(i + 1) * SEG}deg`;
  }).join(',') + ')';
  ORDER.forEach((n, i) => {
    const s = document.createElement('span');
    s.className = 'rw-num';
    s.textContent = n;
    s.style.transform = `rotate(${i * SEG + SEG / 2}deg)`;
    wheel.appendChild(s);
  });

  let picked = new Set(), mode = 'ours', spinning = false, rot = 0, last = null;
  const sp = new URLSearchParams(location.search).get('genre');
  if (sp) sp.split(',').forEach(g => { const m = GENRES.find(x => x.toLowerCase() === g.toLowerCase()); if (m) picked.add(m); });

  function renderChips() {
    chips.innerHTML = '';
    const all = document.createElement('button');
    all.type = 'button'; all.className = 'rw-chip'; all.textContent = 'All genres';
    all.setAttribute('aria-pressed', picked.size === 0);
    all.onclick = () => { picked.clear(); renderChips(); };
    chips.appendChild(all);
    GENRES.forEach(g => {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'rw-chip'; b.textContent = g;
      b.setAttribute('aria-pressed', picked.has(g));
      b.onclick = () => { picked.has(g) ? picked.delete(g) : picked.add(g); renderChips(); };
      chips.appendChild(b);
    });
    updatePool();
  }
  function pool() {
    if (mode === 'own') return ownBox.value.split('\n').map(s => s.trim()).filter(Boolean).map(t => ({ t }));
    return picked.size ? FILMS.filter(f => f.g.some(g => picked.has(g))) : FILMS;
  }
  function updatePool() {
    const n = pool().length;
    poolEl.textContent = n ? `${n} ${n === 1 ? 'film' : 'films'} on the table · 1 in ${n} odds` : 'Add at least one film to spin';
    spinBtn.disabled = !n || spinning;
  }

  document.querySelectorAll('[data-rw-mode]').forEach(b => b.addEventListener('click', () => {
    mode = b.dataset.rwMode;
    document.querySelectorAll('[data-rw-mode]').forEach(x => x.setAttribute('aria-pressed', x === b));
    $('rw-ours').hidden = mode !== 'ours';
    $('rw-ownwrap').hidden = mode !== 'own';
    updatePool();
  }));
  ownBox.addEventListener('input', updatePool);

  function spin() {
    const p = pool();
    if (!p.length || spinning) return;
    spinning = true; spinBtn.disabled = true; result.hidden = true;
    let film = p[Math.floor(Math.random() * p.length)];
    if (p.length > 1 && last && film.t === last.t) film = p[(p.indexOf(film) + 1) % p.length];
    last = film;
    const idx = Math.floor(Math.random() * ORDER.length), num = ORDER[idx];
    const target = -(idx * SEG + SEG / 2);
    const cur = ((rot % 360) + 360) % 360;
    let delta = ((target - cur) % 360 + 360) % 360;
    rot += 360 * 5 + delta;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const dur = reduce ? 0 : 5200;
    wheel.style.transition = `transform ${dur}ms cubic-bezier(.12,.7,.18,1)`;
    wheel.style.transform = `rotate(${rot}deg)`;
    ballRing.style.transition = 'none';
    ballRing.style.transform = 'rotate(0deg)';
    void ballRing.offsetWidth;
    ballRing.style.transition = `transform ${dur}ms cubic-bezier(.2,.6,.15,1)`;
    ballRing.style.transform = `rotate(${-360 * 8}deg)`;
    ballRing.classList.add('rolling');
    setTimeout(() => {
      ballRing.classList.remove('rolling');
      const c = colorOf(num);
      $('rw-pocket').textContent = `${num} ${c}`;
      $('rw-pocket').dataset.c = c;
      $('rw-film').textContent = film.t;
      $('rw-meta').textContent = film.y ? `${film.y} · ${film.g.join(' · ')}` : 'From your list';
      result.hidden = false;
      spinning = false; updatePool();
    }, dur + 120);
  }
  spinBtn.addEventListener('click', spin);
  $('rw-again').addEventListener('click', spin);
  $('rw-share').addEventListener('click', async () => {
    const t = `The wheel landed on ${$('rw-pocket').textContent}. Tonight we're watching ${$('rw-film').textContent}. Spin yours: ${location.origin}${location.pathname}`;
    try { if (navigator.share) await navigator.share({ text: t }); else { await navigator.clipboard.writeText(t); $('rw-share').textContent = 'Copied'; setTimeout(() => $('rw-share').textContent = 'Share result', 1600); } } catch (e) {}
  });
  renderChips();
})();
