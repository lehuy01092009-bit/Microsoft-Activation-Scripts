/**
 * Microsoft Activation Scripts - htchuai fork
 * Cloudflare Worker cho domain htchuai.dpdns.org
 *
 * Routes:
 *   GET /            -> landing page
 *   GET /get         -> trả về loader PowerShell (để `irm .../get | iex`)
 *   GET /MAS_AIO.cmd -> trả về script AIO trực tiếp
 *   GET /separate    -> danh sách file version riêng lẻ
 */

// Nguon file: jsDelivr mirror truoc (cache ngan, purge duoc), raw github la fallback.
// raw.githubusercontent.com co CDN cache ~5 phut khien ban moi push chua hien ngay.
const SOURCES = [
  'https://cdn.jsdelivr.net/gh/lehuy01092009-bit/Microsoft-Activation-Scripts@master',
  'https://raw.githubusercontent.com/lehuy01092009-bit/Microsoft-Activation-Scripts/master',
];
const REPO_ZIP = 'https://codeload.github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/zip/refs/heads/master';
const VERSION  = '3.12-htchuai';

// ---- HTML landing ----------------------------------------------------------

const LANDING = `<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Microsoft Activation Scripts - htchuai fork</title>
<style>
  :root { --bg:#0d1117; --card:#161b22; --line:#30363d; --fg:#e6edf3; --dim:#8b949e; --accent:#3fb950; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--fg);
         font:15px/1.65 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }
  .wrap { max-width:760px; margin:0 auto; padding:56px 24px 72px; }
  h1 { font-size:26px; margin:0 0 6px; letter-spacing:-.4px; }
  .ver { color:var(--accent); font-size:13px; }
  p.lead { color:var(--dim); margin:14px 0 32px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:8px;
          padding:18px 20px; margin-bottom:16px; }
  .card h2 { font-size:14px; margin:0 0 12px; color:var(--dim);
             text-transform:uppercase; letter-spacing:.7px; font-weight:600; }
  pre { background:#010409; border:1px solid var(--line); border-radius:6px;
        padding:12px 14px; overflow-x:auto; margin:0; font-size:13.5px; }
  code { color:var(--accent); }
  .note { color:var(--dim); font-size:13px; margin-top:10px; }
  a { color:#58a6ff; }
  table { width:100%; border-collapse:collapse; font-size:13.5px; }
  td { padding:7px 0; border-bottom:1px solid var(--line); }
  td:last-child { color:var(--dim); text-align:right; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Microsoft Activation Scripts</h1>
  <div class="ver">htchuai fork &middot; v${VERSION}</div>
  <p class="lead">Fork cá nhân của MAS. Chạy trong PowerShell (tự nâng quyền admin).</p>

  <div class="card">
    <h2>Chạy</h2>
    <pre>irm https://htchuai.dpdns.org/get | iex</pre>
    <div class="note">Mở PowerShell thường (không cần Admin) — loader sẽ tự xin quyền.</div>
  </div>

  <div class="card">
    <h2>Chạy ẩn / có tham số</h2>
    <pre>&amp; ([scriptblock]::Create((irm https://htchuai.dpdns.org/get))) /HWID</pre>
    <div class="note">Tham số MAS hợp lệ: /HWID /Ohook /Z- /K- /S</div>
  </div>

  <div class="card">
    <h2>Activation methods</h2>
    <table>
      <tr><td>HWID</td><td>Windows 10-11 · Permanent</td></tr>
      <tr><td>Ohook</td><td>Office · Permanent</td></tr>
      <tr><td>TSforge</td><td>Windows / ESU / Office · Permanent</td></tr>
      <tr><td>Online KMS</td><td>Windows / Office · 180 ngày + renewal</td></tr>
    </table>
  </div>
</div>
</body>
</html>`;

// ---- helpers ---------------------------------------------------------------

function txt(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    },
  });
}

async function fromRepo(path, fallbackMsg) {
  let lastErr = '';
  for (const base of SOURCES) {
    const url = `${base}/${path}`;
    try {
      const r = await fetch(url, { cf: { cacheTtl: 60 } });
      if (!r.ok) {
        lastErr = `upstream ${r.status} (${new URL(base).host})`;
        continue;
      }
      return txt(await r.text());
    } catch (e) {
      lastErr = e.message;
    }
  }
  return txt(`${fallbackMsg}\n\n(${lastErr})`, 502);
}

// ---- router ----------------------------------------------------------------

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);

    switch (pathname.replace(/\/+$/, '') || '/') {
      case '/':
        return new Response(LANDING, {
          headers: { 'Content-Type': 'text/html; charset=utf-8' },
        });

      case '/get':
        return fromRepo('get.ps1', 'Could not load the MAS loader. Try again later.');

      case '/MAS_AIO.cmd':
      case '/aio':
        return fromRepo(
          'All-In-One-Version-KL/MAS_AIO.cmd',
          'Could not load MAS_AIO.cmd.'
        );

      case '/zip':
        return Response.redirect(REPO_ZIP, 302);

      default:
        return txt('Not found.\n\nRoutes: /  /get  /aio  /zip\n', 404);
    }
  },
};
