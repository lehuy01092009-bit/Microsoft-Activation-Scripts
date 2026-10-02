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
| **Push lên GitHub** | ⏳ Còn lại — cần bạn |

### Trạng thái đã deploy

```
Worker:   mas-htchuai
Route:    htchuai.dpdns.org/*  ->  mas-htchuai
workers.dev: mas-htchuai.lehuy01092009.workers.dev

GET /      -> HTTP 200  (landing page)
GET /nope  -> HTTP 404  (đúng)
GET /get   -> 502 (upstream 404)  <- CHỜ REPO GITHUB
```

`/get` trả 502 vì worker fetch `get.ps1` từ GitHub — repo chưa tồn tại.
Push repo xong là endpoint tự chạy, **không cần deploy lại worker**.

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

## Bước 3 — Push lên GitHub (**việc còn lại duy nhất**)

Worker fetch `get.ps1` từ `raw.githubusercontent.com/htchuai/Microsoft-Activation-Scripts/master`.
Cần repo public đúng path đó.

1. Tạo repo **public** tên `Microsoft-Activation-Scripts` tại https://github.com/new
   (không tick README/gitignore — repo đã có sẵn)

2. Push:

```bash
cd "C:/Users/lehuy/Downloads/Microsoft-Activation-Scripts-master/Microsoft-Activation-Scripts-master/MAS"

git remote add origin https://github.com/htchuai/Microsoft-Activation-Scripts.git
git push -u origin master
```

Lần push đầu sẽ hỏi đăng nhập — dùng **Personal Access Token** của GitHub
(Settings → Developer settings → Tokens (classic) → `repo` scope) làm password.

3. Verify:

```powershell
curl.exe -s https://raw.githubusercontent.com/htchuai/Microsoft-Activation-Scripts/master/get.ps1 | Select-Object -First 3
```

Nếu repo của bạn dùng tên user khác `htchuai`, sửa `REPO_RAW` trong `worker.js`
rồi deploy lại.

---

## Bước 4 — Test toàn bộ

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
| `/` | Landing page (dark theme, có lệnh chạy) |
| `/get` | `get.ps1` — dùng cho `irm ... \| iex` |
| `/aio` hoặc `/MAS_AIO.cmd` | `MAS_AIO.cmd` trực tiếp |
| `/zip` | Redirect 302 → ZIP của repo |

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
