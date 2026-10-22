/**
 * Inzx Landing Page Scripts
 * Interactive visualizer, syllable karaoke preview, screenshot lightbox, and modal interactions.
 */

document.addEventListener('DOMContentLoaded', () => {
  initNavbar();
  initVisualizer();
  initKaraokeDemo();
  initScreenshotGallery();
  initCopyButtons();
  initFaqAccordion();
  initUpiModal();
  initBackToTop();
});

/* ==========================================================================
   NAVBAR & SCROLL HANDLING
   ========================================================================== */
function initNavbar() {
  const header = document.querySelector('.site-header');
  const menuBtn = document.querySelector('.mobile-menu-btn');
  const navLinks = document.querySelector('.nav-links');

  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  });

  if (menuBtn && navLinks) {
    menuBtn.addEventListener('click', () => {
      navLinks.classList.toggle('open');
      const isOpen = navLinks.classList.contains('open');
      menuBtn.setAttribute('aria-expanded', isOpen);
      menuBtn.innerHTML = isOpen ? '&#10005;' : '&#9776;';
    });

    // Close menu when clicking any nav link
    navLinks.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        navLinks.classList.remove('open');
        menuBtn.innerHTML = '&#9776;';
      });
    });
  }
}

/* ==========================================================================
   CANVAS AUDIO VISUALIZER
   ========================================================================== */
function initVisualizer() {
  const canvas = document.getElementById('audioVisualizerCanvas');
  const playBtn = document.getElementById('visualizerPlayBtn');
  const playIcon = playBtn ? playBtn.querySelector('span') : null;
  const scrubBar = document.getElementById('visualizerScrubBar');
  const scrubProgress = document.getElementById('visualizerScrubProgress');
  const currentTimeEl = document.getElementById('visualizerCurrentTime');

  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  let isPlaying = true;
  let animationFrameId = null;
  const numBars = 48;
  const barHeights = new Array(numBars).fill(10);
  const targetHeights = new Array(numBars).fill(10);
  let progressPercent = 38;
  let trackDurationSeconds = 214; // 3:34

  function resizeCanvas() {
    canvas.width = canvas.parentElement.clientWidth;
    canvas.height = canvas.parentElement.clientHeight || 40;
  }
  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  function updateBars() {
    const width = canvas.width;
    const height = canvas.height;
    ctx.clearRect(0, 0, width, height);

    const barWidth = Math.max(2, (width / numBars) - 2.5);
    const gap = 2.5;

    for (let i = 0; i < numBars; i++) {
      if (isPlaying) {
        if (Math.random() > 0.6) {
          // Generate wave peaks around the center
          const distFromCenter = Math.abs(i - numBars / 2) / (numBars / 2);
          const factor = 1 - distFromCenter * 0.55;
          targetHeights[i] = Math.max(4, Math.random() * height * factor * 0.95);
        }
      } else {
        targetHeights[i] = 4; // Idle minimal bar height
      }

      // Smooth interpolation
      barHeights[i] += (targetHeights[i] - barHeights[i]) * 0.22;

      const x = i * (barWidth + gap);
      const barH = barHeights[i];
      const y = (height - barH) / 2;

      // Glowing crimson gradient
      const grad = ctx.createLinearGradient(0, y, 0, y + barH);
      grad.addColorStop(0, '#ff4a52');
      grad.addColorStop(0.5, '#e50914');
      grad.addColorStop(1, '#80050c');

      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.roundRect(x, y, barWidth, barH, 2);
      ctx.fill();
    }

    if (isPlaying) {
      progressPercent = (progressPercent + 0.04) % 100;
      if (scrubProgress) {
        scrubProgress.style.width = `${progressPercent}%`;
      }
      if (currentTimeEl) {
        const curSec = Math.floor((progressPercent / 100) * trackDurationSeconds);
        const m = Math.floor(curSec / 60);
        const s = curSec % 60;
        currentTimeEl.textContent = `${m}:${s < 10 ? '0' : ''}${s}`;
      }
    }

    animationFrameId = requestAnimationFrame(updateBars);
  }

  updateBars();

  if (playBtn) {
    playBtn.addEventListener('click', () => {
      isPlaying = !isPlaying;
      if (playIcon) {
        playIcon.textContent = isPlaying ? '⏸' : '▶';
      }
    });
  }

  if (scrubBar) {
    scrubBar.addEventListener('click', (e) => {
      const rect = scrubBar.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      progressPercent = Math.max(0, Math.min(100, (clickX / rect.width) * 100));
      if (scrubProgress) {
        scrubProgress.style.width = `${progressPercent}%`;
      }
    });
  }
}

/* ==========================================================================
   INTERACTIVE WORD-LEVEL KARAOKE DEMO
   ========================================================================== */
function initKaraokeDemo() {
  const syllables = document.querySelectorAll('.karaoke-lines-container .syllable');
  const aiTabs = document.querySelectorAll('.ai-tab');
  const sublines = document.querySelectorAll('.translation-subline');

  if (syllables.length === 0) return;

  let currentIndex = 0;
  let intervalId = null;

  function advanceKaraoke() {
    syllables.forEach((s, idx) => {
      if (idx < currentIndex) {
        s.className = 'syllable sung';
      } else if (idx === currentIndex) {
        s.className = 'syllable current';
      } else {
        s.className = 'syllable';
      }
    });

    currentIndex = (currentIndex + 1) % syllables.length;
  }

  intervalId = setInterval(advanceKaraoke, 380);

  // AI Translation Mode Switcher
  const translations = {
    original: [
      "君の声を聴かせて",
      "夜空に咲く花のように"
    ],
    en: [
      "Let me hear your voice",
      "Like flowers blooming in the midnight sky"
    ],
    romaji: [
      "Kimi no koe o kikasete",
      "Yozora ni saku hana no you ni"
    ]
  };

  aiTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      aiTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      const lang = tab.getAttribute('data-lang') || 'en';

      if (translations[lang]) {
        sublines.forEach((el, i) => {
          if (translations[lang][i]) {
            el.textContent = translations[lang][i];
            el.style.opacity = '0';
            setTimeout(() => {
              el.style.transition = 'opacity 0.25s ease';
              el.style.opacity = '1';
            }, 50);
          }
        });
      }
    });
  });
}

/* ==========================================================================
   SCREENSHOTS GALLERY & LIGHTBOX
   ========================================================================== */
function initScreenshotGallery() {
  const tabs = document.querySelectorAll('.gallery-tab-btn');
  const cards = document.querySelectorAll('.screenshot-card');
  const lightbox = document.getElementById('screenshotLightbox');
  const lightboxImg = document.getElementById('lightboxImg');
  const lightboxCaption = document.getElementById('lightboxCaption');
  const closeBtn = document.querySelector('.lightbox-close');
  const prevBtn = document.querySelector('.lightbox-prev');
  const nextBtn = document.querySelector('.lightbox-next');

  let activeIndex = 0;
  let visibleCards = Array.from(cards);

  // Filter tabs
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');

      const filter = tab.getAttribute('data-filter');

      cards.forEach(card => {
        const category = card.getAttribute('data-category');
        if (filter === 'all' || category === filter) {
          card.style.display = 'block';
        } else {
          card.style.display = 'none';
        }
      });

      visibleCards = Array.from(cards).filter(c => c.style.display !== 'none');
    });
  });

  // Lightbox click
  cards.forEach(card => {
    card.addEventListener('click', () => {
      const img = card.querySelector('img');
      const caption = card.querySelector('.overlay-title')?.textContent || '';
      activeIndex = visibleCards.indexOf(card);
      openLightbox(img.src, caption);
    });
  });

  function openLightbox(src, caption) {
    if (!lightbox || !lightboxImg) return;
    lightboxImg.src = src;
    if (lightboxCaption) lightboxCaption.textContent = caption;
    lightbox.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    if (!lightbox) return;
    lightbox.classList.remove('open');
    document.body.style.overflow = '';
  }

  function showSlide(index) {
    if (visibleCards.length === 0) return;
    if (index < 0) index = visibleCards.length - 1;
    if (index >= visibleCards.length) index = 0;
    activeIndex = index;

    const targetCard = visibleCards[activeIndex];
    const img = targetCard.querySelector('img');
    const caption = targetCard.querySelector('.overlay-title')?.textContent || '';
    if (lightboxImg) lightboxImg.src = img.src;
    if (lightboxCaption) lightboxCaption.textContent = caption;
  }

  if (closeBtn) closeBtn.addEventListener('click', closeLightbox);
  if (prevBtn) prevBtn.addEventListener('click', (e) => { e.stopPropagation(); showSlide(activeIndex - 1); });
  if (nextBtn) nextBtn.addEventListener('click', (e) => { e.stopPropagation(); showSlide(activeIndex + 1); });

  if (lightbox) {
    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox || e.target.classList.contains('lightbox-content')) {
        closeLightbox();
      }
    });
  }

  // Keyboard navigation
  document.addEventListener('keydown', (e) => {
    if (!lightbox || !lightbox.classList.contains('open')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') showSlide(activeIndex - 1);
    if (e.key === 'ArrowRight') showSlide(activeIndex + 1);
  });
}

/* ==========================================================================
   COPY TO CLIPBOARD BUTTONS
   ========================================================================== */
function initCopyButtons() {
  document.querySelectorAll('[data-copy-target]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const targetSelector = btn.getAttribute('data-copy-target');
      const targetEl = document.querySelector(targetSelector);
      if (!targetEl) return;

      const text = targetEl.textContent.trim();
      try {
        await navigator.clipboard.writeText(text);
        const originalText = btn.textContent;
        btn.textContent = 'Copied! ✓';
        btn.style.background = '#00c853';
        btn.style.color = '#ffffff';

        setTimeout(() => {
          btn.textContent = originalText;
          btn.style.background = '';
          btn.style.color = '';
        }, 2200);
      } catch (err) {
        console.error('Failed to copy', err);
      }
    });
  });
}

/* ==========================================================================
   FAQ ACCORDION
   ========================================================================== */
function initFaqAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    if (!questionBtn) return;

    questionBtn.addEventListener('click', () => {
      const isActive = item.classList.contains('active');

      // Close all other items
      faqItems.forEach(other => {
        if (other !== item) other.classList.remove('active');
      });

      item.classList.toggle('active', !isActive);
    });
  });
}

/* ==========================================================================
   UPI MODAL
   ========================================================================== */
function initUpiModal() {
  const triggerBtn = document.getElementById('openUpiModalBtn');
  const modal = document.getElementById('upiModal');
  const closeBtn = document.getElementById('closeUpiModalBtn');

  if (!modal) return;

  if (triggerBtn) {
    triggerBtn.addEventListener('click', () => {
      modal.classList.add('open');
      document.body.style.overflow = 'hidden';
    });
  }

  function closeModal() {
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  if (closeBtn) closeBtn.addEventListener('click', closeModal);

  modal.addEventListener('click', (e) => {
    if (e.target === modal) closeModal();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modal.classList.contains('open')) {
      closeModal();
    }
  });
}

/* ==========================================================================
   BACK TO TOP
   ========================================================================== */
function initBackToTop() {
  const backBtn = document.getElementById('backToTopBtn');
  if (!backBtn) return;

  window.addEventListener('scroll', () => {
    if (window.scrollY > 400) {
      backBtn.classList.add('visible');
    } else {
      backBtn.classList.remove('visible');
    }
  });

  backBtn.addEventListener('click', () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });
}
