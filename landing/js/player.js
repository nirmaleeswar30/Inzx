/* ==========================================================================
   Inzx — Landing page interactions
   · word-level karaoke demo (mirrors the app's TTML engine)
   · demo player with live spectrum visualizer
   · dynamic accent theming (mirrors AlbumColorExtractor)
   · screenshot showcase, reveal-on-scroll, counters, nav, copy
   ========================================================================== */
(function () {
  'use strict';

  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var REPO = 'nirmaleeswar30/Inzx';
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ----------------------------------------------------------------------
     Demo tracks — each carries its own accent, like real album-art colors
     ---------------------------------------------------------------------- */
  var TRACKS = [
    {
      title: 'Starboy',
      artist: 'The Weeknd, Daft Punk',
      glyph: 'ST',
      src: 'JIOSAAVN · 320',
      duration: 273,
      accent: '#ff2233',
      lines: [
        {
          prev: "I'm tryna put you in the worst mood, ah",
          words: [['P1', 380], ['cleaner', 420], ['than', 240], ['your', 240], ['church', 420], ['shoes,', 520], ['ah', 420]],
          tr: 'Plus propre que tes chaussures du dimanche, ah'
        },
        {
          prev: 'P1 cleaner than your church shoes, ah',
          words: [['Milli', 420], ['point', 300], ['two', 340], ['just', 280], ['to', 200], ['hurt', 380], ['you,', 460], ['ah', 400]],
          tr: 'Un million deux, juste pour te blesser, ah'
        }
      ]
    },
    {
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      glyph: 'BL',
      src: 'YT MUSIC · OPUS',
      duration: 200,
      accent: '#e11d48',
      lines: [
        {
          prev: "I said, ooh, I'm blinded by the lights",
          words: [['No,', 380], ['I', 260], ["can't", 400], ['sleep', 460], ['until', 380], ['I', 240], ['feel', 400], ['your', 260], ['touch', 560]],
          tr: 'No, no puedo dormir hasta sentir tu tacto'
        },
        {
          prev: "No, I can't sleep until I feel your touch",
          words: [['I', 260], ['said,', 380], ['ooh,', 440], ["I'm", 280], ['drowning', 520], ['in', 240], ['the', 220], ['night', 540]],
          tr: 'Dije, ooh, me estoy ahogando en la noche'
        }
      ]
    },
    {
      title: 'Kesariya',
      artist: 'Arijit Singh, Pritam',
      glyph: 'KE',
      src: 'JIOSAAVN · 320',
      duration: 268,
      accent: '#f97316',
      lines: [
        {
          prev: 'Kesariya tera ishq hai piya',
          words: [['Rang', 420], ['jaaun', 460], ['jo', 280], ['main', 400], ['haath', 420], ['lagaaun', 620]],
          tr: 'Transliteration · रंग जाऊँ जो मैं हाथ लगाऊँ'
        },
        {
          prev: 'Rang jaaun jo main haath lagaaun',
          words: [['Mera', 380], ['piya', 420], ['ghar', 340], ['aaya', 480], ['o', 260], ['rama', 560]],
          tr: 'My beloved has come home, oh Rama'
        }
      ]
    },
    {
      title: 'Die For You',
      artist: 'The Weeknd',
      glyph: 'DF',
      src: 'YT MUSIC · OPUS',
      duration: 260,
      accent: '#8b5cf6',
      lines: [
        {
          prev: "I'm findin' ways to articulate the feeling I'm goin' through",
          words: [['I', 260], ['just', 320], ["don't", 380], ['wanna', 400], ['hurt', 420], ['you', 480]],
          tr: 'Ich will dich einfach nicht verletzen'
        },
        {
          prev: "I just don't wanna hurt you",
          words: [['But', 320], ['I', 240], ['think', 400], ["I'd", 300], ['die', 480], ['for', 300], ['you', 560]],
          tr: 'Aber ich glaube, ich würde für dich sterben'
        }
      ]
    }
  ];

  /* ----------------------------------------------------------------------
     Accent theming — mirrors the app's 0 ms palette extraction
     ---------------------------------------------------------------------- */
  var PALETTE = [
    { name: 'Inzx Red', hex: '#ff2233' },
    { name: 'Crimson', hex: '#e11d48' },
    { name: 'Ember', hex: '#f97316' },
    { name: 'Amber', hex: '#f59e0b' },
    { name: 'Mint', hex: '#22c55e' },
    { name: 'Cyan', hex: '#06b6d4' },
    { name: 'Indigo', hex: '#6366f1' },
    { name: 'Violet', hex: '#8b5cf6' },
    { name: 'Magenta', hex: '#d946ef' },
    { name: 'Slate', hex: '#94a3b8' }
  ];

  function hexToRgb(hex) {
    var h = hex.replace('#', '');
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }
  function mix(rgb, target, amt) {
    return rgb.map(function (c, i) { return Math.round(c + (target[i] - c) * amt); });
  }
  function toHex(rgb) {
    return '#' + rgb.map(function (c) { return ('0' + Math.max(0, Math.min(255, c)).toString(16)).slice(-2); }).join('');
  }

  var currentAccent = PALETTE[0].hex;

  function applyAccent(hex) {
    currentAccent = hex;
    var rgb = hexToRgb(hex);
    var root = document.documentElement.style;
    root.setProperty('--accent', hex);
    root.setProperty('--accent-rgb', rgb.join(', '));
    root.setProperty('--accent-soft', toHex(mix(rgb, [255, 255, 255], 0.28)));
    root.setProperty('--accent-deep', toHex(mix(rgb, [0, 0, 0], 0.42)));
    var meta = $('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', hex);
  }

  function buildSwatches() {
    var box = $('#swatches');
    if (!box) return;
    PALETTE.forEach(function (c, i) {
      var b = document.createElement('button');
      b.className = 'sw' + (i === 0 ? ' on' : '');
      b.style.background = 'linear-gradient(140deg, ' + toHex(mix(hexToRgb(c.hex), [255, 255, 255], 0.3)) + ', ' + c.hex + ')';
      b.setAttribute('aria-label', 'Theme: ' + c.name);
      b.title = c.name;
      b.addEventListener('click', function () {
        $$('.sw').forEach(function (s) { s.classList.remove('on'); });
        b.classList.add('on');
        applyAccent(c.hex);
      });
      box.appendChild(b);
    });
  }

  /* ----------------------------------------------------------------------
     Karaoke engine — word-by-word highlight, per-word durations
     ---------------------------------------------------------------------- */
  var kara = {
    track: 0,
    line: 0,
    word: 0,
    timer: null,
    elPrev: $('#kara-prev'),
    elCur: $('#kara-cur'),
    elTr: $('#kara-tr')
  };

  function renderLine() {
    if (!kara.elCur) return;
    var line = TRACKS[kara.track].lines[kara.line];
    kara.elPrev.textContent = line.prev;
    kara.elCur.innerHTML = '';
    line.words.forEach(function (w) {
      var s = document.createElement('span');
      s.className = 'kara-w';
      s.textContent = w[0];
      kara.elCur.appendChild(s);
    });
    kara.elTr.textContent = line.tr;
    kara.word = 0;
  }

  function stepWord() {
    var line = TRACKS[kara.track].lines[kara.line];
    var spans = $$('.kara-w', kara.elCur);

    if (kara.word >= line.words.length) {
      kara.timer = setTimeout(function () {
        kara.line = (kara.line + 1) % TRACKS[kara.track].lines.length;
        renderLine();
        stepWord();
      }, 900);
      return;
    }

    spans.forEach(function (s, i) {
      s.classList.toggle('on', i === kara.word);
      s.classList.toggle('done', i < kara.word);
    });

    var dur = line.words[kara.word][1];
    kara.word++;
    kara.timer = setTimeout(stepWord, dur);
  }

  function startKaraoke() {
    if (!kara.elCur) return;
    clearTimeout(kara.timer);
    renderLine();
    if (reduced) {
      $$('.kara-w', kara.elCur).forEach(function (s) { s.classList.add('done'); });
      return;
    }
    if (kara.visible) stepWord();
  }

  // only animate lyrics while the tile is actually on screen
  function watchKaraoke() {
    if (!kara.elCur || reduced) { kara.visible = true; return; }
    if (!('IntersectionObserver' in window)) { kara.visible = true; stepWord(); return; }
    new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        kara.visible = en.isIntersecting;
        clearTimeout(kara.timer);
        if (kara.visible) stepWord();
      });
    }, { threshold: 0.05 }).observe($('#karaoke'));
  }

  /* ----------------------------------------------------------------------
     Demo player — seek bar + canvas spectrum
     ---------------------------------------------------------------------- */
  var player = {
    i: 0,
    t: 0,
    playing: false,
    raf: null,
    last: 0
  };

  function fmt(s) {
    s = Math.max(0, Math.floor(s));
    return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2);
  }

  function loadTrack(i, keepPlaying) {
    player.i = ((i % TRACKS.length) + TRACKS.length) % TRACKS.length;
    var tr = TRACKS[player.i];
    player.t = 0;

    var set = function (sel, val) { var e = $(sel); if (e) e.textContent = val; };
    set('#pl-title', tr.title);
    set('#pl-artist', tr.artist);
    set('#pl-src', tr.src);
    set('#art-glyph', tr.glyph);
    set('#t-dur', fmt(tr.duration));
    set('#t-cur', '0:00');
    var fill = $('#seek-fill');
    if (fill) fill.style.width = '0%';

    // album art colors drive the whole theme — exactly like the app
    applyAccent(tr.accent);
    $$('.sw').forEach(function (s) { s.classList.remove('on'); });
    var idx = PALETTE.findIndex(function (p) { return p.hex === tr.accent; });
    if (idx > -1) { var sw = $$('.sw')[idx]; if (sw) sw.classList.add('on'); }

    kara.track = player.i;
    kara.line = 0;
    startKaraoke();

    if (keepPlaying && player.playing) { /* keep rolling */ }
  }

  function setPlayIcon() {
    var use = $('#play-icon use');
    if (use) use.setAttribute('href', player.playing ? '#i-pause' : '#i-play');
  }

  function tick(ts) {
    if (!player.playing) return;
    if (!player.last) player.last = ts;
    var dt = (ts - player.last) / 1000;
    player.last = ts;

    player.t += dt;
    var dur = TRACKS[player.i].duration;
    if (player.t >= dur) { loadTrack(player.i + 1, true); player.t = 0; }

    var pct = (player.t / dur) * 100;
    var fill = $('#seek-fill');
    if (fill) fill.style.width = pct + '%';
    var cur = $('#t-cur');
    if (cur) cur.textContent = fmt(player.t);

    player.raf = requestAnimationFrame(tick);
  }

  function togglePlay(force) {
    player.playing = typeof force === 'boolean' ? force : !player.playing;
    setPlayIcon();
    var art = $('#art');
    if (player.playing) {
      player.last = 0;
      player.raf = requestAnimationFrame(tick);
      if (art) art.style.boxShadow = '0 18px 44px -10px var(--glow)';
    } else {
      cancelAnimationFrame(player.raf);
      if (art) art.style.boxShadow = '';
    }
    if (player.kickViz) player.kickViz();
  }

  // stop the demo entirely once it scrolls out of view
  function watchPlayer() {
    var tile = $('.f-player');
    if (!tile || !('IntersectionObserver' in window)) return;
    new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          if (player.offscreenPaused) { player.offscreenPaused = false; togglePlay(true); }
        } else if (player.playing) {
          player.offscreenPaused = true;
          togglePlay(false);
        }
      });
    }, { threshold: 0.02 }).observe(tile);
  }

  /* --- canvas spectrum ------------------------------------------------- */
  function initViz() {
    var cv = $('#viz');
    if (!cv) return;
    var ctx = cv.getContext('2d');
    var BARS = 52;
    var vals = new Array(BARS).fill(0);
    var seeds = vals.map(function () { return Math.random() * Math.PI * 2; });

    function resize() {
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var w = cv.clientWidth || 300;
      var h = cv.clientHeight || 56;
      cv.width = w * dpr;
      cv.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener('resize', resize);

    var accentCache = { hex: '', rgb: [255, 34, 51] };
    var visible = false, running = false, settling = false;

    function draw(ts) {
      var w = cv.clientWidth, h = cv.clientHeight;
      ctx.clearRect(0, 0, w, h);

      if (accentCache.hex !== currentAccent) {
        accentCache.hex = currentAccent;
        accentCache.rgb = hexToRgb(currentAccent);
      }
      var c = accentCache.rgb;

      var gap = 3;
      var bw = (w - gap * (BARS - 1)) / BARS;
      var t = ts / 1000;
      settling = false;

      for (var i = 0; i < BARS; i++) {
        var mid = 1 - Math.abs(i - BARS / 2) / (BARS / 2);
        var target;
        if (player.playing) {
          target = (Math.sin(t * 3.1 + seeds[i]) * 0.5 + 0.5) *
                   (Math.sin(t * 1.3 + i * 0.35) * 0.3 + 0.7) *
                   (0.35 + mid * 0.65);
          target = Math.max(0.06, target);
        } else {
          target = 0.06 + mid * 0.05;
        }
        if (Math.abs(target - vals[i]) > 0.004) settling = true;
        vals[i] += (target - vals[i]) * 0.18;

        var bh = Math.max(2, vals[i] * h);
        var x = i * (bw + gap);
        var y = (h - bh) / 2;
        var a = 0.28 + vals[i] * 0.72;

        var g = ctx.createLinearGradient(0, y, 0, y + bh);
        g.addColorStop(0, 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')');
        g.addColorStop(1, 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + (a * 0.32) + ')');
        ctx.fillStyle = g;

        var r = Math.min(bw / 2, 2);
        ctx.beginPath();
        if (ctx.roundRect) { ctx.roundRect(x, y, bw, bh, r); }
        else { ctx.rect(x, y, bw, bh); }
        ctx.fill();
      }

      // idle out once the bars have settled and nothing is playing —
      // keeps the main thread free instead of burning a frame forever
      if (visible && (player.playing || settling)) {
        requestAnimationFrame(draw);
      } else {
        running = false;
      }
    }

    function kick() {
      if (running || !visible || reduced) return;
      running = true;
      requestAnimationFrame(draw);
    }
    player.kickViz = kick;

    if (reduced) {
      vals = vals.map(function (_, i) { return 0.08 + (1 - Math.abs(i - BARS / 2) / (BARS / 2)) * 0.05; });
      requestAnimationFrame(draw);
      return;
    }

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (en) { visible = en.isIntersecting; kick(); });
      }, { threshold: 0.02 }).observe(cv);
    } else {
      visible = true;
      kick();
    }
  }

  function initPlayerControls() {
    var play = $('#btn-play');
    if (!play) return;

    play.addEventListener('click', function () { togglePlay(); });
    $('#btn-next').addEventListener('click', function () { loadTrack(player.i + 1, true); });
    $('#btn-prev').addEventListener('click', function () { loadTrack(player.i - 1, true); });
    $('#btn-shuffle').addEventListener('click', function () {
      this.classList.toggle('act');
      loadTrack(Math.floor(Math.random() * TRACKS.length), true);
    });
    $('#btn-repeat').addEventListener('click', function () { this.classList.toggle('act'); });

    var track = $('#seek-track');
    track.addEventListener('click', function (e) {
      var r = track.getBoundingClientRect();
      var pct = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
      player.t = pct * TRACKS[player.i].duration;
      $('#seek-fill').style.width = pct * 100 + '%';
      $('#t-cur').textContent = fmt(player.t);
    });

    loadTrack(0);
    if (!reduced) togglePlay(true);
    else setPlayIcon();
  }

  /* ----------------------------------------------------------------------
     Screenshot showcase
     ---------------------------------------------------------------------- */
  var SCREENS = [
    {
      id: 'home', tab: 'Home', img: 'assets/shots/home.jpg',
      title: 'A home that knows you',
      desc: 'Quick picks, recently played, new releases and mood mixes pulled live from YouTube Music — all tinted by the art you are listening to.',
      list: ['Dynamic album-color theming across every surface', 'Skeletonizer shimmer while sections load', 'Locale-aware catalog with region control']
    },
    {
      id: 'nowplaying', tab: 'Now Playing', img: 'assets/shots/nowplaying.jpg',
      title: 'Four ways to watch a song play',
      desc: 'Default, Cinematic, Ripple and OG — each with its own motion language, animated Canvas album art and ambient glow reflections.',
      list: ['Linear, waveform or spectrum progress bars', 'Animated album art with reflection backgrounds', 'Like, share and start a Jam without leaving the screen']
    },
    {
      id: 'lyrics', tab: 'Lyrics', img: 'assets/shots/lyrics.jpg',
      title: 'Karaoke, down to the syllable',
      desc: 'BetterLyrics TTML drives word-level highlighting, with 15+ providers behind it and AI translation running inline as the song plays.',
      list: ['Word and line offset tuning per track', 'Instrumental gaps and background vocal lines', 'Translate or transliterate with your own API key']
    },
    {
      id: 'library', tab: 'Library', img: 'assets/shots/library.jpg',
      title: 'Everything in one place',
      desc: 'Your YouTube Music playlists, likes, albums and artists sync down and sit beside your local files and downloads.',
      list: ['Custom playlists and offline downloads', 'Local files organized by folder', 'Podcast episodes browse and play']
    },
    {
      id: 'jam', tab: 'Jams', img: 'assets/shots/jam.jpg',
      title: 'Same song, same second',
      desc: 'Start a Jam and everyone hears the same beat at the same moment, with a queue the whole room can edit.',
      list: ['Supabase realtime sync with drift correction', 'Host and participant permissions', 'Collaborative drag-to-reorder queue']
    },
    {
      id: 'search', tab: 'Search', img: 'assets/shots/search.jpg',
      title: 'Find it before you finish typing',
      desc: 'Live suggestions, searchable history and filters for songs, videos, albums, artists, playlists and podcasts.',
      list: ['Instant suggestion pipeline', 'Per-type result filters', 'History you can clear at any time']
    },
    {
      id: 'playlist', tab: 'Playlists', img: 'assets/shots/playlist.jpg',
      title: 'Playlists that feel native',
      desc: 'Rich headers, shuffle, download-all and queue actions — on your own playlists and on anything you find in the catalog.',
      list: ['Download an entire playlist in the background', 'Add to queue, play next, share deep links', 'Sync state with YouTube Music']
    },
    {
      id: 'folders', tab: 'Folders', img: 'assets/shots/folders.jpg',
      title: 'Your local music, respected',
      desc: 'Browse on-device audio by folder, exactly the way you filed it, and play it through the same engine as everything else.',
      list: ['Folder tree browsing', 'Embedded and local lyrics support', 'Works fully offline']
    }
  ];

  function initShowcase() {
    var stage = $('#phone-screen'), tabs = $('#tabs'), panes = $('#panes');
    if (!stage || !tabs || !panes) return;

    SCREENS.forEach(function (s, i) {
      var img = document.createElement('img');
      img.src = s.img;
      img.alt = 'Inzx — ' + s.tab + ' screen';
      img.width = 520; img.height = 1145;
      if (i > 1) img.loading = 'lazy';
      if (i === 0) img.classList.add('on');
      stage.appendChild(img);

      var b = document.createElement('button');
      b.className = 'tab' + (i === 0 ? ' on' : '');
      b.textContent = s.tab;
      b.setAttribute('aria-controls', 'pane-' + s.id);
      tabs.appendChild(b);

      var pane = document.createElement('div');
      pane.className = 'pane' + (i === 0 ? ' on' : '');
      pane.id = 'pane-' + s.id;
      pane.innerHTML =
        '<h3 class="pane-title">' + s.title + '</h3>' +
        '<p class="pane-desc">' + s.desc + '</p>' +
        '<ul class="pane-list">' + s.list.map(function (l) {
          return '<li><svg><use href="#i-check"/></svg><span>' + l + '</span></li>';
        }).join('') + '</ul>';
      panes.appendChild(pane);

      b.addEventListener('click', function () {
        $$('.tab', tabs).forEach(function (x) { x.classList.remove('on'); });
        $$('img', stage).forEach(function (x) { x.classList.remove('on'); });
        $$('.pane', panes).forEach(function (x) { x.classList.remove('on'); });
        b.classList.add('on');
        img.classList.add('on');
        img.loading = 'eager';
        pane.classList.add('on');
      });
    });
  }

  /* ----------------------------------------------------------------------
     Lists: languages, roadmap, marquee
     ---------------------------------------------------------------------- */
  var LANGS = ['English', 'العربية', 'Deutsch', 'Español', 'Français', 'हिन्दी', 'Bahasa Indonesia',
    '日本語', 'ಕನ್ನಡ', '한국어', 'മലയാളം', 'Português', 'Português (BR)', 'Русский',
    'தமிழ்', 'తెలుగు', 'ไทย', 'Türkçe', 'Українська', '简体中文', '繁體中文'];

  var ROAD = [
    ['Word-level synced lyrics (BetterLyrics TTML engine)', 1],
    ['AI lyric translation & transliteration', 1],
    ['JioSaavn high-quality audio source', 1],
    ['Crossfade & gapless prefetching', 1],
    ['Android Auto', 1],
    ['Home-screen widgets', 1],
    ['Multiple Now Playing & progress-bar styles', 1],
    ['Over-the-air updates (Shorebird)', 1],
    ['Chromecast / cast to external speakers', 0],
    ['Desktop targets — Windows · macOS · Linux', 0]
  ];

  var MARQUEE = ['Word-level karaoke lyrics', 'AI translation', '320 kbps audio', 'Dynamic theming',
    'Real-time Jams', 'Android Auto', 'Home-screen widgets', 'Gapless playback', 'Crossfade',
    'Offline downloads', 'Podcasts', 'OTA updates', 'No tracking', 'MIT licensed'];

  function initLists() {
    var langs = $('#langs');
    if (langs) LANGS.forEach(function (l) {
      var s = document.createElement('span');
      s.className = 'lang';
      s.textContent = l;
      langs.appendChild(s);
    });

    var road = $('#road');
    if (road) ROAD.forEach(function (r) {
      var d = document.createElement('div');
      d.className = 'road-item ' + (r[1] ? 'done' : 'todo');
      d.innerHTML = '<span class="road-box">' + (r[1] ? '<svg><use href="#i-check"/></svg>' : '') + '</span><span>' + r[0] + '</span>';
      road.appendChild(d);
    });

    var track = $('#marquee-track');
    if (track) {
      var html = MARQUEE.map(function (m) {
        return '<span class="marquee-item"><svg><use href="#i-bolt"/></svg>' + m + '</span>';
      }).join('');
      track.innerHTML = html + html; // duplicated for seamless loop
    }
  }

  /* ----------------------------------------------------------------------
     Nav, reveal, counters, spotlight, copy, back-to-top, GitHub stats
     ---------------------------------------------------------------------- */
  function initNav() {
    var nav = $('#nav'), burger = $('#burger'), menu = $('#mobile-menu');

    var onScroll = function () {
      nav.classList.toggle('stuck', window.scrollY > 24);
      $('#to-top').classList.toggle('show', window.scrollY > 700);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();

    burger.addEventListener('click', function () {
      var open = menu.classList.toggle('open');
      burger.classList.toggle('open', open);
      burger.setAttribute('aria-expanded', String(open));
    });
    $$('a', menu).forEach(function (a) {
      a.addEventListener('click', function () {
        menu.classList.remove('open');
        burger.classList.remove('open');
        burger.setAttribute('aria-expanded', 'false');
      });
    });

    $('#to-top').addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
    });
  }

  function initReveal() {
    var items = $$('.rv');
    if (!('IntersectionObserver' in window) || reduced) {
      items.forEach(function (e) { e.classList.add('in'); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        en.target.classList.add('in');
        io.unobserve(en.target);
      });
    }, { rootMargin: '0px 0px -60px 0px', threshold: 0.08 });

    items.forEach(function (e, i) {
      e.style.transitionDelay = ((i % 4) * 70) + 'ms';
      io.observe(e);
    });
  }

  function initCounters() {
    var nums = $$('[data-count]');
    if (!nums.length) return;
    if (reduced || !('IntersectionObserver' in window)) {
      nums.forEach(function (n) { n.textContent = n.dataset.count + (n.dataset.suffix || ''); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        var el = en.target;
        io.unobserve(el);
        var target = parseFloat(el.dataset.count);
        var suffix = el.dataset.suffix || '';
        var start = performance.now();
        var dur = 1300;
        (function step(now) {
          var p = Math.min(1, (now - start) / dur);
          var eased = 1 - Math.pow(1 - p, 3);
          el.textContent = Math.round(target * eased) + suffix;
          if (p < 1) requestAnimationFrame(step);
        })(start);
      });
    }, { threshold: 0.4 });
    nums.forEach(function (n) { io.observe(n); });
  }

  function initSpotlight() {
    if (window.matchMedia('(hover: none)').matches) return;
    document.addEventListener('pointermove', function (e) {
      var tile = e.target.closest ? e.target.closest('.tile') : null;
      if (!tile) return;
      var r = tile.getBoundingClientRect();
      tile.style.setProperty('--mx', (e.clientX - r.left) + 'px');
      tile.style.setProperty('--my', (e.clientY - r.top) + 'px');
    }, { passive: true });
  }

  function initParallax() {
    if (reduced) return;
    var blobs = $$('.blob');
    var ticking = false;
    window.addEventListener('scroll', function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () {
        var y = window.scrollY;
        blobs.forEach(function (b) {
          b.style.transform = 'translate3d(0,' + (y * parseFloat(b.dataset.par || 0)) + 'px,0)';
        });
        ticking = false;
      });
    }, { passive: true });
  }

  function initCopy() {
    var btn = $('#copy-btn');
    if (!btn) return;
    btn.addEventListener('click', function () {
      var text = btn.dataset.copy;
      var done = function () {
        btn.textContent = 'COPIED';
        btn.classList.add('ok');
        setTimeout(function () { btn.textContent = 'COPY'; btn.classList.remove('ok'); }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, done);
      } else {
        var ta = document.createElement('textarea');
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); } catch (e) { /* noop */ }
        document.body.removeChild(ta);
        done();
      }
    });
  }

  function compact(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return String(n);
  }

  function initGitHub() {
    if (!window.fetch) return;

    fetch('https://api.github.com/repos/' + REPO)
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) {
        if (!d) return;
        var el = $('#star-count');
        if (el && typeof d.stargazers_count === 'number') el.textContent = compact(d.stargazers_count);
      })
      .catch(function () { /* offline — leave the placeholder */ });

    fetch('https://api.github.com/repos/' + REPO + '/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) {
        if (!d || !d.tag_name) return;
        var chip = $('#ver-chip');
        if (chip) chip.textContent = d.tag_name;
      })
      .catch(function () { /* offline — leave the placeholder */ });
  }

  /* ---------------------------------------------------------------------- */
  function init() {
    var y = $('#year');
    if (y) y.textContent = new Date().getFullYear();

    buildSwatches();
    initLists();
    initShowcase();
    initViz();
    initPlayerControls();
    watchKaraoke();
    watchPlayer();
    initNav();
    initReveal();
    initCounters();
    initSpotlight();
    initParallax();
    initCopy();
    initGitHub();

    // pause the demo player when the tab is hidden
    document.addEventListener('visibilitychange', function () {
      if (document.hidden && player.playing) {
        togglePlay(false);
        player.wasPlaying = true;
      } else if (!document.hidden && player.wasPlaying) {
        player.wasPlaying = false;
        togglePlay(true);
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
