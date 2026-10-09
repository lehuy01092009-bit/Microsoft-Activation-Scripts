@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo   DEPLOY WORKER MAS len Cloudflare
echo   (chay 1 lan sau moi khi sua worker.js)
echo ============================================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [LOI] Khong tim thay Node.js. Cai Node.js truoc: https://nodejs.org
  pause
  exit /b 1
)

echo [1/2] Dang nhap Cloudflare (neu chua dang nhap, trinh duyet se mo ra)
echo       -> Bam "Allow" tren trang vua mo.
echo.
call npx --yes wrangler@latest login
if errorlevel 1 (
  echo.
  echo [LOI] Dang nhap that bai.
  pause
  exit /b 1
)

echo.
echo [2/2] Dang deploy worker "mas-htchuai"...
echo.
call npx --yes wrangler@latest deploy
if errorlevel 1 (
  echo.
  echo [LOI] Deploy that bai. Xem thong bao phia tren.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   XONG! Worker da duoc cap nhat.
echo   Thu lai:  irm https://htchuai.dpdns.org/get ^| iex
echo ============================================================
pause
