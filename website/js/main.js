/* ═══════════════════════════════════════════════════════
   INZX — landing page interactions
   ═══════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var $  = function (s, c) { return (c || document).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); };
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ───────── year ───────── */
  var yearEl = $('#year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* ───────── scroll progress ───────── */
  var bar = $('#progressBar');
  var ticking = false;

  function onScroll() {
    var y = window.scrollY || document.documentElement.scrollTop;
    var h = document.documentElement.scrollHeight - window.innerHeight;
    if (bar) bar.style.width = (h > 0 ? (y / h) * 100 : 0) + '%';
    ticking = false;
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  onScroll();

  /* ───────── active nav link ───────── */
  var navLinks = $$('.nav-links a');
  var sections = navLinks
    .map(function (a) { return document.getElementById(a.getAttribute('href').slice(1)); })
    .filter(Boolean);

  if (sections.length && 'IntersectionObserver' in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        navLinks.forEach(function (a) {
          a.classList.toggle('current', a.getAttribute('href') === '#' + e.target.id);
        });
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    sections.forEach(function (s) { spy.observe(s); });
  }

  /* ───────── mobile menu ───────── */
  var burger = $('#burger');
  var menu = $('#mobileMenu');
  if (burger && menu) {
    var setMenu = function (open) {
      menu.hidden = !open;
      burger.classList.toggle('open', open);
      burger.setAttribute('aria-expanded', String(open));
      burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
      document.body.style.overflow = open ? 'hidden' : '';
    };
    burger.addEventListener('click', function () { setMenu(menu.hidden); });
    menu.addEventListener('click', function (e) { if (e.target.tagName === 'A') setMenu(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !menu.hidden) setMenu(false); });
    window.addEventListener('resize', function () { if (window.innerWidth > 860 && !menu.hidden) setMenu(false); });
  }

  /* ───────── reveal on scroll ───────── */
  var revealables = $$('.reveal');
  revealables.forEach(function (el) {
    var d = el.getAttribute('data-delay');
    if (d) el.style.setProperty('--d', d);
  });

  if ('IntersectionObserver' in window) {
    var revealer = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('in');
        obs.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    revealables.forEach(function (el) { revealer.observe(el); });
  } else {
    revealables.forEach(function (el) { el.classList.add('in'); });
  }

  /* ───────── stat counters ───────── */
  var counters = $$('[data-count]');
  if (counters.length && 'IntersectionObserver' in window && !reduced) {
    var counterObs = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        obs.unobserve(e.target);
        var el = e.target;
        var target = parseInt(el.getAttribute('data-count'), 10);
        var suffix = el.getAttribute('data-suffix') || '';
        var start = performance.now();
        var dur = 1300;
        (function step(now) {
          var p = Math.min((now - start) / dur, 1);
          var eased = 1 - Math.pow(1 - p, 3);
          el.textContent = Math.round(target * eased) + suffix;
          if (p < 1) requestAnimationFrame(step);
        })(start);
      });
    }, { threshold: 0.5 });
    counters.forEach(function (c) { counterObs.observe(c); });
  }

  /* ───────── card spotlight ───────── */
  var spots = $$('.spot');
  if (spots.length && window.matchMedia('(hover: hover)').matches) {
    spots.forEach(function (card) {
      card.addEventListener('pointermove', function (e) {
        var r = card.getBoundingClientRect();
        card.style.setProperty('--mx', (e.clientX - r.left) + 'px');
        card.style.setProperty('--my', (e.clientY - r.top) + 'px');
      });
    });
  }

  /* ───────── cursor glow ───────── */
  var glow = $('#cursorGlow');
  if (glow && window.matchMedia('(hover: hover) and (pointer: fine)').matches && !reduced) {
    var gx = 0, gy = 0, cx = 0, cy = 0, glowOn = false, glowRaf = null;

    // The loop parks itself once the glow has caught up with the pointer, so an
    // idle page costs nothing instead of compositing a 520px blur every frame.
    var glowLoop = function () {
      var dx = gx - cx, dy = gy - cy;
      cx += dx * 0.12;
      cy += dy * 0.12;
      glow.style.transform = 'translate(' + cx + 'px,' + cy + 'px) translate(-50%,-50%)';
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        glowRaf = requestAnimationFrame(glowLoop);
      } else {
        glowRaf = null;
      }
    };

    document.addEventListener('pointermove', function (e) {
      gx = e.clientX; gy = e.clientY;
      if (!glowOn) { glowOn = true; glow.style.opacity = '1'; cx = gx; cy = gy; }
      if (!glowRaf) glowRaf = requestAnimationFrame(glowLoop);
    }, { passive: true });
  }

  /* ───────── hero parallax ───────── */
  var backdrop = $('#heroBackdrop');
  if (backdrop && !reduced && window.matchMedia('(min-width: 1081px)').matches) {
    var pTick = false;
    window.addEventListener('scroll', function () {
      if (pTick) return;
      pTick = true;
      requestAnimationFrame(function () {
        var y = window.scrollY;
        if (y < window.innerHeight * 1.2) {
          backdrop.style.transform = 'translateY(calc(-50% + ' + (y * 0.13) + 'px)) scale(' + (1 + y * 0.00008) + ')';
        }
        pTick = false;
      });
    }, { passive: true });
  }

  /* ───────── hero phone tilt ───────── */
  var tilt = $('.tilt');
  if (tilt && !reduced && window.matchMedia('(hover: hover)').matches) {
    var host = tilt.parentElement;
    host.addEventListener('pointermove', function (e) {
      var r = host.getBoundingClientRect();
      var px = (e.clientX - r.left) / r.width - 0.5;
      var py = (e.clientY - r.top) / r.height - 0.5;
      tilt.style.transform =
        'rotateY(' + (-13 + px * 12) + 'deg) rotateX(' + (4 - py * 10) + 'deg) rotateZ(1.5deg)';
    });
    host.addEventListener('pointerleave', function () {
      tilt.style.transform = 'rotateY(-13deg) rotateX(4deg) rotateZ(1.5deg)';
    });
  }

  /* ───────── karaoke lyrics demo (Starboy BetterLyrics engine logic) ───────── */
  var kdemo = $('#kdemo');
  if (kdemo) {
    var LINES = [
      ["I'm ", "tryna ", "put ", "you ", "in ", "the ", "worst ", "mood, ", "ah"],
      ["P1 ", "cleaner ", "than ", "your ", "church ", "shoes, ", "ah"],
      ["Milli ", "point ", "two ", "just ", "to ", "hurt ", "you, ", "ah"],
      ["All ", "red ", "Lamb' ", "just ", "to ", "tease ", "you, ", "ah"],
      ["None ", "of ", "these ", "toys ", "on ", "lease ", "too, ", "ah"],
      ["Made ", "your ", "whole ", "year ", "in ", "a ", "week ", "too, ", "yeah"],
      ["Main ", "bitch ", "out ", "of ", "your ", "league ", "too, ", "ah"],
      ["Side ", "bitch ", "out ", "of ", "your ", "league ", "too, ", "ah"],
      ["Look ", "what ", "you've ", "done"],
      ["I'm ", "a ", "motherfuckin' ", "starboy"],
      ["Look ", "what ", "you've ", "done"],
      ["I'm ", "a ", "motherfuckin' ", "starboy"]
    ];

    var lineEls = LINES.map(function (words) {
      var line = document.createElement('div');
      line.className = 'kline';
      words.forEach(function (w) {
        var span = document.createElement('span');
        span.className = 'kword';
        span.textContent = w;
        span.setAttribute('data-w', w);
        line.appendChild(span);
      });
      kdemo.appendChild(line);
      return line;
    });

    var rafId = null;
    var lineTimeout = null;
    var running = false;

    // Exact word & syllable durations (in ms) from official synced lyrics provider
    var STARBOY_DURS = [
      // Line 0: "I'm tryna put you in the worst mood, ah"
      // I'm: 151, tryna: 316, put: 133, you: 201, in: 151, the: 165, worst: 316, mood,: 369, ah: 282
      [151, 316, 133, 201, 151, 165, 316, 369, 282],

      // Line 1: "P1 cleaner than your church shoes, ah"
      // P: 362, 1: 306 -> P1: 668, cleaner: 316, than: 168, your: 134, church: 334, shoes,: 348, ah: 381
      [668, 316, 168, 134, 334, 348, 381],

      // Line 2: "Milli point two just to hurt you, ah"
      // Milli: 331, point: 320, two: 299, just: 151, to: 133, hurt: 366, you,: 334, ah: 351
      [331, 320, 299, 151, 133, 366, 334, 351],

      // Line 3: "All red Lamb' just to tease you, ah"
      // All: 316, red: 351, Lamb': 317, just: 165, to: 134, tease: 351, you,: 316, ah: 383
      [316, 351, 317, 165, 134, 351, 316, 383],

      // Line 4: "None of these toys on lease too, ah"
      // None: 151, of: 148, these: 317, toys: 319, on: 331, lease: 334, too,: 351, ah: 432
      [151, 148, 317, 319, 331, 334, 351, 432],

      // Line 5: "Made your whole year in a week too, yeah"
      // Made: 151, your: 148, whole: 351, year: 351, in: 148, a: 151, week: 334, too,: 334, yeah: 453
      [151, 148, 351, 351, 148, 151, 334, 334, 453],

      // Line 6: "Main bitch out of your league too, ah"
      // Main: 317, bitch: 366, out: 150, of: 148, your: 337, league: 299, too,: 334, ah: 383
      [317, 366, 150, 148, 337, 299, 334, 383],

      // Line 7: "Side bitch out of your league too, ah"
      // Side: 319, bitch: 334, out: 148, of: 151, your: 299, league: 302, too,: 351, ah: 348
      [319, 334, 148, 151, 299, 302, 351, 348],

      // Line 8: "Look what you've done"
      // Look: 214, what: 118, you've: 160, done: 520
      [214, 118, 160, 520],

      // Line 9: "I'm a motherfuckin' starboy"
      // I'm: 107, a: 135, mother: 360, fuckin': 292 -> motherfuckin': 652, star: 346, boy: 335 -> starboy: 681
      [107, 135, 652, 681],

      // Line 10: "Look what you've done"
      // Look: 204, what: 135, you've: 202, done: 486
      [204, 135, 202, 486],

      // Line 11: "I'm a motherfuckin' starboy"
      // I'm: 121, a: 160, motherfuckin': 680, starboy: 706
      [121, 160, 680, 706]
    ];

    function wordDur(lineIdx, wordIdx, text) {
      if (STARBOY_DURS[lineIdx] && STARBOY_DURS[lineIdx][wordIdx] !== undefined) {
        return STARBOY_DURS[lineIdx][wordIdx];
      }
      return 180 + text.trim().length * 55;
    }

    function resetWord(w) {
      w.classList.remove('sung');
      w.style.removeProperty('--fill');
      w.style.removeProperty('--glow');
      w.style.transform = 'scale(1)';
    }

    function setWordState(w, fillProgress) {
      if (fillProgress >= 1) {
        w.classList.add('sung');
        w.style.setProperty('--fill', '1');
        w.style.setProperty('--glow', '0.25');
        w.style.transform = 'scale(1)';
        return;
      }
      w.classList.remove('sung');
      w.style.setProperty('--fill', fillProgress.toFixed(4));
      // BetterLyrics: glowIntensity = fillProgress * fillProgress
      var glowIntensity = fillProgress * fillProgress;
      w.style.setProperty('--glow', glowIntensity.toFixed(3));
      // BetterLyrics: scalePop = 1.0 + (0.04 * sin(fillProgress * pi))
      var scalePop = 1.0 + 0.05 * Math.sin(fillProgress * Math.PI);
      w.style.transform = 'scale(' + scalePop.toFixed(4) + ')';
    }

    function centerLine(index) {
      var parent = kdemo.parentElement;
      if (!parent || !lineEls[index]) return;
      var parentHeight = parent.clientHeight || 185;
      var activeEl = lineEls[index];
      // Calculate offset so active line is vertically centered
      var targetY = (parentHeight / 2) - (activeEl.offsetTop + activeEl.clientHeight / 2);
      kdemo.style.transform = 'translateY(' + targetY.toFixed(1) + 'px)';
    }

    function playLine(i) {
      if (!running) return;

      centerLine(i);

      lineEls.forEach(function (el, j) {
        el.classList.remove('past', 'active', 'upcoming');
        el.classList.add(j < i ? 'past' : j === i ? 'active' : 'upcoming');
        if (j !== i) {
          $$('.kword', el).forEach(function (w) {
            if (j < i) {
              w.classList.add('sung');
              w.style.setProperty('--fill', '1');
              w.style.setProperty('--glow', '0');
              w.style.transform = 'scale(1)';
            } else {
              resetWord(w);
            }
          });
        }
      });

      var words = $$('.kword', lineEls[i]);
      words.forEach(resetWord);

      // Build word timing schedule
      var timeline = [];
      var cursor = 0;
      words.forEach(function (w, wordIdx) {
        var d = wordDur(i, wordIdx, w.textContent);
        timeline.push({ el: w, start: cursor, end: cursor + d, dur: d });
        cursor += d;
      });

      var totalLineDur = cursor;
      var startTime = performance.now();

      function tick(now) {
        if (!running) return;
        var elapsed = now - startTime;

        timeline.forEach(function (item) {
          if (elapsed < item.start) {
            resetWord(item.el);
          } else if (elapsed >= item.end) {
            setWordState(item.el, 1);
          } else {
            // raw clamp(0.0, 1.0)
            var raw = Math.min(Math.max((elapsed - item.start) / item.dur, 0), 1);
            // BetterLyrics smooth Hermite cubic interpolation: raw * raw * (3.0 - 2.0 * raw)
            var fillProgress = raw * raw * (3.0 - 2.0 * raw);
            setWordState(item.el, fillProgress);
          }
        });

        if (elapsed < totalLineDur) {
          rafId = requestAnimationFrame(tick);
        } else {
          // Line complete, pause briefly then move up to next line
          lineTimeout = setTimeout(function () {
            if (i + 1 < lineEls.length) {
              playLine(i + 1);
            } else {
              lineTimeout = setTimeout(function () {
                lineEls.forEach(function (el) {
                  el.classList.remove('past', 'active', 'upcoming');
                  $$('.kword', el).forEach(resetWord);
                });
                lineTimeout = setTimeout(function () { playLine(0); }, 400);
              }, 600);
            }
          }, 360);
        }
      }

      rafId = requestAnimationFrame(tick);
    }

    function start() {
      if (running) return;
      running = true;
      playLine(0);
    }

    function stop() {
      running = false;
      if (rafId) cancelAnimationFrame(rafId);
      if (lineTimeout) clearTimeout(lineTimeout);
    }

    if (reduced) {
      lineEls.forEach(function (el, j) {
        el.classList.add(j === 0 ? 'active' : 'upcoming');
        if (j === 0) $$('.kword', el).forEach(function (w) { w.classList.add('sung'); });
      });
      centerLine(0);
    } else if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { e.isIntersecting ? start() : stop(); });
      }, { threshold: 0.25 }).observe(kdemo);
    } else {
      start();
    }
  }

  /* ───────── waveform canvas ───────── */
  var canvas = $('#waveCanvas');
  if (canvas && !reduced) {
    var ctx = canvas.getContext('2d');
    var visible = false;
    var raf = null;
    var playedFill = null; // one cached gradient, not one per bar per frame

    function sizeCanvas() {
      var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      var r = canvas.getBoundingClientRect();
      if (!r.width) return;
      canvas.width = r.width * dpr;
      canvas.height = r.height * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      playedFill = ctx.createLinearGradient(0, 0, 0, r.height);
      playedFill.addColorStop(0, '#ff5a62');
      playedFill.addColorStop(1, '#9e0009');
    }

    function draw(now) {
      if (!visible) { raf = null; return; }
      var r = canvas.getBoundingClientRect();
      var W = r.width, H = r.height;
      ctx.clearRect(0, 0, W, H);

      var gap = 5;
      var bw = 6;
      var step = bw + gap;
      var n = Math.ceil(W / step);
      var t = now / 1000;
      var playhead = ((t * 0.09) % 1.25) - 0.1;
      var rounded = typeof ctx.roundRect === 'function';

      // Two passes so fillStyle is set twice per frame rather than once per bar.
      for (var pass = 0; pass < 2; pass++) {
        if (pass === 0) { ctx.fillStyle = '#ffffff'; ctx.globalAlpha = 0.11; }
        else { ctx.fillStyle = playedFill; ctx.globalAlpha = 1; }

        ctx.beginPath();
        for (var i = 0; i < n; i++) {
          var played = (i / n) < playhead;
          if (played !== (pass === 1)) continue;

          var a =
            Math.sin(i * 0.42 + t * 2.1) * 0.34 +
            Math.sin(i * 0.17 - t * 1.3) * 0.28 +
            Math.sin(i * 0.93 + t * 3.4) * 0.16;
          var amp = (Math.abs(a) + 0.12) * (0.55 + 0.45 * Math.sin(i * 0.08 + t * 0.5));
          var h = Math.max(3, Math.min(amp * H * 0.92, H * 0.92));
          var y = (H - h) / 2;

          if (rounded) ctx.roundRect(i * step, y, bw, h, bw / 2);
          else ctx.rect(i * step, y, bw, h);
        }
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      raf = requestAnimationFrame(draw);
    }

    var kick = function () { if (!raf && visible) raf = requestAnimationFrame(draw); };

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          visible = e.isIntersecting;
          if (visible) { sizeCanvas(); kick(); }
        });
      }, { threshold: 0.15 }).observe(canvas);
    } else {
      visible = true; sizeCanvas(); kick();
    }

    var rt;
    window.addEventListener('resize', function () {
      clearTimeout(rt);
      rt = setTimeout(sizeCanvas, 160);
    });
  }

  /* ───────── showcase sticky scroll controller ───────── */
  var showcasePin = $('#showcase') || $('.showcase-pin-wrap');
  var showcaseTrack = $('#showcaseTrack');
  var showcaseSlides = $$('.showcase-slide');
  var showcaseCur = $('#showcaseCur');
  var showcaseTag = $('#showcaseTag');
  var showcaseDots = $$('.showcase-dot');

  if (showcasePin && showcaseTrack && showcaseSlides.length) {
    var count = showcaseSlides.length;
    var currentIndex = -1;
    var targetProgress = 0;
    var currentProgress = 0;
    var isTicking = false;
    var isLerping = false;

    var slideData = showcaseSlides.map(function (el) {
      return {
        title: el.getAttribute('data-title') || 'Screen',
        index: parseInt(el.getAttribute('data-index') || '0', 10)
      };
    });

    function getSlideCenter(idx) {
      var slide = showcaseSlides[idx];
      if (!slide) return 0;
      return slide.offsetLeft + (slide.offsetWidth / 2);
    }

    function applyProgress(prog) {
      var p = Math.max(0, Math.min(1, prog));
      var maxIdx = count - 1;
      var continuousIndex = p * maxIdx;

      var baseIdx = Math.floor(continuousIndex);
      var nextIdx = Math.min(maxIdx, baseIdx + 1);
      var frac = continuousIndex - baseIdx;

      var stage = showcaseTrack.parentElement;
      var stageWidth = stage ? stage.clientWidth : window.innerWidth;
      var centerA = getSlideCenter(baseIdx);
      var centerB = getSlideCenter(nextIdx);
      var interpolatedCenter = centerA + (centerB - centerA) * frac;
      var translateX = (stageWidth / 2) - interpolatedCenter;

      showcaseTrack.style.transform = 'translate3d(' + translateX.toFixed(2) + 'px, 0, 0)';

      var activeIdx = Math.max(0, Math.min(maxIdx, Math.round(continuousIndex)));
      if (activeIdx !== currentIndex) {
        currentIndex = activeIdx;
        for (var i = 0; i < count; i++) {
          if (i === activeIdx) {
            showcaseSlides[i].classList.add('active');
            if (showcaseDots[i]) showcaseDots[i].classList.add('active');
          } else {
            showcaseSlides[i].classList.remove('active');
            if (showcaseDots[i]) showcaseDots[i].classList.remove('active');
          }
        }
        if (showcaseCur) {
          showcaseCur.textContent = (activeIdx + 1 < 10 ? '0' : '') + (activeIdx + 1);
        }
        if (showcaseTag && slideData[activeIdx]) {
          showcaseTag.textContent = slideData[activeIdx].title;
        }
      }
    }

    function lerpLoop() {
      var diff = targetProgress - currentProgress;
      if (Math.abs(diff) < 0.0006) {
        currentProgress = targetProgress;
        applyProgress(currentProgress);
        isLerping = false;
        return;
      }
      currentProgress += diff * 0.22;
      applyProgress(currentProgress);
      requestAnimationFrame(lerpLoop);
    }

    function updateFromScroll() {
      var rect = showcasePin.getBoundingClientRect();
      var totalScroll = showcasePin.offsetHeight - window.innerHeight;
      if (totalScroll <= 0) {
        targetProgress = 0;
      } else {
        var scrolled = -rect.top;
        targetProgress = Math.max(0, Math.min(1, scrolled / totalScroll));
      }

      if (reduced) {
        currentProgress = targetProgress;
        applyProgress(currentProgress);
        return;
      }

      if (!isLerping) {
        isLerping = true;
        requestAnimationFrame(lerpLoop);
      }
    }

    function scrollToSlide(idx) {
      var totalScroll = showcasePin.offsetHeight - window.innerHeight;
      var pinTopFromDoc = showcasePin.getBoundingClientRect().top + window.scrollY;
      var targetY = pinTopFromDoc + (idx / (count - 1)) * totalScroll;
      window.scrollTo({ top: targetY, behavior: 'smooth' });
    }

    showcaseDots.forEach(function (dot, i) {
      dot.addEventListener('click', function () {
        scrollToSlide(i);
      });
    });

    showcaseSlides.forEach(function (slide, i) {
      slide.addEventListener('click', function () {
        if (i !== currentIndex) {
          scrollToSlide(i);
        }
      });
    });

    window.addEventListener('scroll', function () {
      if (!isTicking) {
        requestAnimationFrame(function () {
          updateFromScroll();
          isTicking = false;
        });
        isTicking = true;
      }
    }, { passive: true });

    window.addEventListener('resize', function () {
      applyProgress(currentProgress);
    }, { passive: true });

    updateFromScroll();
    currentProgress = targetProgress;
    applyProgress(currentProgress);
  }

  /* ───────── tabs ───────── */
  var tabs = $$('.tab');
  if (tabs.length) {
    tabs.forEach(function (tab) {
      tab.addEventListener('click', function () {
        var id = tab.getAttribute('data-tab');
        tabs.forEach(function (t) {
          var on = t === tab;
          t.classList.toggle('active', on);
          t.setAttribute('aria-selected', String(on));
        });
        $$('.tab-panel').forEach(function (p) { p.classList.toggle('active', p.id === id); });
      });
    });
  }

  /* ───────── copy buttons ───────── */
  $$('.copy').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = btn.getAttribute('data-copy') || '';
      var done = function () {
        var old = btn.textContent;
        btn.textContent = 'Copied';
        btn.classList.add('done');
        setTimeout(function () { btn.textContent = old; btn.classList.remove('done'); }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {});
      } else {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); done(); } catch (_) {}
        document.body.removeChild(ta);
      }
    });
  });

  /* ───────── live repo & release info (public GitHub API) ───────── */
  (function repoInfo() {
    if (!window.fetch) return;

    var starEl = $('#ghStars');
    var supportStarEl = $('#supportGhStars');

    async function getStarCount(owner, repo) {
      // 1. Check cached count in localStorage
      var cached = localStorage.getItem('inzx_gh_stars');
      if (cached) {
        if (starEl) starEl.textContent = cached;
        if (supportStarEl) supportStarEl.textContent = cached;
      }

      // 2. Try primary GitHub API
      try {
        var res = await fetch('https://api.github.com/repos/' + owner + '/' + repo);
        if (res.ok) {
          var data = await res.json();
          if (typeof data.stargazers_count === 'number') {
            return data.stargazers_count;
          }
        }
      } catch (e) {}

      // 3. Fallback: Shields.io JSON endpoint (never hits GitHub client rate limit)
      try {
        var sRes = await fetch('https://img.shields.io/github/stars/' + owner + '/' + repo + '.json');
        if (sRes.ok) {
          var sData = await sRes.json();
          if (sData && sData.value) {
            // value is formatted like "120" or "1.2k"
            return sData.value;
          }
        }
      } catch (e) {}

      return cached || null;
    }

    function formatCount(num) {
      if (typeof num === 'string') {
        var parsed = parseFloat(num.replace(/,/g, ''));
        if (!isNaN(parsed) && !/[a-zA-Z]/.test(num)) num = parsed;
        else return num;
      }
      if (typeof num === 'number') {
        if (num >= 1000) {
          var k = (num / 1000).toFixed(1).replace(/\.0$/, '');
          return k + 'k';
        }
        return String(num);
      }
      return String(num);
    }

    getStarCount('nirmaleeswar30', 'Inzx').then(function (stars) {
      if (stars == null) return;
      var formatted = formatCount(stars);
      if (starEl) starEl.textContent = formatted;
      if (supportStarEl) supportStarEl.textContent = formatted;
      try { localStorage.setItem('inzx_gh_stars', formatted); } catch (e) {}
    });

    fetch('https://api.github.com/repos/nirmaleeswar30/Inzx/releases', {
      headers: { Accept: 'application/vnd.github+json' }
    })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (releases) {
        if (!Array.isArray(releases) || !releases.length) return;

        var latest = releases.find(function (r) { return !r.draft && !r.prerelease; }) || releases[0];
        var total = releases.reduce(function (sum, rel) {
          return sum + (rel.assets || []).reduce(function (s, a) { return s + (a.download_count || 0); }, 0);
        }, 0);

        var ver = $('#dlVersion');
        var cnt = $('#dlCount');
        var tag = $('#releaseTag');
        var eyeVer = $('#eyebrowVersion');

        if (latest.tag_name) {
          if (ver) ver.textContent = latest.tag_name;
          if (eyeVer) eyeVer.textContent = latest.tag_name;
          else if (tag) tag.textContent = latest.tag_name + ' now available';
        }
        if (cnt && total > 0) {
          cnt.textContent = total >= 1000
            ? (total / 1000).toFixed(total >= 10000 ? 0 : 1).replace(/\.0$/, '') + 'k'
            : String(total);
        }
      })
      .catch(function () { /* offline or rate-limited — the static fallbacks stay */ });
  })();

  /* ───────── Dynamic Theming card live palette extractor ───────── */
  (function () {
    var card = document.getElementById('themeCard');
    if (!card) return;

    var THEMES = [
      {
        title: 'Starboy',
        artist: 'The Weeknd',
        primary: '#ff1f3d',
        vibrant: '#ff6b72',
        surface: '#2a0409',
        glow: 'rgba(255, 31, 61, 0.32)',
        border: 'rgba(255, 31, 61, 0.45)',
        badgeBg: 'rgba(255, 31, 61, 0.12)',
        badgeColor: '#ff9fa4'
      },
      {
        title: 'Espresso',
        artist: 'Sabrina Carpenter',
        primary: '#f59e0b',
        vibrant: '#fbbf24',
        surface: '#2e1808',
        glow: 'rgba(245, 158, 11, 0.32)',
        border: 'rgba(245, 158, 11, 0.45)',
        badgeBg: 'rgba(245, 158, 11, 0.14)',
        badgeColor: '#fde68a'
      },
      {
        title: 'Sienna',
        artist: 'The Marías',
        primary: '#0ea5e9',
        vibrant: '#38bdf8',
        surface: '#071526',
        glow: 'rgba(14, 165, 233, 0.34)',
        border: 'rgba(56, 189, 248, 0.45)',
        badgeBg: 'rgba(14, 165, 233, 0.15)',
        badgeColor: '#bae6fd'
      }
    ];

    var posters = card.querySelectorAll('.theme-poster-item');
    var titleEl = card.querySelector('.theme-track-title');
    var artistEl = card.querySelector('.theme-track-artist');
    var stage = card.querySelector('.theme-poster-stage');
    var currentIndex = 0;
    var timer = null;

    function applyTheme(idx) {
      var t = THEMES[idx];
      if (!t) return;
      currentIndex = idx;
      card.setAttribute('data-theme-idx', String(idx));
      card.style.setProperty('--t-primary', t.primary);
      card.style.setProperty('--t-vibrant', t.vibrant);
      card.style.setProperty('--t-surface', t.surface);
      card.style.setProperty('--t-glow', t.glow);
      card.style.setProperty('--t-border', t.border);
      card.style.setProperty('--t-badge-bg', t.badgeBg);
      card.style.setProperty('--t-badge-color', t.badgeColor);

      if (titleEl) titleEl.textContent = t.title;
      if (artistEl) artistEl.textContent = t.artist;

      posters.forEach(function (poster, i) {
        if (i === idx) {
          poster.classList.add('active');
        } else {
          poster.classList.remove('active');
        }
      });
    }

    function nextTheme() {
      var next = (currentIndex + 1) % THEMES.length;
      applyTheme(next);
    }

    function startCycle() {
      stopCycle();
      timer = setInterval(nextTheme, 3600);
    }

    function stopCycle() {
      if (timer) clearInterval(timer);
      timer = null;
    }

    if (stage) {
      stage.addEventListener('click', function () {
        nextTheme();
        stopCycle();
        setTimeout(startCycle, 5000);
      });
    }

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            startCycle();
          } else {
            stopCycle();
          }
        });
      }, { threshold: 0.15 }).observe(card);
    } else {
      startCycle();
    }
  })();

  /* ───────── AI Translation Studio Deck Auto-Cycle ───────── */
  (function () {
    var card = document.getElementById('aiCard');
    if (!card) return;

    var DEMOS = [
      {
        lang: 'ja',
        nativeWords: [
          { text: '夜', state: 'sung' },
          { text: 'に', state: 'sung' },
          { text: '駆', state: 'active-word' },
          { text: 'け', state: '' },
          { text: 'る', state: '' }
        ],
        phoneticLabel: 'ROMAJI',
        phonetic: 'Yo • ru ni ka • ke • ru',
        meaning: '“Racing into the night”',
        latency: '34 ms stream',
        provider: 'Gemini 2.5 Flash'
      },
      {
        lang: 'ko',
        nativeWords: [
          { text: '보고', state: 'sung' },
          { text: '싶다', state: 'active-word' },
          { text: '이렇게', state: '' }
        ],
        phoneticLabel: 'HANGUL',
        phonetic: 'Bo • go sip • da i • reoh • ge',
        meaning: '“I miss you, saying this hurts more”',
        latency: '41 ms stream',
        provider: 'DeepL Translate'
      },
      {
        lang: 'hi',
        nativeWords: [
          { text: 'कभी', state: 'sung' },
          { text: 'कभी', state: 'sung' },
          { text: 'मेरे', state: 'active-word' },
          { text: 'दिल', state: '' },
          { text: 'में', state: '' }
        ],
        phoneticLabel: 'DEVANAGARI',
        phonetic: 'Ka • bhi ka • bhi me • re dil mein',
        meaning: '“Sometimes, deep within my heart…”',
        latency: '38 ms stream',
        provider: 'Llama 3.3 70B'
      },
      {
        lang: 'es',
        nativeWords: [
          { text: 'De', state: 'sung' },
          { text: 'música', state: 'active-word' },
          { text: 'ligera', state: '' },
          { text: 'nada', state: '' },
          { text: 'más', state: '' }
        ],
        phoneticLabel: 'SPANISH',
        phonetic: 'De mú • si • ca li • ge • ra',
        meaning: '“Of light music, nothing else remains”',
        latency: '29 ms stream',
        provider: 'Claude 3.5 Sonnet'
      }
    ];

    var tabs = card.querySelectorAll('.ai-tab');
    var content = card.querySelector('.ai-stream-content');
    var nativeEl = card.querySelector('.ai-text-native');
    var labelEl = card.querySelector('.ai-phonetic-label');
    var phoneticEl = card.querySelector('.ai-text-phonetic');
    var meaningEl = card.querySelector('.ai-text-meaning');
    var latencyEl = card.querySelector('.ai-latency-text');
    var providerEl = card.querySelector('.ai-providers-tag');
    var currentIndex = 0;
    var timer = null;

    function applyDemo(idx) {
      var d = DEMOS[idx];
      if (!d || !content) return;
      currentIndex = idx;

      tabs.forEach(function (tab, i) {
        if (i === idx) {
          tab.classList.add('active');
          tab.setAttribute('aria-selected', 'true');
        } else {
          tab.classList.remove('active');
          tab.setAttribute('aria-selected', 'false');
        }
      });

      content.classList.add('animating');
      setTimeout(function () {
        if (nativeEl) {
          nativeEl.innerHTML = d.nativeWords.map(function (w) {
            return '<span class="ai-word ' + (w.state || '') + '">' + w.text + '</span>';
          }).join(' ');
        }
        if (labelEl) labelEl.textContent = d.phoneticLabel;
        if (phoneticEl) phoneticEl.textContent = d.phonetic;
        if (meaningEl) meaningEl.textContent = d.meaning;
        if (latencyEl) latencyEl.textContent = d.latency;
        if (providerEl) providerEl.textContent = d.provider;

        content.classList.remove('animating');
      }, 160);
    }

    function nextDemo() {
      var next = (currentIndex + 1) % DEMOS.length;
      applyDemo(next);
    }

    function startCycle() {
      stopCycle();
      timer = setInterval(nextDemo, 3800);
    }

    function stopCycle() {
      if (timer) clearInterval(timer);
      timer = null;
    }

    tabs.forEach(function (tab, i) {
      tab.addEventListener('click', function () {
        applyDemo(i);
        stopCycle();
        setTimeout(startCycle, 6000);
      });
    });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) startCycle();
          else stopCycle();
        });
      }, { threshold: 0.15 }).observe(card);
    } else {
      startCycle();
    }
  })();

  /* ───────── Jams Interactive Session Controller ───────── */
  (function () {
    var card = document.getElementById('togetherCard');
    if (!card) return;

    var addBtn = card.querySelector('#jamAddQueueBtn');
    var badge = card.querySelector('#jamQueuedBadge');
    var countEl = card.querySelector('#jamListenersText');
    var syncChip = card.querySelector('#jamSyncIndicator');
    var added = false;
    var resetTimeout = null;

    if (addBtn) {
      addBtn.addEventListener('click', function () {
        if (resetTimeout) clearTimeout(resetTimeout);
        added = !added;

        if (added) {
          addBtn.classList.add('queued-state');
          addBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg><span>Queued by You</span>';
          if (badge) badge.textContent = 'Queued by You (Next)';
          if (countEl) countEl.textContent = '9 listening';
          if (syncChip) {
            syncChip.style.borderColor = 'rgba(126, 224, 176, 0.4)';
            syncChip.style.background = 'rgba(126, 224, 176, 0.08)';
          }
        } else {
          addBtn.classList.remove('queued-state');
          addBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg><span>Add to Queue</span>';
          if (badge) badge.textContent = 'Queued by Alex';
          if (countEl) countEl.textContent = '8 listening';
          if (syncChip) {
            syncChip.style.borderColor = '';
            syncChip.style.background = '';
          }
        }

        resetTimeout = setTimeout(function () {
          added = false;
          addBtn.classList.remove('queued-state');
          addBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg><span>Add to Queue</span>';
          if (badge) badge.textContent = 'Queued by Alex';
          if (countEl) countEl.textContent = '8 listening';
          if (syncChip) {
            syncChip.style.borderColor = '';
            syncChip.style.background = '';
          }
        }, 5000);
      });
    }
  })();
})();
