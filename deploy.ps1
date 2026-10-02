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

# ---- step 3: attach route ---------------------------------------------------
#
#  Luu y: 2 endpoint "custom domain" deu bi chan voi token dang dung
#  (loi 10405 Method not allowed for this authentication scheme):
#      POST /accounts/{id}/workers/domains
#      POST /accounts/{id}/workers/scripts/{name}/domains/records
#  Nen dung zone-level route - da test chay tot.

Write-Host '  [3/4] Gan zone route...' -ForegroundColor Cyan

$zoneId = (Invoke-CF GET "/zones?name=$ZoneName").result[0].id
if (-not $zoneId) { throw "Khong tim thay zone $ZoneName" }

# xoa route cu cung pattern (neu co) de tranh trung
$existing = (Invoke-CF GET "/zones/$zoneId/workers/routes").result |
            Where-Object { $_.pattern -eq "$ZoneName/*" }
foreach ($r in $existing) {
    $null = Invoke-CF DELETE "/zones/$zoneId/workers/routes/$($r.id)"
}

$route = Invoke-CF POST "/zones/$zoneId/workers/routes" @{
    pattern = "$ZoneName/*"
    script  = $ScriptName
}
Write-Host "        route: $($route.result.pattern) -> $($route.result.script)" -ForegroundColor DarkGray
Write-Host '        (route o tang edge nen khong can DNS record)' -ForegroundColor DarkGray

# ---- step 4: test ----------------------------------------------------------

Write-Host '  [4/4] Test endpoint...' -ForegroundColor Cyan
try {
    $t = Invoke-WebRequest -Uri "https://$ZoneName/get" -UseBasicParsing -TimeoutSec 25
    Write-Host "        GET /get -> HTTP $($t.StatusCode), $($t.Content.Length) bytes" -ForegroundColor DarkGray
    if ($t.Content -match 'MAS') {
        Write-Host ''
        Write-Host '  THANH CONG' -ForegroundColor Green
        Write-Host ''
        Write-Host '    irm https://htchuai.dpdns.org/get | iex' -ForegroundColor White
        Write-Host ''
    } else {
        Write-Host '        canh bao: noi dung tra ve bat thuong' -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "        chua truy cap duoc: $($_.Exception.Message)" -ForegroundColor DarkYellow
    Write-Host '        co the DNS chua propagate - doi 1-2 phut roi thu lai' -ForegroundColor DarkYellow
}
