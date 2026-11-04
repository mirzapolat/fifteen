// Serves the built site and resolves the newest Mac release on the server,
// so visitors never talk to the GitHub API and never land on a GitHub page.
//
//   GET /download/mac  → 302 to the newest Fifteen-<version>.dmg (downloads in place)
//   GET /api/latest    → { version, url, size, publishedAt }
//   GET /health        → ok
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.env.PORT) || 3000;
const REPO = process.env.GITHUB_REPO || 'mirzapolat/fifteen';
const TOKEN = process.env.GITHUB_TOKEN || ''; // optional, only raises the API rate limit
const CACHE_MS = 5 * 60 * 1000;
const FALLBACK = `https://github.com/${REPO}/releases/latest`;
const DIST = join(fileURLToPath(new URL('.', import.meta.url)), 'dist');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.woff2': 'font/woff2',
};

// ---- Latest release (cached) ---------------------------------------------
let cached = null; // { at, release }
let inflight = null;

async function fetchLatest() {
  const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'getfifteen.de',
      ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}),
    },
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`GitHub API ${res.status}`);
  const data = await res.json();
  const dmg = (data.assets || []).find((a) => a.name.toLowerCase().endsWith('.dmg'));
  if (!dmg) throw new Error('No .dmg asset on the latest release');
  return {
    version: String(data.tag_name || '').replace(/^v/, ''),
    url: dmg.browser_download_url,
    size: dmg.size,
    publishedAt: data.published_at,
  };
}

async function latest() {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.release;
  inflight ??= fetchLatest()
    .then((release) => {
      cached = { at: Date.now(), release };
      return release;
    })
    .catch((err) => {
      console.error('[latest]', err.message);
      if (cached) return cached.release; // serve stale rather than nothing
      throw err;
    })
    .finally(() => {
      inflight = null;
    });
  return inflight;
}

// ---- Static files ----------------------------------------------------------
async function sendFile(res, path, { head }) {
  const info = await stat(path).catch(() => null);
  if (!info?.isFile()) return false;
  const immutable = path.includes(`${sep}assets${sep}`);
  res.writeHead(200, {
    'Content-Type': TYPES[extname(path)] || 'application/octet-stream',
    'Content-Length': info.size,
    'Cache-Control': immutable ? 'public, max-age=31536000, immutable' : 'no-cache',
    'X-Content-Type-Options': 'nosniff',
  });
  if (head) res.end();
  else createReadStream(path).pipe(res);
  return true;
}

const ROUTES = new Set(['/', '/imprint', '/privacy']);

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;
  const head = req.method === 'HEAD';

  if (req.method !== 'GET' && !head) {
    res.writeHead(405, { Allow: 'GET, HEAD' }).end();
    return;
  }

  if (path === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' }).end('ok');
    return;
  }

  if (path === '/download/mac' || path === '/download') {
    const target = await latest().then((r) => r.url, () => FALLBACK);
    res.writeHead(302, { Location: target, 'Cache-Control': 'no-store' }).end();
    return;
  }

  if (path === '/api/latest') {
    try {
      const r = await latest();
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=300',
      });
      res.end(JSON.stringify(r));
    } catch {
      res.writeHead(503, { 'Content-Type': 'application/json' }).end('{"error":"unavailable"}');
    }
    return;
  }

  // Static asset, guarded against path traversal.
  let file;
  try {
    file = normalize(join(DIST, decodeURIComponent(path)));
  } catch {
    res.writeHead(400).end();
    return;
  }
  if (file.startsWith(DIST + sep) && (await sendFile(res, file, { head }))) return;

  // Client-side routes get the app shell; everything else is a real 404.
  const route = path.replace(/\/+$/, '') || '/';
  if (ROUTES.has(route)) {
    await sendFile(res, join(DIST, 'index.html'), { head });
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' }).end('Not found');
}).listen(PORT, () => console.log(`getfifteen.de listening on :${PORT}`));
