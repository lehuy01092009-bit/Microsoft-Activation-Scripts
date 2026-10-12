# ============================================================================
#  verify-deploy.ps1 — kiem tra worker MAS sau khi deploy
#
#  Kiem tra 3 thu:
#    1. /get     -> phai tra script (HTTP 200)
#    2. /office  -> phai tra script (HTTP 200)
#    3. /dash.php -> website well-known phai CON SONG
#       (neu chet => route da bi dat thanh htchuai.dpdns.org/* -> phai sua ngay)
#
#  Cach dung:  powershell -NoProfile -ExecutionPolicy Bypass -File verify-deploy.ps1
# ============================================================================

$ZoneName = 'htchuai.dpdns.org'
$ok = $true

# Tat thanh tien do cua Invoke-WebRequest (rat on ao trong console)
$ProgressPreference = 'SilentlyContinue'

Write-Host ''
Write-Host '  Kiem tra worker' -ForegroundColor Cyan
Write-Host ('  ' + ('=' * 52)) -ForegroundColor Cyan

foreach ($p in @('/get', '/office')) {
    try {
        $r = Invoke-WebRequest -Uri "https://$ZoneName$p" -UseBasicParsing -TimeoutSec 30
        $good = $r.Content -match 'LEHUY|OFFICE|MAS'
        if (-not $good) { $ok = $false }
        Write-Host ("  {0,-10} HTTP {1}  ({2} bytes)  {3}" -f $p, $r.StatusCode, $r.Content.Length, $(if ($good) { 'OK' } else { 'NOI DUNG BAT THUONG' })) -ForegroundColor $(if ($good) { 'Green' } else { 'Red' })
    } catch {
        $ok = $false
        Write-Host ("  {0,-10} LOI: {1}" -f $p, $_.Exception.Message) -ForegroundColor Red
    }
}

# QUAN TRONG: route /* se giet website. Luon kiem tra.
try {
    $h = Invoke-WebRequest -Uri "https://$ZoneName/dash.php" -UseBasicParsing -TimeoutSec 30
    Write-Host ("  {0,-10} HTTP {1}  ({2} bytes)  website OK" -f '/dash.php', $h.StatusCode, $h.Content.Length) -ForegroundColor Green
} catch {
    $ok = $false
    Write-Host '  /dash.php  WEBSITE WELL-KNOWN KHONG TRA LOI!' -ForegroundColor Red
    Write-Host '             => route co the da bi dat thanh htchuai.dpdns.org/*' -ForegroundColor Red
    Write-Host '             => chay: %LOCALAPPDATA%\PhpStack\fix-mas-route.ps1' -ForegroundColor Yellow
}

Write-Host ''
if ($ok) {
    Write-Host '  TAT CA OK' -ForegroundColor Green
} else {
    Write-Host '  CO LOI - xem thong bao phia tren' -ForegroundColor Red
}
Write-Host ''
