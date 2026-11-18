/**
 * AltStore / SideStore source for the iOS app, served at /altstore.json
 * (rewritten here by vercel.json).
 *
 * Built from the GitHub releases on every request (cached at the edge), so a
 * release only needs its .ipa attached (the iOS build workflow does that)
 * and AltStore picks it up: nothing here is edited by hand.
 */

const SITE = 'https://inzx.nirmaleeswar.dev';
const REPO = 'nirmaleeswar30/Inzx';
const ICON = `${SITE}/assets/img/brand.png`;
const TINT = '#7C5CFF';

const DESCRIPTION =
  'A YouTube Music client with synced and translated lyrics, Automix, AutoEQ, ' +
  'lossless sources, Jams and Discord Rich Presence. Not affiliated with Google or YouTube.';

async function fetchReleases() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 4000);
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=15`, {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'inzx-altstore-source',
      },
      signal: controller.signal,
    });
    if (!res.ok) return [];
    return await res.json();
  } catch (_) {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

function versionOf(release) {
  return String(release.tag_name || release.name || '').replace(/^v/i, '').trim();
}

function toVersion(release) {
  if (release.draft) return null;
  const ipa = (release.assets || []).find((a) => /\.ipa$/i.test(a.name || ''));
  const version = versionOf(release);
  if (!ipa || !version) return null;
  return {
    version,
    buildVersion: version,
    date: release.published_at || release.created_at,
    localizedDescription: (release.body || '').slice(0, 4000),
    downloadURL: ipa.browser_download_url,
    size: ipa.size,
    minOSVersion: '17.0',
  };
}

export default async function handler(req, res) {
  const releases = await fetchReleases();
  const versions = releases.map(toVersion).filter(Boolean);

  const source = {
    name: 'Inzx',
    identifier: 'dev.nirmaleeswar.inzx.source',
    subtitle: 'Inzx for iPhone and iPad',
    description: DESCRIPTION,
    iconURL: ICON,
    website: SITE,
    tintColor: TINT,
    apps: [
      {
        name: 'Inzx',
        bundleIdentifier: 'com.nirmal.inzx',
        developerName: 'Inzx',
        subtitle: 'YouTube Music, beautifully',
        localizedDescription: DESCRIPTION,
        iconURL: ICON,
        tintColor: TINT,
        category: 'entertainment',
        screenshotURLs: [],
        versions,
        appPermissions: {
          entitlements: ['com.apple.security.application-groups'],
          privacy: {
            NSCameraUsageDescription: 'Inzx uses the camera to scan an Inzx Connect pairing code.',
            NSPhotoLibraryUsageDescription: 'Inzx opens your photo library when you pick a playlist cover.',
          },
        },
      },
    ],
    news: [],
  };

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  // Fresh within ten minutes of a release; served stale while revalidating.
  res.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
  res.status(200).send(JSON.stringify(source, null, 2));
}
