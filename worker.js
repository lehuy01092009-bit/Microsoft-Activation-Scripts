/**
 * Microsoft Activation Scripts - htchuai fork
 * Cloudflare Worker cho domain htchuai.dpdns.org
 *
 * Routes:
 *   GET /get         -> script loader cho `irm https://htchuai.dpdns.org/get | iex`
 *   GET /aio         -> MAS_AIO.cmd
 *   GET /zip         -> redirect ZIP cua repo
 *
 * QUY TAC /get:
 *   - Request KHONG phai trinh duyet (PowerShell `irm`, curl...) -> tra ve script.
 *     Khach chay binh thuong, chi can key (xem /api/mas/key).
 *   - Request tu TRINH DUYET:
 *       + IP nam trong danh sach cho phep (/api/mas/ips) -> tra trang HTML xem code,
 *         co gan san doan phat hien DevTools giong het web chinh (F12 -> redirect).
 *       + IP khac -> tra 404 y nhu mot URL khong ton tai tren web chinh.
 */

// Nguon file: jsDelivr mirror truoc (cache ngan, purge duoc), raw github la fallback.
const SOURCES = [
  'https://cdn.jsdelivr.net/gh/lehuy01092009-bit/Microsoft-Activation-Scripts@master',
  'https://raw.githubusercontent.com/lehuy01092009-bit/Microsoft-Activation-Scripts/master',
];
const REPO_ZIP = 'https://codeload.github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/zip/refs/heads/master';
const VERSION  = '3.12-htchuai';

// Danh sach IP duoc xem code (lay tu web chinh). Doi token thi phai sua ca
// app/ajax/global/default/mas-ips.php.
const IP_API   = 'https://htchuai.dpdns.org/api/mas/ips';
const IP_TOKEN = '71ddd83103743658565fed83d003c449';
const IP_TTL   = 60000; // ms

// Giong het web chinh khi bat fuck-devtools (main.min.js)
const DEVTOOLS_REDIRECT = '//t.me/ThanhPhucDev';

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

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/**
 * Request nay la trinh duyet that su?
 * Tieu chi chinh: Accept phai co text/html. PowerShell `irm` / curl khong bao gio
 * gui gia tri nay, nen khach van nhan duoc script binh thuong.
 */
function isBrowser(request) {
  const accept = request.headers.get('Accept') || '';
  const ua = request.headers.get('User-Agent') || '';
  if (!/text\/html/i.test(accept)) return false;
  // chan them cho chac: mot so client co the gia Accept
  if (/powershell|curl|wget|python|libwww|httpclient|winhttp/i.test(ua)) return false;
  return true;
}

// Cache trong bo nho cua worker instance (60s). Neu goi API loi thi giu
// danh sach cu -> khong tu nhien khoa het nguoi dung.
let ipCache = { ips: null, at: 0 };

async function allowedIps() {
  const now = Date.now();
  if (ipCache.ips !== null && now - ipCache.at < IP_TTL) return ipCache.ips;
  try {
    const r = await fetch(`${IP_API}?k=${IP_TOKEN}`, { cf: { cacheTtl: 30 } });
    if (r.ok) {
      const d = await r.json();
      if (Array.isArray(d.ips)) {
        ipCache = { ips: d.ips, at: now };
        return d.ips;
      }
    }
  } catch (e) {
    // giu danh sach cu
  }
  return ipCache.ips || [];
}

/** Tra ve 404 giong y nhu mot URL khong ton tai tren web chinh */
async function notFound(request) {
  try {
    const u = new URL(request.url);
    u.pathname = '/__mas404_' + Math.random().toString(36).slice(2);
    u.search = '';

    // PHAI gui kem header cua request goc. Neu khong co User-Agent thi web chinh
    // se hien "Undefined array key HTTP_USER_AGENT" + modal "Browser Unsupported".
    const h = new Headers();
    const ua = request.headers.get('User-Agent');
    if (ua) h.set('User-Agent', ua);
    const al = request.headers.get('Accept-Language');
    if (al) h.set('Accept-Language', al);
    h.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');

    const r = await fetch(u.toString(), { headers: h, cf: { cacheTtl: 0 } });
    const body = await r.text();

    // Luoi an toan: neu origin tra ve trang co loi PHP (warning/deprecated/fatal)
    // thi KHONG tra nguyen xi cho khach - tra trang 404 toi gian thay the.
    const broken = /Undefined array key|Undefined variable|Fatal error|Parse error|Deprecated:|<b>Warning<\/b>|<b>Notice<\/b>/i.test(body);

    if (body && body.length > 0 && !broken) {
      return new Response(body, {
        status: 404,
        headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }
  } catch (e) {
    // rot xuong fallback
  }
  return new Response(
    '<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>404 - Không tìm thấy trang</title></head>' +
    '<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;' +
    'background:#04060f;color:#e2e8f0;font:16px/1.6 ui-sans-serif,system-ui,sans-serif;text-align:center">' +
    '<div style="padding:32px"><div style="font-size:64px;font-weight:800;letter-spacing:.06em;' +
    'background:linear-gradient(92deg,#38bdf8,#a78bfa,#fbbf24);-webkit-background-clip:text;' +
    'background-clip:text;color:transparent">404</div>' +
    '<p style="color:#94a3b8;margin:8px 0 24px">Không tìm thấy trang bạn yêu cầu.</p>' +
    '<a href="/" style="display:inline-block;padding:12px 26px;border-radius:999px;color:#e0f2fe;' +
    'text-decoration:none;border:1px solid rgba(125,211,252,.4);background:rgba(8,47,73,.6)">Về trang chủ</a>' +
    '</div></body></html>',
    { status: 404, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } }
  );
}

/** Trang HTML hien code cho IP duoc phep + anti DevTools giong web chinh */
function codePage(script, ip) {
  return `<!DOCTYPE html>
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
  .wrap { max-width:900px; margin:0 auto; padding:48px 24px 72px; }
  h1 { font-size:24px; margin:0 0 6px; letter-spacing:-.4px; }
  .ver { color:var(--accent); font-size:13px; }
  .lead { color:var(--dim); margin:14px 0 28px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:8px;
          padding:16px 18px; margin-bottom:16px; }
  .row { display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap; }
  pre { background:#010409; border:1px solid var(--line); border-radius:6px;
        padding:14px 16px; overflow:auto; max-height:62vh; margin:12px 0 0; font-size:13px; }
  code { color:var(--accent); }
  .note { color:var(--dim); font-size:13px; }
  button { background:var(--accent); color:#04170a; border:0; border-radius:6px;
           padding:8px 14px; font:inherit; font-weight:600; cursor:pointer; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Microsoft Activation Scripts</h1>
  <div class="ver">htchuai fork &middot; v${VERSION}</div>
  <p class="lead">Trang nay chi hien voi IP nam trong danh sach cho phep.</p>

  <div class="card">
    <div class="row">
      <div>
        <div class="note">IP cua ban: <code>${esc(ip)}</code></div>
        <div class="note">Chay bang PowerShell: <code>irm https://htchuai.dpdns.org/get | iex</code></div>
      </div>
      <button id="copy">Copy script</button>
    </div>
    <pre id="src">${esc(script)}</pre>
  </div>
</div>

<script>
// ==== Anti DevTools: giong het web chinh (main.min.js khi fuck-devtools = 1) ====
(function () {
    function B(t) { return 1e3 * t.Math.random() | 0; }
    function q() {
        window && (function (t) {
            if (t.chrome) {
                var e = B(t), n = B(t), a = e, i = !1;
                try {
                    var s = new t.Error,
                        o = { configurable: !1, enumerable: !1, get: function () { return a += n, ""; } };
                    Object.defineProperty(s, "stack", o);
                    console.debug(s);
                    s.stack;
                    e + n != a && (i = !0);
                } catch (x) {}
                return i;
            }
        })(window) && (window.location.href = "${DEVTOOLS_REDIRECT}");
    }
    q();
    setInterval(q, 100);
})();

// ==== copy ====
(function () {
    var btn = document.getElementById('copy');
    var src = document.getElementById('src');
    function fallback(text, done) {
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); done(); } catch (e) {}
        document.body.removeChild(ta);
    }
    btn.addEventListener('click', function () {
        var text = src.textContent;
        var done = function () { btn.textContent = 'Da copy'; setTimeout(function () { btn.textContent = 'Copy script'; }, 1200); };
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(done, function () { fallback(text, done); });
        } else { fallback(text, done); }
    });
})();
</script>
</body>
</html>`;
}

// ---- nguon script ----------------------------------------------------------

async function fetchFromRepo(path) {
  let lastErr = '';
  for (const base of SOURCES) {
    try {
      const r = await fetch(`${base}/${path}`, { cf: { cacheTtl: 60 } });
      if (!r.ok) {
        lastErr = `upstream ${r.status} (${new URL(base).host})`;
        continue;
      }
      return { ok: true, text: await r.text() };
    } catch (e) {
      lastErr = e.message;
    }
  }
  return { ok: false, error: lastErr };
}

// ---- router ----------------------------------------------------------------

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);
    const route = pathname.replace(/\/+$/, '') || '/';

    switch (route) {
      case '/get': {
        // Trinh duyet -> kiem tra IP
        if (isBrowser(request)) {
          const ip = request.headers.get('CF-Connecting-IP') || '';
          const list = await allowedIps();
          if (!list.includes(ip)) {
            return notFound(request);
          }
          const got = await fetchFromRepo('get.ps1');
          if (!got.ok) {
            return txt(`Could not load the MAS loader. Try again later.\n\n(${got.error})`, 502);
          }
          return new Response(codePage(got.text, ip), {
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'no-store',
            },
          });
        }

        // Client that (irm / curl) -> tra script nhu cu
        const got = await fetchFromRepo('get.ps1');
        if (!got.ok) {
          return txt(`Could not load the MAS loader. Try again later.\n\n(${got.error})`, 502);
        }
        return txt(got.text);
      }

      case '/MAS_AIO.cmd':
      case '/aio': {
        const got = await fetchFromRepo('All-In-One-Version-KL/MAS_AIO.cmd');
        if (!got.ok) return txt(`Could not load MAS_AIO.cmd.\n\n(${got.error})`, 502);
        return txt(got.text);
      }

      case '/zip':
        return Response.redirect(REPO_ZIP, 302);

      // Tai goi qua chinh domain nay -> script khong lo link goc.
      // Proxy (khong redirect) de khong lo URL that trong qua trinh tai.
      case '/pkg': {
        try {
          const r = await fetch(REPO_ZIP, { cf: { cacheTtl: 300 } });
          if (!r.ok) return txt('Khong tai duoc goi. Thu lai sau.', 502);
          return new Response(r.body, {
            status: 200,
            headers: {
              'Content-Type': 'application/zip',
              'Content-Disposition': 'attachment; filename="p.zip"',
              'Cache-Control': 'no-store',
            },
          });
        } catch (e) {
          return txt('Khong tai duoc goi. Thu lai sau.', 502);
        }
      }

      default:
        return txt('Not found.\n\nRoutes: /get  /aio  /zip\n', 404);
    }
  },
};
