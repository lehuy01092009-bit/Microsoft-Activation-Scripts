# MAS - htchuai fork

Fork cá nhân của [Microsoft Activation Scripts](https://github.com/massgravel/Microsoft-Activation-Scripts) (GPL-3.0).

## Chạy

```powershell
irm https://htchuai.dpdns.org/get | iex
```

## Cấu trúc

| File | Mô tả |
|---|---|
| `All-In-One-Version-KL/MAS_AIO.cmd` | Script gộp tất cả tính năng |
| `Separate-Files-Version/` | Bản tách rời từng công cụ |
| `get.ps1` | Loader — nội dung endpoint `/get` |
| `worker.js` | Cloudflare Worker phục vụ domain |
| `wrangler.toml` | Config deploy Worker |
| `HUONG-DAN-FORK.md` | Hướng dẫn rebrand + deploy chi tiết |

## Deploy Worker

```bash
npx wrangler deploy
```

## License

Kế thừa **GPL-3.0** từ MAS gốc. Source phải public.
Credit gốc: WindowsAddict, @abbodi1406 và cộng đồng MAS.

## Lưu ý kỹ thuật

- File `.cmd` **bắt buộc CRLF** — script MAS abort nếu phát hiện LF.
- **KHÔNG** sửa 2 salt mật mã: `MAS_AIO.cmd:8218` và `:9075` (`"massgrave.dev :3"` / `ValueAsStr = "massgrave.dev"`).
  Đây là dữ liệu mật mã cho KMS binding, không phải branding — sửa là hỏng activation.
