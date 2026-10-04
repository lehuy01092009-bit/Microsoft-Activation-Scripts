# MAS htchuai fork — Deploy lên htchuai.dpdns.org

## Trạng thái

| Việc | Trạng thái |
|---|---|
| Rebrand 10 file `.cmd` + readme sang `htchuai.dpdns.org` | ✅ Xong |
| Tắt update-check ping về `massgrave.dev` | ✅ Xong |
| Tạo `get.ps1` (loader cho `/get`) | ✅ Xong |
| Tạo `worker.js` + `wrangler.toml` | ✅ Xong |
| Test worker chạy local | ✅ Xong (`/` → 200, `/nope` → 404) |
| Init git repo + commit | ✅ Xong (4 commit) |
| Verify CRLF sống sót qua clone | ✅ Xong |
| Tạo `deploy.ps1` | ✅ Xong |
| **Upload Worker lên Cloudflare** | ✅ **XONG** — `mas-htchuai` |
| **Gắn domain htchuai.dpdns.org** | ✅ **XONG** — HTTP 200, hết lỗi 530 |
| **Push lên GitHub** | ✅ **XONG** — `lehuy01092009-bit/Microsoft-Activation-Scripts` |
| **Test end-to-end** | ✅ **XONG** — cả 5 route đều đúng |

## Lệnh đã chạy được

```powershell
irm https://htchuai.dpdns.org/get | iex
```

### Trạng thái đã deploy

```
Worker:   mas-htchuai
Route:    htchuai.dpdns.org/*  ->  mas-htchuai
workers.dev: mas-htchuai.lehuy01092009.workers.dev
Repo:     github.com/lehuy01092009-bit/Microsoft-Activation-Scripts (public)

GET /      -> HTTP 200            landing page
GET /get   -> HTTP 200  4121 B    loader (PowerShell)
GET /aio   -> HTTP 200  742984 B  MAS_AIO.cmd
GET /zip   -> HTTP 302            -> codeload.github.com/.../master.zip
GET /nope  -> HTTP 404
```

Verify ZIP: 24 file, `MAS_AIO.cmd` giữ **CRLF=19223, bareLF=0** → chạy được sau khi tải.

### ⚠️ Lưu ý về username

Username GitHub thật là **`lehuy01092009-bit`** — KHÔNG phải `htchuai` (account đó
không tồn tại). Danh xưng `htchuai` chỉ dùng làm tên brand/domain, không phải tài khoản.

### ⚠️ Cache của raw.githubusercontent.com

Sau khi push, `raw.githubusercontent.com` vẫn trả bản cũ khoảng **5 phút** (CDN cache,
không purge được bằng token hiện tại). Nếu vừa push mà worker còn trả nội dung cũ —
đó là lý do, không phải lỗi.

`worker.js` xử lý sẵn: dùng **jsDelivr trước, raw GitHub làm fallback**:

```js
const SOURCES = [
  'https://cdn.jsdelivr.net/gh/lehuy01092009-bit/Microsoft-Activation-Scripts@master',
  'https://raw.githubusercontent.com/lehuy01092009-bit/Microsoft-Activation-Scripts/master',
];
```

Push xong muốn thấy ngay, purge jsDelivr:

```
https://purge.jsdelivr.net/gh/lehuy01092009-bit/Microsoft-Activation-Scripts@master/get.ps1
```

---

## Ghi chú hạ tầng

**Đã xác minh:** zone `htchuai.dpdns.org` active, account
`6783d1be06b99f51d37827642c3615b6`, zone `03ed913c4a9d899e40f0651218b52035`.

### Ghi chú về token

Token `~/.cloudflared/cert.pem` là **Argo Tunnel token** — không deploy được.
Token API mới (đã dùng) deploy + tạo route OK, **nhưng** 2 endpoint
gắn custom domain bị chặn `10405 Method not allowed for this authentication scheme`:

- `POST /accounts/{id}/workers/domains`
- `POST /accounts/{id}/workers/scripts/{name}/domains/records`

Cách vượt: dùng **zone-level route** thay vì custom domain — chạy tốt:

```
POST /zones/{zone_id}/workers/routes
{"pattern":"htchuai.dpdns.org/*","script":"mas-htchuai"}
```

Route ở tầng edge nên **không cần DNS record** — để trống là đúng.

---

## Cập nhật nội dung sau này (đã push repo rồi)

Workflow chuẩn mỗi lần sửa:

```bash
cd "C:/Users/lehuy/Downloads/Microsoft-Activation-Scripts-master/Microsoft-Activation-Scripts-master/MAS"

# 1. Sua file, nho convert CRLF cho .cmd/.ps1 (xem cuoi file nay)

# 2. Commit + push
git add -A
git commit -m "mo ta thay doi"
git push

# 3. Purge jsDelivr de thay ngay (khong bat buoc, tu het sau ~12h)
curl.exe "https://purge.jsdelivr.net/gh/lehuy01092009-bit/Microsoft-Activation-Scripts@master/get.ps1"
```

**Chỉ cần deploy lại worker khi sửa `worker.js`.** Sửa `get.ps1` / `.cmd` thì push là đủ.

---

## Test toàn bộ

```powershell
# Test 1: trang landing
curl.exe -s https://htchuai.dpdns.org/

# Test 2: endpoint loader
curl.exe -s https://htchuai.dpdns.org/get | Select-Object -First 5

# Test 3: chạy thật (mở PowerShell MỚI, KHÔNG chạy as Admin)
irm https://htchuai.dpdns.org/get | iex
```

Test 3 sẽ tự xin quyền admin → tải ZIP → mở menu MAS.
Kiểm tra: title cửa sổ hiện `Microsoft Activation Scripts 3.12-htchuai (htchuai fork)`
và **không** có dòng "Your version of MAS is outdated".

---

## Route của Worker

| Route | Trả về |
|---|---|
| `/get` | Xem bảng bên dưới |
| `/aio` hoặc `/MAS_AIO.cmd` | `MAS_AIO.cmd` trực tiếp |
| `/zip` | Redirect 302 → ZIP của repo |

### `/get` — phân biệt theo client và theo IP (2026-10-04)

```
/get
├─ request KHÔNG phải trình duyệt (Accept không có text/html)
│    → trả script get.ps1 (text/plain). Khách `irm ... | iex` chạy bình thường,
│      chỉ cần key (xem mục Key bên dưới).
└─ request từ TRÌNH DUYỆT (Accept có text/html)
     ├─ IP nằm trong danh sách cho phép → trang HTML hiện code + anti DevTools
     └─ IP khác → 404 (lấy nguyên trang 404 thật của web chính)
```

**Cách nhận diện trình duyệt:** `Accept` chứa `text/html`. PowerShell `irm` và `curl`
không bao giờ gửi giá trị này → khách không bị chặn oan. Có thêm lớp chặn phụ:
UA chứa `powershell|curl|wget|python|libwww|httpclient|winhttp` thì luôn coi là client thật.

**Danh sách IP** lấy từ `https://htchuai.dpdns.org/api/mas/ips?k=<token>`, worker cache
60 giây trong bộ nhớ. Nếu API lỗi thì giữ danh sách cũ (không tự khoá hết người dùng).
Thêm/xoá IP tại **Admin → Quản Lý Key MAS → khối "IP được xem code"**.

⚠️ Đổi `MAS_IP_TOKEN` phải sửa **cả hai** nơi:
`worker.js` và `app/ajax/global/default/mas-ips.php`.

**Anti DevTools** trong trang HTML là bản copy nguyên văn từ `main.min.js` của web chính
(khi `fuck-devtools = 1`): dùng trick getter `Error.stack` để phát hiện Chrome DevTools,
phát hiện thì `window.location.href = "//t.me/ThanhPhucDev"`, chạy `setInterval(q, 100)`.

### Deploy lại worker

Sửa `worker.js` thì **phải deploy lại** (không như `get.ps1` chỉ cần push + purge jsDelivr):

```powershell
$env:CF_API_TOKEN = "..."
.\deploy.ps1
```

hoặc gọi thẳng API:

```bash
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/6783d1be06b99f51d37827642c3615b6/workers/scripts/mas-htchuai" \
  -H "Authorization: Bearer $TOKEN" \
  -F 'metadata={"main_module":"worker.js","compatibility_date":"2024-11-01"};type=application/json' \
  -F 'worker.js=@worker.js;type=application/javascript+module'
```

Test logic worker trước khi deploy: copy `worker.js` → `_w.mjs`, viết harness `.mjs` gọi
`worker.fetch(new Request(url, { headers: { 'CF-Connecting-IP': '1.2.3.4', ... } }))`.
Mock được `CF-Connecting-IP` nên test được cả nhánh 404 mà không cần đổi IP thật.

---

## ⚠️ CRLF — đọc trước khi sửa file

`MAS_AIO.cmd` có check cứng ở đầu: nếu file dùng **LF thì abort ngay**.
Tool edit tự động ghi LF là phá script.

`.gitattributes` đã ép `*.cmd text eol=crlf` nên clone/push an toàn.
Nhưng khi sửa file bằng editor, luôn verify:

```powershell
python -c "
import glob
fs=(glob.glob('All-In-One-Version-KL/*.cmd')+glob.glob('Separate-Files-Version/*.cmd')+glob.glob('Separate-Files-Version/Activators/*.cmd'))
bad=[f for f in fs if (lambda d: d.count(b'\n')-d.count(b'\r\n') or not d.endswith(b'\r\n'))(open(f,'rb').read())]
print('BAD:', bad if bad else 'none - all CRLF OK')"
```

Script convert nếu cần:

```python
import glob
files = (glob.glob('All-In-One-Version-KL/*.cmd') +
         glob.glob('Separate-Files-Version/*.cmd') +
         glob.glob('Separate-Files-Version/Activators/*.cmd') +
         ['get.ps1', 'deploy.ps1'])
for f in files:
    d = open(f, 'rb').read()
    d = d.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    if not d.endswith(b'\r\n'):
        d += b'\r\n'
    open(f, 'wb').write(d)
```

---

## ⚠️ KHÔNG được sửa — salt mật mã

Bốn dòng này trông như branding nhưng là **dữ liệu mật mã**, sửa là hỏng activation:

```
All-In-One-Version-KL/MAS_AIO.cmd:8218      Encoding.UTF8.GetBytes("massgrave.dev :3")
All-In-One-Version-KL/MAS_AIO.cmd:9075      ValueAsStr = "massgrave.dev"
Separate-Files-Version/Activators/TSforge_Activation.cmd:5827
Separate-Files-Version/Activators/TSforge_Activation.cmd:6684
```

Đã thêm comment `Must NOT be changed` ngay trên đó.

---

## License

MAS gốc: **GPL-3.0** → fork **bắt buộc** public source, giữ credit gốc
(WindowsAddict, @abbodi1406). Repo public vừa là yêu cầu kỹ thuật (worker fetch raw)
vừa là yêu cầu pháp lý — trùng nhau, tiện.

Ngoài phạm vi code: công cụ này kích hoạt bản quyền Windows/Office, phân phối nó
vi phạm ToS của Microsoft — độc lập với license GPL.
