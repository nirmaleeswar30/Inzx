/**
 * Inzx — landing page interactions
 *  · demo player (queue, scrub, dynamic glow)
 *  · word-level karaoke simulation with AI translation / transliteration toggles
 *  · screenshot showcase tabs
 *  · scroll reveal, nav state, marquees, copy buttons
 */
(function () {
  'use strict';

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

  /* ===================== Demo tracks ===================== */

  const tracks = [
    {
      title: 'Starboy',
      artist: 'The Weeknd, Daft Punk',
      duration: 230,
      art: 'linear-gradient(140deg, #ff2740 0%, #8f0418 55%, #2b0208 100%)',
      glow: 'rgba(236, 15, 46, 0.34)',
      lyrics: [
        { t: "I'm", d: 300 }, { t: 'try-', d: 320 }, { t: 'na', d: 240 },
        { t: 'put', d: 300 }, { t: 'you', d: 300 }, { t: 'in', d: 200 },
        { t: 'the', d: 200 }, { t: 'worst', d: 420 }, { t: 'mood,', d: 520 }, { t: 'ah', d: 420 }
      ],
      translation: 'Je veux te mettre dans la pire des humeurs, ah',
      roman: "aim tray-na put yoo in dha wurst mood, aa"
    },
    {
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      duration: 200,
      art: 'linear-gradient(140deg, #ff6070 0%, #c00d26 50%, #1a0206 100%)',
      glow: 'rgba(255, 96, 112, 0.3)',
      lyrics: [
        { t: 'I', d: 280 }, { t: 'said,', d: 300 }, { t: 'ooh,', d: 400 },
        { t: "I'm", d: 300 }, { t: 'blind-', d: 320 }, { t: 'ed', d: 220 },
        { t: 'by', d: 250 }, { t: 'the', d: 200 }, { t: 'lights', d: 620 }
      ],
      translation: 'Dije, oh, estoy cegado por las luces',
      roman: 'ai sed, ooh, aim blain-ded bai dha laits'
    },
    {
      title: 'Kesariya',
      artist: 'Arijit Singh',
      duration: 268,
      art: 'linear-gradient(140deg, #ff9068 0%, #d01030 50%, #23030a 100%)',
      glow: 'rgba(255, 144, 104, 0.28)',
      lyrics: [
        { t: 'Ke-', d: 320 }, { t: 'sar-', d: 300 }, { t: 'i-', d: 240 },
        { t: 'ya', d: 480 }, { t: 'tera', d: 380 }, { t: 'ishq', d: 420 },
        { t: 'hai', d: 300 }, { t: 'piya', d: 620 }
      ],
      translation: 'Saffron-coloured is your love, my beloved',
      roman: 'kesariya tera ishq hai piya'
    },
    {
      title: 'Sweet Child O’ Mine',
      artist: 'Guns N’ Roses',
      duration: 356,
      art: 'linear-gradient(140deg, #ffb199 0%, #a30f24 52%, #150104 100%)',
      glow: 'rgba(255, 177, 153, 0.24)',
      lyrics: [
        { t: "She's", d: 400 }, { t: 'got', d: 300 }, { t: 'a', d: 200 },
        { t: 'smile', d: 600 }, { t: 'that', d: 300 }, { t: 'it', d: 250 },
        { t: 'seems', d: 450 }, { t: 'to', d: 250 }, { t: 'me', d: 600 }
      ],
      translation: 'Ella tiene una sonrisa que me parece recordar',
      roman: 'sheez got a smail dhat it seemz tu mee'
    }
  ];

  const state = {
    idx: 0,
    time: 74,
    playing: true,
    syl: 0,
    trans: false,
    roman: false,
    shuffle: false,
    repeat: false
  };

  const fmt = (s) => {
    const m = Math.floor(s / 60);
    const r = Math.floor(s % 60);
    return m + ':' + (r < 10 ? '0' : '') + r;
  };

  const noteIcon =
    '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
    '<path d="M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z"/></svg>';

  /* ===================== Queue ===================== */

  function buildQueue() {
    const list = $('#queueList');
    if (!list) return;

    list.innerHTML = '';
    tracks.forEach((track, i) => {
      const row = document.createElement('div');
      row.className = 'queue-item' + (i === state.idx ? ' playing' : '');
      row.setAttribute('role', 'button');
      row.tabIndex = 0;
      row.innerHTML =
        '<span class="queue-thumb" style="background:' + track.art + '">' + noteIcon + '</span>' +
        '<span class="queue-meta">' +
          '<span class="queue-name">' + track.title + '</span>' +
          '<span class="queue-artist">' + track.artist + '</span>' +
        '</span>' +
        '<span class="queue-dur">' + fmt(track.duration) + '</span>';

      const select = () => {
        state.idx = i;
        state.time = 0;
        state.syl = 0;
        state.playing = true;
        render();
      };
      row.addEventListener('click', select);
      row.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(); }
      });
      list.appendChild(row);
    });
  }

  /* ===================== Player render ===================== */

  function render() {
    const track = tracks[state.idx];

    $('#pTitle').textContent = track.title;
    $('#pArtist').textContent = track.artist;
    $('#pDur').textContent = fmt(track.duration);
    $('#pArt').style.background = track.art;

    $$('.dyn-glow').forEach((el) => { el.style.background = track.glow; });
    $$('.queue-item').forEach((el, i) => el.classList.toggle('playing', i === state.idx));

    renderTime();
    renderPlayState();
    renderKaraoke();
  }

  function renderTime() {
    const track = tracks[state.idx];
    const pct = Math.min(100, (state.time / track.duration) * 100);
    $('#pNow').textContent = fmt(state.time);
    $('#scrubFill').style.width = pct + '%';
    $('#scrub').setAttribute('aria-valuenow', Math.round(pct));
  }

  function renderPlayState() {
    const play = $('.i-play');
    const pause = $('.i-pause');
    if (play && pause) {
      play.style.display = state.playing ? 'none' : 'block';
      pause.style.display = state.playing ? 'block' : 'none';
    }
    const eq = $('#eqMini');
    if (eq) eq.classList.toggle('paused', !state.playing);
    $$('.wave i').forEach((bar) => {
      bar.style.animationPlayState = state.playing ? 'running' : 'paused';
    });
  }

  function nextTrack() {
    state.idx = state.shuffle
      ? Math.floor(Math.random() * tracks.length)
      : (state.idx + 1) % tracks.length;
    state.time = 0;
    state.syl = 0;
    render();
  }

  function prevTrack() {
    if (state.time > 4) {
      state.time = 0;
    } else {
      state.idx = (state.idx - 1 + tracks.length) % tracks.length;
      state.time = 0;
    }
    state.syl = 0;
    render();
  }

  /* ===================== Karaoke ===================== */

  function renderKaraoke() {
    const track = tracks[state.idx];
    const line = $('#karaokeLine');
    const trans = $('#karaokeTrans');
    if (!line) return;

    line.innerHTML = '';
    track.lyrics.forEach((syl, i) => {
      const span = document.createElement('span');
      span.className = 'syl' + (i < state.syl ? ' active' : '') + (i === state.syl ? ' now' : '');
      span.textContent = syl.t;
      line.appendChild(span);
      line.appendChild(document.createTextNode(' '));
    });

    if (trans) {
      trans.textContent = state.roman ? track.roman : track.translation;
      trans.classList.toggle('show', state.trans || state.roman);
    }
  }

  function advanceKaraoke() {
    const track = tracks[state.idx];
    const spans = $$('#karaokeLine .syl');
    if (!spans.length) return;

    spans.forEach((span, i) => {
      span.classList.toggle('active', i < state.syl);
      span.classList.toggle('now', i === state.syl);
    });

    state.syl++;
    if (state.syl > track.lyrics.length) {
      state.syl = 0;
      spans.forEach((s) => s.classList.remove('active', 'now'));
    }
  }

  function karaokeTick() {
    if (!state.playing) { setTimeout(karaokeTick, 300); return; }
    const track = tracks[state.idx];
    const syl = track.lyrics[Math.min(state.syl, track.lyrics.length - 1)];
    advanceKaraoke();
    setTimeout(karaokeTick, syl ? syl.d : 400);
  }

  /* ===================== Showcase ===================== */

  const shots = {
    nowplaying: {
      src: 'screenshots/nowplaying.png',
      title: 'Now Playing — cinematic & ambient',
      desc: 'Zero-latency colour extraction paints ambient reflections that match the album artwork in real time.'
    },
    lyrics: {
      src: 'screenshots/output.gif',
      title: 'Word-level karaoke lyrics',
      desc: 'Synced to the syllable across 15+ providers, with live AI translation from OpenRouter, DeepL or Gemini.'
    },
    home: {
      src: 'screenshots/home.png',
      title: 'Home — quick picks & discovery',
      desc: 'The YouTube Music recommendation feed, mixed with your recents, trending charts and locale-aware catalogues.'
    },
    jam: {
      src: 'screenshots/jam.png',
      title: 'Jams — real-time sessions',
      desc: 'Listen in sync with friends over Supabase WebSockets, with a shared queue and automatic drift correction.'
    },
    library: {
      src: 'screenshots/library.png',
      title: 'Library, folders & offline',
      desc: 'YouTube playlists, likes and albums alongside your local files, all downloadable for offline listening.'
    },
    search: {
      src: 'screenshots/search.png',
      title: 'Search — fast and filtered',
      desc: 'Live suggestions, saved history and filters across songs, videos, albums, artists and playlists.'
    }
  };

  function initTabs() {
    const tabs = $$('#tabs .tab');
    const img = $('#shotImg');
    if (!tabs.length || !img) return;

    tabs.forEach((tab) => {
      tab.addEventListener('click', () => {
        tabs.forEach((t) => t.classList.remove('active'));
        tab.classList.add('active');

        const data = shots[tab.dataset.key];
        if (!data) return;

        img.style.opacity = '0';
        img.style.transform = 'scale(0.98)';
        setTimeout(() => {
          img.src = data.src;
          img.alt = data.title;
          $('#shotTitle').textContent = data.title;
          $('#shotDesc').textContent = data.desc;
          img.style.opacity = '1';
          img.style.transform = 'scale(1)';
        }, 180);
      });
    });
  }

  /* ===================== Decorative generators ===================== */

  function buildWave() {
    const wave = $('#wave');
    if (!wave) return;
    for (let i = 0; i < 34; i++) {
      const bar = document.createElement('i');
      bar.style.animationDelay = (i * 0.055) + 's';
      bar.style.animationDuration = (1 + Math.random() * 0.7).toFixed(2) + 's';
      wave.appendChild(bar);
    }
  }

  function buildSwatches() {
    const host = $('#swatches');
    if (!host) return;
    const colors = [
      '#ec0f2e', '#ff6070', '#ff9068', '#f5c451', '#54c98a',
      '#3ec5d8', '#5b8cff', '#b06bff', '#ff5fbf', '#8f0418'
    ];
    colors.forEach((c) => {
      const s = document.createElement('span');
      s.className = 'swatch';
      s.style.background = 'linear-gradient(140deg, ' + c + ', rgba(0,0,0,.65))';
      host.appendChild(s);
    });
  }

  function buildMarquees() {
    const features = [
      'Word-level synced lyrics', 'AI translation', '320 kbps audio', 'Gapless playback',
      'Crossfade', 'Dynamic theming', 'Android Auto', 'Home-screen widgets', 'Jams',
      'Offline downloads', 'Podcasts', 'Local files', 'OTA updates', 'No trackers'
    ];
    const langs = [
      'English', 'العربية', 'Deutsch', 'Español', 'Français', 'हिन्दी', 'Indonesia',
      '日本語', 'ಕನ್ನಡ', '한국어', 'മലയാളം', 'Português', 'Português (BR)', 'Русский',
      'தமிழ்', 'తెలుగు', 'ไทย', 'Türkçe', 'Українська', '简体中文', '繁體中文'
    ];

    const fill = (el, items) => {
      if (!el) return;
      const html = items.map((i) => '<span>' + i + '</span>').join('');
      el.innerHTML = html + html; // duplicated for a seamless loop
    };

    fill($('#marquee'), features);
    fill($('#langMarquee'), langs);
  }

  /* ===================== Page chrome ===================== */

  function initNav() {
    const nav = $('#nav');
    const toggle = $('#navToggle');
    const links = $('#navLinks');
    const toTop = $('#toTop');

    const onScroll = () => {
      const y = window.scrollY;
      nav.classList.toggle('scrolled', y > 24);
      toTop.classList.toggle('show', y > 900);

      let current = '';
      $$('section[id]').forEach((sec) => {
        if (y >= sec.offsetTop - 160) current = sec.id;
      });
      $$('#navLinks a[href^="#"]').forEach((a) => {
        a.classList.toggle('active', a.getAttribute('href') === '#' + current);
      });
    };

    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();

    toggle.addEventListener('click', () => {
      const open = links.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(open));
    });

    links.addEventListener('click', (e) => {
      if (e.target.tagName === 'A') {
        links.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });

    toTop.addEventListener('click', () => window.scrollTo({ top: 0, behavior: 'smooth' }));
  }

  function initReveal() {
    const items = $$('.reveal');
    if (!('IntersectionObserver' in window)) {
      items.forEach((el) => el.classList.add('in'));
      return;
    }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -60px' });

    items.forEach((el) => io.observe(el));
  }

  function initCopy() {
    $$('[data-copy]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        const target = $(btn.dataset.copy);
        if (!target) return;
        try {
          await navigator.clipboard.writeText(target.textContent.trim());
          const original = btn.innerHTML;
          btn.innerHTML =
            '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">' +
            '<polyline points="20 6 9 17 4 12"/></svg>';
          btn.style.color = '#ff6070';
          setTimeout(() => { btn.innerHTML = original; btn.style.color = ''; }, 1600);
        } catch (err) {
          /* clipboard unavailable — nothing to do */
        }
      });
    });
  }

  function initMisc() {
    const year = $('#year');
    if (year) year.textContent = new Date().getFullYear();

    $$('.heart-btn').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        btn.classList.toggle('liked');
        const icon = $('svg', btn);
        if (icon) {
          icon.style.transform = 'scale(1.4)';
          setTimeout(() => { icon.style.transform = 'scale(1)'; }, 240);
        }
      });
    });

    $$('#styleRow .style-pill').forEach((pill) => {
      pill.addEventListener('click', () => {
        $$('#styleRow .style-pill').forEach((p) => p.classList.remove('active'));
        pill.classList.add('active');
      });
    });
  }

  function initPlayerControls() {
    $('#btnPlay').addEventListener('click', () => {
      state.playing = !state.playing;
      renderPlayState();
    });
    $('#btnNext').addEventListener('click', nextTrack);
    $('#btnPrev').addEventListener('click', prevTrack);

    $('#btnShuffle').addEventListener('click', (e) => {
      state.shuffle = !state.shuffle;
      e.currentTarget.classList.toggle('on', state.shuffle);
    });
    $('#btnRepeat').addEventListener('click', (e) => {
      state.repeat = !state.repeat;
      e.currentTarget.classList.toggle('on', state.repeat);
    });

    const scrub = $('#scrub');
    const seek = (clientX) => {
      const rect = scrub.getBoundingClientRect();
      const pct = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
      state.time = Math.floor(pct * tracks[state.idx].duration);
      renderTime();
    };
    scrub.addEventListener('click', (e) => seek(e.clientX));
    scrub.addEventListener('keydown', (e) => {
      const step = 5;
      if (e.key === 'ArrowRight') {
        state.time = Math.min(tracks[state.idx].duration, state.time + step);
        renderTime();
      } else if (e.key === 'ArrowLeft') {
        state.time = Math.max(0, state.time - step);
        renderTime();
      }
    });

    const toggle = (btn, key) => {
      btn.addEventListener('click', () => {
        state[key] = !state[key];
        btn.classList.toggle('on', state[key]);
        btn.setAttribute('aria-pressed', String(state[key]));
        if (key === 'roman' && state.roman) { state.trans = false; $('#toggleTrans').classList.remove('on'); }
        if (key === 'trans' && state.trans) { state.roman = false; $('#toggleRoman').classList.remove('on'); }
        renderKaraoke();
      });
    };
    toggle($('#toggleTrans'), 'trans');
    toggle($('#toggleRoman'), 'roman');
  }

  function startClock() {
    setInterval(() => {
      if (!state.playing) return;
      state.time++;
      if (state.time > tracks[state.idx].duration) {
        if (state.repeat) { state.time = 0; state.syl = 0; render(); }
        else nextTrack();
      } else {
        renderTime();
      }
    }, 1000);
  }

  /* ===================== Boot ===================== */

  document.addEventListener('DOMContentLoaded', () => {
    buildQueue();
    buildWave();
    buildSwatches();
    buildMarquees();
    render();
    initPlayerControls();
    initTabs();
    initNav();
    initReveal();
    initCopy();
    initMisc();
    startClock();
    karaokeTick();
  });
})();
