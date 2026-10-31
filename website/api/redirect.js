/**
 * Vercel serverless function for Inzx share links and Jam invites.
 *
 * Short links are rewritten here by vercel.json:
 *   /s/:id    song         /a/:id   album        /p/:id   playlist
 *   /ar/:id   artist       /pod/:id podcast      /jam/:code  Jam invite
 *
 * Crawlers (WhatsApp, Discord, Telegram, X, iMessage...) read the Open Graph
 * tags, so the preview shows the song's artwork and title. People get bounced
 * into the app through the inzx:// scheme, with a fallback card if it isn't
 * installed. Older links (?url=<base64 deep link>) still work.
 */

const SITE = 'https://inzx.nirmaleeswar.dev';
const APP_ICON = `${SITE}/assets/img/brand.png`;
const RELEASES = 'https://github.com/nirmaleeswar30/Inzx/releases/latest';

const TYPES = new Set(['song', 'album', 'playlist', 'artist', 'podcast', 'jam']);
const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function fetchJson(url, init = {}, timeoutMs = 1800) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...init, signal: controller.signal });
    if (!res.ok) return null;
    return await res.json();
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Title / artist for a video via YouTube's public oEmbed endpoint. */
async function songMeta(videoId) {
  const data = await fetchJson(
    `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(
      `https://music.youtube.com/watch?v=${videoId}`,
    )}`,
  );
  return {
    title: data?.title || '',
    subtitle: (data?.author_name || '').replace(/ - Topic$/, ''),
    // maxres isn't generated for every upload; hq always is.
    image: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
  };
}

/** Header title + artwork for an album / playlist / artist / podcast page. */
async function browseMeta(browseId) {
  const data = await fetchJson(
    'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        context: {
          client: { clientName: 'WEB_REMIX', clientVersion: '1.20260114.03.00', hl: 'en', gl: 'US' },
        },
        browseId,
      }),
    },
    2200,
  );
  if (!data) return null;

  let title = '';
  let subtitle = '';
  let image = '';
  let best = 0;
  const visit = (node, depth) => {
    if (!node || typeof node !== 'object' || depth > 14) return;
    if (Array.isArray(node)) {
      node.forEach((n) => visit(n, depth + 1));
      return;
    }
    if (!title && node.title?.runs?.[0]?.text && /Header|header/.test(Object.keys(node).join())) {
      title = node.title.runs.map((r) => r.text).join('');
    }
    if (Array.isArray(node.thumbnails)) {
      for (const t of node.thumbnails) {
        const area = (t.width || 0) * (t.height || 0);
        if (t.url && area > best) {
          best = area;
          image = t.url;
        }
      }
    }
    for (const [key, value] of Object.entries(node)) {
      if (key === 'contents' && depth > 2) continue; // stay in the header
      visit(value, depth + 1);
    }
  };
  visit(data.header || data, 0);
  if (!title) {
    const t = data.header && JSON.stringify(data.header).match(/"title":\{"runs":\[\{"text":"([^"]+)"/);
    title = t ? t[1] : '';
  }
  const sub = data.header && JSON.stringify(data.header).match(/"(?:subtitle|straplineTextOne)":\{"runs":\[\{"text":"([^"]+)"/);
  subtitle = sub ? sub[1] : '';
  return { title, subtitle, image: image.startsWith('//') ? `https:${image}` : image };
}

function deepLinkFor(type, id) {
  return `inzx://open/${type}?id=${encodeURIComponent(id)}`;
}

export default async function handler(req, res) {
  let { type, id, url, v } = req.query;
  type = String(type || '').toLowerCase();
  id = String(id || '').trim();

  // Legacy long links: ?url=<base64 of inzx://open/<type>?id=<id>>
  if (url && !type) {
    try {
      const decoded = new URL(Buffer.from(String(url), 'base64').toString('utf-8'));
      type = decoded.pathname.replace(/^\//, '');
      id = decoded.searchParams.get('id') || '';
    } catch (_) {
      // fall through to the generic card
    }
  }

  const valid = TYPES.has(type) && ID_PATTERN.test(id);
  if (type === 'jam') id = id.toUpperCase();
  const deepLink = valid ? deepLinkFor(type, id) : 'inzx://open/home';

  let title = 'Inzx · YouTube Music, beautifully';
  let desc = 'Word-synced lyrics, 320 kbps audio, dynamic theming and Jams. Free and open source.';
  let image = APP_ICON;
  let heading = 'Inzx';
  let subheading = '';
  let cta = 'Open in Inzx';

  if (valid && type === 'song') {
    const meta = await songMeta(id);
    image = meta.image;
    heading = meta.title || 'A song on Inzx';
    subheading = meta.subtitle;
    title = meta.title ? `${meta.title}${meta.subtitle ? ` · ${meta.subtitle}` : ''}` : 'Listen on Inzx';
    desc = 'Listen on Inzx — word-synced lyrics, 320 kbps, no ads.';
    cta = 'Play in Inzx';
  } else if (valid && type === 'jam') {
    // Optional ?v=<videoId> carries what's playing, for the artwork.
    const vid = typeof v === 'string' && /^[A-Za-z0-9_-]{11}$/.test(v) ? v : null;
    const meta = vid ? await songMeta(vid) : null;
    if (meta) image = meta.image;
    heading = 'Join my Jam';
    subheading = meta?.title ? `Now playing: ${meta.title}` : '';
    title = meta?.title ? `🎧 Join my Jam · ${meta.title}` : `🎧 Join my Jam on Inzx · ${id}`;
    desc = `Listen together in sync on Inzx. Jam code: ${id}`;
    cta = 'Join the Jam in Inzx';
  } else if (valid) {
    const meta = await browseMeta(id);
    const label = { album: 'Album', playlist: 'Playlist', artist: 'Artist', podcast: 'Podcast' }[type];
    if (meta?.image) image = meta.image;
    heading = meta?.title || `${label} on Inzx`;
    subheading = meta?.subtitle || label;
    title = meta?.title ? `${meta.title} · ${label}` : `${label} on Inzx`;
    desc = `Open this ${label.toLowerCase()} in Inzx.`;
  }

  const safe = {
    title: escapeHtml(title),
    desc: escapeHtml(desc),
    image: escapeHtml(image),
    deepLink: escapeHtml(deepLink),
    heading: escapeHtml(heading),
    subheading: escapeHtml(subheading),
    cta: escapeHtml(cta),
    code: escapeHtml(type === 'jam' ? id : ''),
  };
  const square = type !== 'artist';

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${safe.title}</title>
<meta name="description" content="${safe.desc}">
<meta property="og:type" content="${type === 'song' ? 'music.song' : 'website'}">
<meta property="og:site_name" content="Inzx">
<meta property="og:title" content="${safe.title}">
<meta property="og:description" content="${safe.desc}">
<meta property="og:image" content="${safe.image}">
<meta property="og:image:alt" content="${safe.title}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${safe.title}">
<meta name="twitter:description" content="${safe.desc}">
<meta name="twitter:image" content="${safe.image}">
<meta name="theme-color" content="#050506">
<meta http-equiv="refresh" content="0;url=${safe.deepLink}">
<link rel="icon" type="image/png" href="/assets/img/logo_transparent.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@600;700&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root { --ink:#050506; --red:#ff1f2e; --red-hot:#ff4b52; --fg:#f2f2f5; --fg-2:#b6b6c0; --line:rgba(255,255,255,.1); }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { min-height:100vh; display:flex; align-items:center; justify-content:center; padding:20px;
    background:var(--ink); color:var(--fg); font-family:'Inter',system-ui,sans-serif; overflow-x:hidden; }
  .bg { position:fixed; inset:-20%; background:url('${safe.image}') center/cover; filter:blur(70px) saturate(1.4);
    opacity:.35; transform:scale(1.1); z-index:0; }
  .card { position:relative; z-index:1; width:100%; max-width:400px; text-align:center; padding:28px 24px;
    border-radius:28px; background:rgba(10,10,12,.62); border:1px solid var(--line);
    box-shadow:0 30px 70px -20px rgba(0,0,0,.85); backdrop-filter:blur(24px); -webkit-backdrop-filter:blur(24px); }
  .badge { display:inline-flex; align-items:center; gap:8px; padding:6px 14px; border-radius:999px; margin-bottom:22px;
    background:rgba(255,255,255,.06); border:1px solid var(--line); font:700 11px 'Space Grotesk',sans-serif;
    letter-spacing:.08em; color:var(--red-hot); }
  .badge img { width:18px; height:18px; }
  .art { width:${square ? '220px' : '180px'}; height:${square ? '220px' : '180px'}; margin:0 auto 20px;
    border-radius:${square ? '18px' : '50%'}; overflow:hidden; background:#111; border:1px solid var(--line);
    box-shadow:0 20px 40px rgba(0,0,0,.6); }
  .art img { width:100%; height:100%; object-fit:cover; display:block; }
  h1 { font:700 22px/1.25 'Space Grotesk',sans-serif; margin-bottom:6px; }
  .sub { color:var(--fg-2); font-size:14.5px; margin-bottom:22px; }
  .code { display:flex; justify-content:center; gap:6px; margin:-6px 0 22px; }
  .code b { width:36px; height:46px; display:grid; place-items:center; border-radius:10px; font:700 20px 'Space Grotesk';
    color:var(--red-hot); background:rgba(255,31,46,.08); border:1px solid rgba(255,31,46,.35); }
  .btn { display:flex; align-items:center; justify-content:center; padding:14px 20px; border-radius:14px;
    font:700 15px 'Space Grotesk',sans-serif; text-decoration:none; transition:transform .2s, background .2s; }
  .btn + .btn { margin-top:10px; }
  .primary { background:linear-gradient(120deg,var(--red-hot),var(--red) 55%,#9e0009); color:#fff;
    box-shadow:0 10px 26px -6px rgba(255,31,46,.55); }
  .primary:hover { transform:translateY(-2px); }
  .ghost { background:rgba(255,255,255,.06); border:1px solid var(--line); color:var(--fg); }
  .ghost:hover { background:rgba(255,255,255,.1); }
</style>
</head>
<body>
<div class="bg" aria-hidden="true"></div>
<main class="card">
  <div class="badge"><img src="/assets/img/logo_transparent.png" alt="">${type === 'jam' ? 'INZX JAM' : 'OPEN IN INZX'}</div>
  <div class="art"><img src="${safe.image}" alt=""></div>
  <h1>${safe.heading}</h1>
  ${safe.subheading ? `<p class="sub">${safe.subheading}</p>` : '<p class="sub"></p>'}
  ${safe.code ? `<div class="code">${safe.code.split('').map((c) => `<b>${c}</b>`).join('')}</div>` : ''}
  <a class="btn primary" href="${safe.deepLink}">${safe.cta}</a>
  <a class="btn ghost" href="${RELEASES}" rel="noopener">Get Inzx for Android</a>
</main>
<script>try { window.location.href = ${JSON.stringify(deepLink)}; } catch (_) {}</script>
</body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=86400, stale-while-revalidate=604800');
  res.status(200).send(html);
}
