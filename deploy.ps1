# ============================================================================
#  deploy.ps1 - Deploy MAS htchuai fork lên Cloudflare
#
#  Cách dùng. Mở PowerShell tại thư mục này rồi chạy:
#
#      $env:CF_API_TOKEN = "token-cua-ban"
#      .\deploy.ps1
#
#  Token cần 2 quyền (tạo tại dash.cloudflare.com/profile/api-tokens):
#      Account  ->  Workers Scripts   ->  Edit
#      Zone     ->  Workers Routes    ->  Edit
#      Zone     ->  Zone              ->  Read
# ============================================================================

$ErrorActionPreference = 'Stop'

$AccountId = '6783d1be06b99f51d37827642c3615b6'
$ZoneName  = 'htchuai.dpdns.org'
$ScriptName = 'mas-htchuai'
$Api = 'https://api.cloudflare.com/client/v4'

# ---- check token -----------------------------------------------------------

if (-not $env:CF_API_TOKEN) {
    Write-Host ''
    Write-Host '  Thieu CF_API_TOKEN.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Tao token tai: https://dash.cloudflare.com/profile/api-tokens' -ForegroundColor Yellow
    Write-Host '  -> Create Token -> Custom token, them 3 quyen:' -ForegroundColor Yellow
    Write-Host '       Account | Workers Scripts | Edit' -ForegroundColor Gray
    Write-Host '       Zone    | Workers Routes  | Edit' -ForegroundColor Gray
    Write-Host '       Zone    | Zone            | Read' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Roi chay lai:' -ForegroundColor Yellow
    Write-Host '       $env:CF_API_TOKEN = "..."' -ForegroundColor White
    Write-Host '       .\deploy.ps1' -ForegroundColor White
    Write-Host ''
    exit 1
}

$Headers = @{ Authorization = "Bearer $($env:CF_API_TOKEN)" }

function Invoke-CF {
    param([string]$Method, [string]$Path, $Body, $Form)
    $uri = "$Api$Path"
    try {
        if ($Form) {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers -Form $Form
        } elseif ($Body) {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers `
                -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 12)
        } else {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Headers
        }
    } catch {
        $msg = $_.ErrorDetails.Message
        if (-not $msg) { $msg = $_.Exception.Message }
        throw "CF API $Method $Path failed: $msg"
    }
}

Write-Host ''
Write-Host '  MAS htchuai fork - deploy' -ForegroundColor Green
Write-Host '  ' + ('=' * 50) -ForegroundColor Green
Write-Host ''

# ---- step 1: verify token --------------------------------------------------

Write-Host '  [1/4] Kiem tra token...' -ForegroundColor Cyan
$null = Invoke-CF GET '/user/tokens/verify'
Write-Host '        token hop le' -ForegroundColor DarkGray

# ---- step 2: upload worker -------------------------------------------------

Write-Host '  [2/4] Upload Worker...' -ForegroundColor Cyan

if (-not (Test-Path '.\worker.js')) { throw 'Khong tim thay worker.js' }

$meta = @{
    main_module        = 'worker.js'
    compatibility_date = '2024-11-01'
} | ConvertTo-Json -Compress

# dung curl vi Invoke-RestMethod -Form khong on dinh tren PS 5.1 voi file module
$curl = "curl.exe"
$out = & $curl -s -X PUT "$Api/accounts/$AccountId/workers/scripts/$ScriptName" `
    -H "Authorization: Bearer $($env:CF_API_TOKEN)" `
    -F "metadata=$meta;type=application/json" `
    -F "worker.js=@worker.js;type=application/javascript+module" 2>&1

$res = $out | ConvertFrom-Json
if (-not $res.success) {
    Write-Host "        LOI: $($res.errors | ConvertTo-Json -Compress)" -ForegroundColor Red
    throw 'Upload Worker that bai'
}
Write-Host "        uploaded: $ScriptName" -ForegroundColor DarkGray

# ---- step 3: attach routes --------------------------------------------------
#
#  ⚠️⚠️ KHONG dung "$ZoneName/*" — route do NUOT CA DOMAIN, worker se tra loi
#  moi path va website well-known (dash.php, /tx/, /tx/admin/, /edit/,
#  /admin/dashboard...) CHET NGAY. Chi 5 path duoi day thuoc worker; phan con
#  lai roi xuong tunnel -> localhost:8090 -> Apache.
#
#  ⚠️ /office CO Y KHONG nam trong danh sach — no do well-known phuc vu
#     (well-known\function\mas\office.php). Them route /office se lam worker
#     "che" mat ban cua well-known.
#
#  ⚠️ Danh sach $wanted nay PHAI DONG BO voi:
#       - $wanted trong %LOCALAPPDATA%\PhpStack\fix-mas-route.ps1
#       - `routes` trong wrangler.toml
#
#  Luu y: 2 endpoint "custom domain" deu bi chan voi token dang dung
#  (loi 10405 Method not allowed for this authentication scheme):
#      POST /accounts/{id}/workers/domains
#      POST /accounts/{id}/workers/scripts/{name}/domains/records
#  Nen dung zone-level route - da test chay tot.

Write-Host '  [3/4] Gan zone route...' -ForegroundColor Cyan

$zoneId = (Invoke-CF GET "/zones?name=$ZoneName").result[0].id
if (-not $zoneId) { throw "Khong tim thay zone $ZoneName" }

$wanted = @(
    "$ZoneName/get",
    "$ZoneName/aio",
    "$ZoneName/zip",
    "$ZoneName/MAS_AIO.cmd",
    "$ZoneName/pkg"
)

# xoa route cu KHONG nam trong danh sach (vd route /* con sot lai)
$existing = (Invoke-CF GET "/zones/$zoneId/workers/routes").result
foreach ($r in $existing) {
    if ($wanted -notcontains $r.pattern) {
        Write-Host "        xoa route la: $($r.pattern)" -ForegroundColor Yellow
        $null = Invoke-CF DELETE "/zones/$zoneId/workers/routes/$($r.id)"
    }
}

# tao route con thieu
$existing = (Invoke-CF GET "/zones/$zoneId/workers/routes").result
foreach ($pat in $wanted) {
    if ($existing | Where-Object { $_.pattern -eq $pat }) {
        Write-Host "        da co: $pat" -ForegroundColor DarkGray
        continue
    }
    $res = Invoke-CF POST "/zones/$zoneId/workers/routes" @{ pattern = $pat; script = $ScriptName }
    Write-Host "        them: $($res.result.pattern) -> $($res.result.script)" -ForegroundColor DarkGray
}

Write-Host '        --- ket qua cuoi ---' -ForegroundColor DarkGray
(Invoke-CF GET "/zones/$zoneId/workers/routes").result |
    ForEach-Object { Write-Host ("        {0,-42} -> {1}" -f $_.pattern, $_.script) -ForegroundColor DarkGray }

# ---- step 4: test ----------------------------------------------------------

Write-Host '  [4/4] Test endpoint...' -ForegroundColor Cyan
Start-Sleep -Seconds 4

$allOk = $true
foreach ($t in @('/get', '/office')) {
    try {
        $r = Invoke-WebRequest -Uri "https://$ZoneName$t" -UseBasicParsing -TimeoutSec 30
        $good = $r.Content -match 'MAS|OFFICE|LEHUY'
        if (-not $good) { $allOk = $false }
        Write-Host ("        GET {0,-9} -> HTTP {1}  ({2} bytes) {3}" -f $t, $r.StatusCode, $r.Content.Length, $(if ($good) { 'OK' } else { 'NOI DUNG BAT THUONG' })) -ForegroundColor DarkGray
    } catch {
        $allOk = $false
        Write-Host ("        GET {0,-9} -> LOI: {1}" -f $t, $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

# QUAN TRONG: xac nhan website well-known van song (route /* khong duoc lot vao)
try {
    $h = Invoke-WebRequest -Uri "https://$ZoneName/dash.php" -UseBasicParsing -TimeoutSec 30
    Write-Host ("        GET /dash.php -> HTTP {0}  ({1} bytes) - website OK" -f $h.StatusCode, $h.Content.Length) -ForegroundColor DarkGray
} catch {
    Write-Host '        [!] WEBSITE WELL-KNOWN KHONG TRA LOI!' -ForegroundColor Red
    Write-Host '            Kiem tra lai route - co the da bi dat thanh htchuai.dpdns.org/*' -ForegroundColor Red
    $allOk = $false
}

Write-Host ''
if ($allOk) {
    Write-Host '  THANH CONG' -ForegroundColor Green
    Write-Host ''
    Write-Host '    irm https://htchuai.dpdns.org/get    | iex    (Windows)' -ForegroundColor White
    Write-Host '    irm https://htchuai.dpdns.org/office | iex    (Office)' -ForegroundColor White
    Write-Host ''
} else {
    Write-Host '  CO LOI - xem thong bao phia tren' -ForegroundColor Red
    Write-Host ''
}
