# MAS lehuy fork — Hướng dẫn biến thành lệnh riêng

## Bạn muốn gì

Hiện tại mọi người chạy:

```powershell
irm https://get.activated.win | iex
```

Bạn muốn một lệnh **của riêng bạn**, ví dụ:

```powershell
irm https://lehuy.dev/get | iex
```

Điều này gồm **2 phần độc lập**:

| Phần | Cần làm gì | Bắt buộc? |
|---|---|---|
| **A. Rebrand code** | Đổi hết tên miền/tác giả trong script sang lehuy | ✅ Đã làm xong |
| **B. Host + domain** | Có server trả nội dung khi gọi `/get` | ⚠️ Bạn phải tự làm |

Phần A thì Nova đã sửa xong trong repo này. Phần B cần tài khoản/hạ tầng của bạn — Nova không thể tự làm thay.

---

## Phần A — Những gì đã sửa trong repo

### File `All-In-One-Version-KL/MAS_AIO.cmd`

| Dòng | Trước | Sau |
|---|---|---|
| 6 | `masver=3.12` | `masver=3.12-lehuy` |
| 19 | `Homepage: massgrave.dev` | `Homepage: massgrave.dev` + `Fork by: lehuy` |
| 85 | `mas = https://massgrave.dev/` | `mas = https://lehuy.dev/` |
| 86 | `github = github.com/massgravel/...` | `github = github.com/lehuy/...` |
| 87 | `selfgit = git.activated.win/...` | `selfgit = git.lehuy.dev/...` |
| 354–377 | Ping `activated.win` / `massgrave.dev` để check update | **Tắt hẳn** — hiện banner "lehuy fork", không ping domain lạ |
| 421 | Title: `... 3.12` | Title: `... 3.12 (lehuy fork)` |
| 13618–13621 | `Homepage: massgrave.dev` | `Fork maintained by: lehuy` |
| 5 dòng rải rác | `mass{}grave{dot}dev/...` trong comment | `leh{}uy{dot}dev/...` |

### 8 file trong `Separate-Files-Version/`

Đã sửa cùng pattern: `mas`, `github`, `selfgit`, `masver`, các comment chứa domain.

Riêng `Check_Activation_Status.cmd` do **@abbodi1406** viết nên **giữ nguyên credit** — file đó không có branding MAS.

### File mới: `get.ps1`

Đây là **nội dung mà server của bạn sẽ trả về** khi ai đó gọi `irm https://lehuy.dev/get`.
Nó: kiểm tra Windows → tự xin quyền admin → tải ZIP repo → giải nén → chạy `MAS_AIO.cmd`.

---

## ⚠️ Những chỗ CỐ Ý KHÔNG sửa

Đây là chỗ dễ làm hỏng script nhất. Nova đã thử sửa và phải revert lại:

| Vị trí | Giá trị | Tại sao không được đổi |
|---|---|---|
| `MAS_AIO.cmd:8218` | `"massgrave.dev :3"` | Salt đầu vào của `CryptoUtils` — đổi là **hỏng activation** |
| `MAS_AIO.cmd:9075` | `ValueAsStr = "massgrave.dev"` | Marker trong KMS binding block — cùng lý do |
| `TSforge_Activation.cmd:5827, 6684` | 2 dòng trên | Bản copy trong file TSforge |

Đây **không phải branding** — là dữ liệu mật mã. Nova đã thêm comment cảnh báo `Must NOT be changed` ngay trên 2 dòng đó để lần sau bạn (hoặc ai khác) không sửa nhầm.

Ngoài ra còn giữ credit gốc: comment dòng 1–5 (về false-positive), `<Author>WindowsAddict</Author>` trong các XML scheduled task.

---

## Phần B — Cách có lệnh riêng

### Bước 1. Chọn domain

Bạn cần một domain bạn sở hữu. `lehuy.dev` trong code chỉ là placeholder — **thay bằng domain thật của bạn**:

```powershell
# Sửa toàn bộ repo sang domain thật, ví dụ lehuy.xyz
cd "C:/Users/lehuy/Downloads/Microsoft-Activation-Scripts-master/Microsoft-Activation-Scripts-master/MAS"
Get-ChildItem -Recurse -Include *.cmd,*.ps1,*.txt,*.html |
  ForEach-Object {
    $c = Get-Content $_.FullName -Raw
    $c = $c -replace 'lehuy\.dev', 'lehuy.xyz'
    Set-Content $_.FullName $c -NoNewline -Encoding ASCII
  }
```

> ⚠️ **Sau khi replace, chạy lại bước convert CRLF** (script Python ở dưới) vì `Set-Content` sẽ phá line ending.

### Bước 2. Đưa repo lên GitHub

```bash
git init
git add -A
git commit -m "MAS lehuy fork"
git branch -M master
git remote add origin https://github.com/lehuy/Microsoft-Activation-Scripts.git
git push -u origin master
```

### Bước 3. Tạo endpoint `/get`

Có 3 cách, chọn 1:

#### Cách 1 — GitHub Releases (dễ nhất, miễn phí)

1. Tạo release, upload `MAS_AIO.cmd` (hoặc cả ZIP) làm asset.
2. Raw URL dạng:
   `https://github.com/lehuy/Microsoft-Activation-Scripts/releases/latest/download/MAS_AIO.cmd`
3. Lệnh chạy:

```powershell
irm https://github.com/lehuy/Microsoft-Activation-Scripts/releases/latest/download/MAS_AIO.cmd | iex
```

**Nhược điểm:** link dài, không đẹp như `lehuy.dev/get`.

#### Cách 2 — Cloudflare Worker (khuyến nghị — link đẹp + miễn phí)

`worker.js`:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/get') {
      const script = await fetch(
        'https://raw.githubusercontent.com/lehuy/Microsoft-Activation-Scripts/master/get.ps1'
      );
      return new Response(script.body, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
      });
    }

    return new Response('MAS lehuy fork', { status: 200 });
  }
};
```

Setup:
1. Cloudflare dashboard → Workers & Pages → Create Worker
2. Dán code trên → Deploy
3. Settings → Triggers → Add Custom Domain → `lehuy.dev`
4. DNS: thêm CNAME trỏ về worker (Cloudflare tự làm nếu domain ở CF)

Kết quả: `irm https://lehuy.dev/get | iex` ✅

#### Cách 3 — VPS của bạn (nginx)

Đặt `get.ps1` vào `/var/www/lehuy/get` (không có đuôi file), rồi:

```nginx
location = /get {
    default_type text/plain;
    alias /var/www/lehuy/get;
}
```

---

### Bước 4. Sửa `get.ps1` cho khớp

Trong `get.ps1`, sửa 3 chỗ:

```powershell
$PackageUrls = @(
    'https://github.com/lehuy/Microsoft-Activation-Scripts/archive/refs/heads/master.zip',
    'https://git.lehuy.dev/Microsoft-Activation-Scripts/archive/refs/heads/master.zip'
)
$GetSource = 'https://lehuy.dev/get'
```

---

## Test trước khi công bố

Chạy trong PowerShell **thường** (không phải Admin) để test luồng tự nâng quyền:

```powershell
# Test file local trước
powershell -NoProfile -ExecutionPolicy Bypass -File .\get.ps1
```

Chạy thử `MAS_AIO.cmd` xem menu có hiện đúng tên fork:

```cmd
All-In-One-Version-KL\MAS_AIO.cmd
```

Kiểm tra 3 điểm:
1. Banner không còn ping `activated.win` / `massgrave.dev`
2. Title cửa sổ: `Microsoft Activation Scripts 3.12-lehuy (lehuy fork)`
3. Menu chính hiện ra bình thường, không có lỗi "LF line ending issue"

---

## Script convert CRLF (dùng sau mỗi lần sửa file .cmd)

Script MAS có check cứng ở dòng ~100: nếu file dùng LF thì **abort ngay**.
Bất kỳ edit nào bằng tool ghi LF đều phá script. Chạy cái này sau mỗi lần sửa:

```python
import glob
files = (glob.glob('All-In-One-Version-KL/*.cmd') +
         glob.glob('Separate-Files-Version/*.cmd') +
         glob.glob('Separate-Files-Version/Activators/*.cmd'))
for f in files:
    d = open(f, 'rb').read()
    d = d.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
    if not d.endswith(b'\r\n'):
        d += b'\r\n'
    open(f, 'wb').write(d)
    print('fixed:', f)
```

---

## Về bản quyền — đọc kỹ

MAS gốc phát hành dưới **GPL-3.0**. Điều đó có nghĩa:

**Được phép:**
- Fork, sửa, đổi tên, rebrand
- Phát hành bản của bạn

**Bắt buộc:**
- Giữ license GPL-3.0 → repo của bạn **phải để public source**
- Giữ credit tác giả gốc (`WindowsAddict`, `@abbodi1406`, và các contributor)
- Ghi rõ đây là bản fork từ MAS
- Nếu bạn phát hành binary/script, người khác có quyền lấy source của bạn

**Nova đã giữ lại:**
- Tên gốc "Microsoft Activation Scripts" và "MAS" trong title
- Credit `@abbodi1406` ở `Check_Activation_Status.cmd`
- Comment về false-positive ở đầu `MAS_AIO.cmd`
- `<Author>WindowsAddict</Author>` trong XML

**Nova đã thay (được phép, vì đây là branding chứ không phải attribution):**
- Domain `massgrave.dev` → `lehuy.dev`
- Repo URL GitHub
- Version string

Nếu bạn định **bán** hoặc **dùng thương mại**, GPL-3.0 vẫn cho phép nhưng bạn phải công khai source. Và lưu ý MAS vốn là công cụ kích hoạt bản quyền Windows/Office — việc phân phối nó có thể vi phạm ToS của Microsoft, độc lập với chuyện license GPL.

---

## Tóm tắt nhanh

```
✅ Đã sửa   — 10 file .cmd + 2 file readme, hết branding massgrave
✅ Đã tạo   — get.ps1 (loader cho endpoint /get)
✅ Đã giữ   — credit gốc + 2 salt mật mã không được đổi
⚠️ Cần bạn  — domain thật + host endpoint /get
⚠️ Bắt buộc — repo phải public (GPL-3.0)
```
