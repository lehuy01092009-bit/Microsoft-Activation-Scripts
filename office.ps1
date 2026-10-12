# ============================================================================
#  KÍCH HOẠT OFFICE — HTCHUAI.DPDNS.ORG
#  Bản quyền © lehuy
#
#  Cách dùng (PowerShell):
#
#      irm https://htchuai.dpdns.org/office | iex
#
#  Các lệnh có thể dùng khi được hỏi:
#      /Ohook            kích hoạt Office
#      /Ohook-Uninstall  gỡ kích hoạt Office
#      /HWID             kích hoạt Windows
#      /Z-               kích hoạt Windows / ESU (TSforge)
#      (bỏ trống + Enter = kích hoạt Office)
#
#  Script sẽ hỏi KEY và LỆNH ngay tại cửa sổ này, rồi mới mở cửa sổ Admin để chạy.
#  Dùng CHUNG key với bản kích hoạt Windows (/get) — không cần key riêng.
#  Chạy không hỏi (tự động): đặt $env:MAS_KEY trước khi chạy.
# ============================================================================

$ErrorActionPreference = 'Stop'

# ---- hiển thị tiếng Việt đúng trên console -----------------------------------
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    $OutputEncoding           = New-Object System.Text.UTF8Encoding $false
} catch { }

# ---- config -----------------------------------------------------------------
$ForkName  = 'KÍCH HOẠT OFFICE — BẢN QUYỀN LEHUY'
$CopyRight = '© lehuy · htchuai.dpdns.org'
$GetSource = 'https://htchuai.dpdns.org/office'
$KeyApi    = 'https://htchuai.dpdns.org/api/mas/key'
$KeyStore  = Join-Path $env:LOCALAPPDATA 'MAS_htchuai\key.txt'
$Handoff   = Join-Path $env:LOCALAPPDATA 'MAS_htchuai\office-run.txt'
$WorkDir   = Join-Path $env:SystemRoot 'Temp\MAS_htchuai_office'
$Default   = '/Ohook'
$Package   = @(
    'https://htchuai.dpdns.org/pkg'
)
# -----------------------------------------------------------------------------

$Stage = [string]$env:MAS_STAGE          # 'run' = cửa sổ Admin, không hỏi lại

function Write-Banner($text, $color = 'Green') {
    Write-Host ''
    Write-Host ('  ' + '=' * 60) -ForegroundColor $color
    Write-Host ('    ' + $text) -ForegroundColor $color
    Write-Host ('  ' + '=' * 60) -ForegroundColor $color
    Write-Host ''
}

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal(
            [Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- HWID (chỉ gửi hash, không gửi UUID gốc) --------------------------------

function Get-MasHWID {
    $raw = $null
    try { $raw = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
    if (-not $raw) { try { $raw = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber } catch { } }
    if (-not $raw) { $raw = $env:COMPUTERNAME }
    $raw = ([string]$raw).Trim().ToUpper()
    if (-not $raw) { $raw = 'UNKNOWN' }
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

# ---- kiểm tra key -----------------------------------------------------------

function Invoke-MasKeyCheck([string]$Key) {
    try {
        return Invoke-RestMethod -Uri $KeyApi -Method Post -TimeoutSec 30 -Body @{
            key  = $Key
            hwid = (Get-MasHWID)
        }
    } catch {
        return [pscustomobject]@{
            ok   = $false
            code = 'network'
            msg  = 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.'
        }
    }
}

# ---- environment ------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

if ([Environment]::OSVersion.Version.Build -lt 9600) {
    Write-Host '  Cần Windows 8.1 trở lên để kích hoạt Office.' -ForegroundColor Red
    return
}
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host '  Cần dùng Windows PowerShell 5.1 (không phải PowerShell Core).' -ForegroundColor Red
    return
}

# ---- cửa sổ Admin đọc lại key/lệnh do cửa sổ trước bàn giao -----------------
# Chỉ nhận nếu file còn mới (< 120 giây) để một file cũ sót lại không làm
# cửa sổ thường bỏ qua bước nhập key.
if ($Stage -ne 'run' -and (Test-Path $Handoff)) {
    $fresh = $false
    try {
        $h = @(Get-Content -Path $Handoff -TotalCount 3)
        if ($h.Count -ge 3) {
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h[2]
            if ($age -ge 0 -and $age -lt 120) { $fresh = $true }
        }
        if ($fresh) {
            if ($h[0].Trim() -ne '') { $env:MAS_KEY  = $h[0].Trim() }
            if ($h[1].Trim() -ne '') { $env:MAS_OPTS = $h[1].Trim() }
            $Stage = 'run'
        }
    } catch { }
    Remove-Item -Path $Handoff -Force -ErrorAction SilentlyContinue
}

# ============================================================================
#  BƯỚC 1 — hỏi KEY + LỆNH tại chính cửa sổ người dùng gõ lệnh
# ============================================================================
$KeyOK = $false
$Opts  = ''

if ($Stage -ne 'run') {
    Write-Banner $ForkName
    Write-Host ('  ' + $CopyRight) -ForegroundColor DarkGray

    # ---- key ----
    $Saved = $null
    if (Test-Path $KeyStore) {
        try { $Saved = ([string](Get-Content -Path $KeyStore -TotalCount 1)).Trim() } catch { $Saved = $null }
    }
    if ($env:MAS_KEY) { $Saved = $env:MAS_KEY.Trim() }

    $try = 0
    while (-not $KeyOK -and $try -lt 5) {
        $try++
        $in = $Saved
        if (-not $in) {
            Write-Host '  Nhập key để sử dụng:' -ForegroundColor Cyan
            $in = Read-Host '  Key'
        }
        $in = ([string]$in).Trim().ToUpper()

        if (-not $in) {
            Write-Host '  Bạn chưa nhập key.' -ForegroundColor Red
            if ($env:MAS_KEY) { break }
            continue
        }

        Write-Host '  Đang kiểm tra...' -ForegroundColor DarkGray
        $r = Invoke-MasKeyCheck $in

        if ($r.ok) {
            try {
                $dir = Split-Path -Path $KeyStore -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Set-Content -Path $KeyStore -Value $in -Encoding ASCII
            } catch { }
            if ($r.expires_at) {
                Write-Host "  Key hợp lệ — còn $($r.days_left) ngày." -ForegroundColor Green
            } else {
                Write-Host '  Key hợp lệ — vĩnh viễn.' -ForegroundColor Green
            }
            $KeyOK = $true
            break
        }

        Write-Host "  $($r.msg)" -ForegroundColor Red
        if ($env:MAS_KEY) { break }
        $Saved = $null
        Remove-Item -Path $KeyStore -Force -ErrorAction SilentlyContinue
    }

    if (-not $KeyOK) {
        Write-Banner 'KHÔNG THỂ KHỞI CHẠY' 'Red'
        Write-Host '  Key không hợp lệ hoặc đã hết hạn.' -ForegroundColor Red
        Write-Host '  Liên hệ admin để lấy key mới.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    # ---- lệnh ----
    # Danh sách lệnh KHÔNG in ra console — công thức lệnh chỉ hiện trên web.
    $passed = @($args) -join ' '
    if ($passed.Trim() -ne '') {
        $Opts = $passed.Trim()
    } else {
        Write-Host ''
        $Opts = (Read-Host '  Lệnh').Trim()
        if (-not $Opts) { $Opts = $Default }     # bỏ trống = kích hoạt Office
    }

    $env:MAS_KEY   = $in
    $env:MAS_OPTS  = $Opts
    $env:MAS_STAGE = 'run'
}

# ============================================================================
#  BƯỚC 2 — mở cửa sổ Admin (không hỏi lại gì)
# ============================================================================
if (-not (Test-Admin)) {
    # bàn giao key + lệnh cho cửa sổ Admin qua file (không phụ thuộc biến môi trường)
    try {
        $dir = Split-Path -Path $Handoff -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $Handoff -Value @(
            [string]$env:MAS_KEY,
            [string]$env:MAS_OPTS,
            [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        ) -Encoding ASCII
    } catch { }

    Write-Host ''
    Write-Host '  Đang khởi động...' -ForegroundColor DarkGray
    $sw = "-NoProfile -ExecutionPolicy Bypass -Command `"irm $GetSource | iex`""
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $sw
    } catch {
        Write-Host '  Đã huỷ cấp quyền Admin.' -ForegroundColor Red
    }
    return
}

# ============================================================================
#  BƯỚC 3 — chạy (cửa sổ Admin)
# ============================================================================
if (-not $Opts) { $Opts = [string]$env:MAS_OPTS }
if (-not $Opts) { $Opts = $Default }

Write-Host ''
Write-Host '  Đang chuẩn bị...' -ForegroundColor DarkGray
Write-Host ("  Chế độ: $Opts") -ForegroundColor DarkGray

# ---- tải + giải nén (ẩn hết chi tiết) ---------------------------------------
try {
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
} catch {
    $WorkDir = Join-Path $env:TEMP 'MAS_htchuai_office'
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

$zip = Join-Path $WorkDir 'p.zip'
$ok  = $false
foreach ($u in $Package) {
    try {
        Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 90
        $ok = $true
        break
    } catch { }
}

if (-not $ok) {
    Write-Host ''
    Write-Host '  Không tải được gói. Vui lòng thử lại sau.' -ForegroundColor Red
    return
}

try {
    Expand-Archive -Path $zip -DestinationPath $WorkDir -Force
} catch {
    Write-Host '  Không mở được gói. Vui lòng thử lại sau.' -ForegroundColor Red
    return
}

$entry = Get-ChildItem -Path $WorkDir -Recurse -Filter 'MAS_AIO.cmd' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like '*All-In-One-Version-KL*' } |
         Select-Object -First 1

if (-not $entry) {
    Write-Host '  Không tìm thấy thành phần cần thiết.' -ForegroundColor Red
    return
}

Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
Write-Host '  Xong.' -ForegroundColor DarkGray

# ---- chạy MAS trong chính cửa sổ này ---------------------------------------
Write-Banner 'Đang mở Office...' 'Green'
& cmd.exe /c "`"$($entry.FullName)`" $Opts"
