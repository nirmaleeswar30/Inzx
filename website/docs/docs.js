// Inzx Docs: builds the section nav, prev/next links and "On this page"
// list from one list of pages, so adding a page means adding one line here.
(function () {
  var GROUPS = [
    { title: 'Getting started', pages: [
      { slug: '', title: 'Overview', keys: 'start intro what is inzx youtube music' },
      { slug: 'install', title: 'Install & update', keys: 'download apk obtainium github release update upgrade ota shorebird' },
      { slug: 'sign-in', title: 'Signing in', keys: 'google account login youtube music sign in one login profile history guest' },
    ] },
    { title: 'Listening', pages: [
      { slug: 'player', title: 'Now playing', keys: 'player cinematic ripple og default lyrics up next queue related shuffle repeat like device output spectrum waveform liquid glass' },
      { slug: 'lyrics', title: 'Lyrics & AI translation', keys: 'synced karaoke word translation ai offset provider lrclib musixmatch ttml deepl gemini openrouter transliteration romanization' },
      { slug: 'audio', title: 'Audio & quality', keys: 'quality 320kbps jiosaavn high quality sources crossfade cache streaming routing bluetooth' },
      { slug: 'downloads', title: 'Downloads & offline', keys: 'offline download local files folders storage' },
    ] },
    { title: 'Together', pages: [
      { slug: 'jams', title: 'Jams', keys: 'listen together friends sync code link host controller permission websocket' },
      { slug: 'sharing', title: 'Sharing links', keys: 'share link preview whatsapp discord open in app short url' },
    ] },
    { title: 'Around the app', pages: [
      { slug: 'widgets', title: 'Home screen widgets', keys: 'widget pill square wide launcher 2x2 4x4 4x1' },
      { slug: 'integrations', title: 'Integrations', keys: 'discord rich presence rpc backup restore android auto' },
    ] },
    { title: 'Help', pages: [
      { slug: 'faq', title: 'Troubleshooting & FAQ', keys: 'help problem error wrong song not playing history login crash bug report' },
    ] },
  ];

  var flat = [];
  GROUPS.forEach(function (g) { g.pages.forEach(function (p) { flat.push(p); }); });

  // Relative links, so the docs work on the site (/docs/player), from a
  // local server, and straight from disk (file:///.../docs/player.html).
  function href(slug) { return (slug || 'index') + '.html'; }
  var last = location.pathname.replace(/\/$/, '').split('/').pop().replace(/\.html$/, '');
  var current = (last === 'docs' || last === 'index') ? '' : last;
  var index = flat.findIndex(function (p) { return p.slug === current; });

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; });
  }

  // Section nav
  var nav = document.getElementById('docs-nav');
  if (nav) {
    var html = '<input class="nav-search" id="nav-search" type="search" placeholder="Search the docs" aria-label="Search the docs">';
    GROUPS.forEach(function (g) {
      html += '<div class="nav-group"><h4>' + esc(g.title) + '</h4>';
      g.pages.forEach(function (p) {
        html += '<a href="' + href(p.slug) + '" data-keys="' + esc((p.title + ' ' + p.keys).toLowerCase()) + '"' +
          (p.slug === current ? ' aria-current="page"' : '') + '>' + esc(p.title) + '</a>';
      });
      html += '</div>';
    });
    html += '<p class="nav-empty" id="nav-empty" hidden>No page matches. Try the FAQ.</p>';
    nav.innerHTML = html;

    var search = document.getElementById('nav-search');
    search.addEventListener('input', function () {
      var q = search.value.trim().toLowerCase();
      var any = false;
      nav.querySelectorAll('.nav-group').forEach(function (group) {
        var shown = 0;
        group.querySelectorAll('a').forEach(function (a) {
          var hit = !q || a.dataset.keys.indexOf(q) !== -1;
          a.hidden = !hit;
          if (hit) shown++;
        });
        group.hidden = shown === 0;
        if (shown) any = true;
      });
      document.getElementById('nav-empty').hidden = any;
    });
  }

  // Mobile menu
  var menu = document.getElementById('menu-btn');
  if (menu) {
    menu.addEventListener('click', function () {
      var open = document.body.classList.toggle('nav-open');
      menu.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }

  // Prev / next
  var pager = document.getElementById('pager');
  if (pager && index !== -1) {
    var prev = flat[index - 1];
    var next = flat[index + 1];
    pager.innerHTML =
      (prev ? '<a class="prev" href="' + href(prev.slug) + '"><small>Previous</small>' + esc(prev.title) + '</a>' : '') +
      (next ? '<a class="next" href="' + href(next.slug) + '"><small>Next</small>' + esc(next.title) + '</a>' : '');
  }

  // Heading anchors + "On this page"
  var article = document.querySelector('.prose');
  var toc = document.getElementById('docs-toc');
  if (article) {
    var heads = article.querySelectorAll('h2[id]');
    heads.forEach(function (h) {
      var a = document.createElement('a');
      a.className = 'anchor';
      a.href = '#' + h.id;
      a.setAttribute('aria-label', 'Link to this section');
      a.textContent = '#';
      h.appendChild(a);
    });
    if (toc && heads.length > 1) {
      var t = '<h4>On this page</h4>';
      heads.forEach(function (h) {
        t += '<a href="#' + h.id + '">' + esc(h.firstChild.textContent.trim()) + '</a>';
      });
      toc.innerHTML = t;
      var links = toc.querySelectorAll('a');
      if ('IntersectionObserver' in window) {
        var obs = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) {
            if (!e.isIntersecting) return;
            links.forEach(function (l) { l.classList.toggle('active', l.getAttribute('href') === '#' + e.target.id); });
          });
        }, { rootMargin: '-80px 0px -70% 0px' });
        heads.forEach(function (h) { obs.observe(h); });
      }
    }
  }
})();
