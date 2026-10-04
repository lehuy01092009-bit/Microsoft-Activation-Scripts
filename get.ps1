# ============================================================================
#  Microsoft Activation Scripts - Le Huy
#
#  Cach dung (PowerShell):
#
#      irm https://htchuai.dpdns.org/get | iex
#
#  Script se hoi KEY va LENH ngay tai cua so nay, roi moi mo cua so Admin de chay.
#  Chay khong hoi (tu dong): dat $env:MAS_KEY truoc khi chay.
# ============================================================================

$ErrorActionPreference = 'Stop'

# ---- config -----------------------------------------------------------------
$ForkName  = 'Microsoft Activation Scripts'
$GetSource = 'https://htchuai.dpdns.org/get'
$KeyApi    = 'https://htchuai.dpdns.org/api/mas/key'
$KeyStore  = Join-Path $env:LOCALAPPDATA 'MAS_htchuai\key.txt'
$Handoff   = Join-Path $env:LOCALAPPDATA 'MAS_htchuai\run.txt'
$WorkDir   = Join-Path $env:SystemRoot 'Temp\MAS_htchuai'
$Package   = @(
    'https://github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/archive/refs/heads/master.zip',
    'https://codeload.github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/zip/refs/heads/master'
)
# -----------------------------------------------------------------------------

$Stage = [string]$env:MAS_STAGE          # 'run' = cua so Admin, khong hoi lai

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

# ---- HWID (chi gui hash, khong gui UUID goc) --------------------------------

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

# ---- kiem tra key -----------------------------------------------------------

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
            msg  = 'Khong ket noi duoc may chu. Kiem tra mang roi thu lai.'
        }
    }
}

# ---- environment ------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

if ([Environment]::OSVersion.Version.Build -lt 7600) {
    Write-Host '  Windows Vista/7 tro len moi dung duoc.' -ForegroundColor Red
    return
}
if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host '  Can dung Windows PowerShell 5.1 (khong phai PowerShell Core).' -ForegroundColor Red
    return
}

# ---- cua so Admin doc lai key/lenh do cua so truoc ban giao -----------------
# Chi nhan neu file con moi (< 120 giay) de mot file cu sot lai khong lam
# cua so thuong bo qua buoc nhap key.
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
#  BUOC 1 - hoi KEY + LENH tai chinh cua so nguoi dung go lenh
# ============================================================================
$KeyOK = $false
$Opts  = ''

if ($Stage -ne 'run') {
    Write-Banner $ForkName

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
            Write-Host '  Nhap key de su dung:' -ForegroundColor Cyan
            $in = Read-Host '  Key'
        }
        $in = ([string]$in).Trim().ToUpper()

        if (-not $in) {
            Write-Host '  Ban chua nhap key.' -ForegroundColor Red
            if ($env:MAS_KEY) { break }
            continue
        }

        Write-Host '  Dang kiem tra...' -ForegroundColor DarkGray
        $r = Invoke-MasKeyCheck $in

        if ($r.ok) {
            try {
                $dir = Split-Path -Path $KeyStore -Parent
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Set-Content -Path $KeyStore -Value $in -Encoding ASCII
            } catch { }
            if ($r.expires_at) {
                Write-Host "  Key hop le - con $($r.days_left) ngay." -ForegroundColor Green
            } else {
                Write-Host '  Key hop le - vinh vien.' -ForegroundColor Green
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
        Write-Banner 'KHONG THE KHOI CHAY' 'Red'
        Write-Host '  Key khong hop le hoac da het han.' -ForegroundColor Red
        Write-Host '  Lien he admin de lay key moi.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    # ---- lenh ----
    $passed = @($args) -join ' '
    if ($passed.Trim() -ne '') {
        $Opts = $passed.Trim()
    } else {
        Write-Host ''
        Write-Host '  Nhap lenh (bo trong + Enter de vao menu chinh):' -ForegroundColor Cyan
        Write-Host '    /HWID   kich hoat Windows' -ForegroundColor DarkGray
        Write-Host '    /Ohook  kich hoat Office' -ForegroundColor DarkGray
        Write-Host '    /Z-     xoa kich hoat' -ForegroundColor DarkGray
        $Opts = (Read-Host '  Lenh').Trim()
    }

    $env:MAS_KEY   = $in
    $env:MAS_OPTS  = $Opts
    $env:MAS_STAGE = 'run'
}

# ============================================================================
#  BUOC 2 - mo cua so Admin (khong hoi lai gi)
# ============================================================================
if (-not (Test-Admin)) {
    # ban giao key + lenh cho cua so Admin qua file (khong phu thuoc bien moi truong)
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
    Write-Host '  Dang khoi dong...' -ForegroundColor DarkGray
    $sw = "-NoProfile -ExecutionPolicy Bypass -Command `"irm $GetSource | iex`""
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $sw
    } catch {
        Write-Host '  Da huy cap quyen Admin.' -ForegroundColor Red
    }
    return
}

# ============================================================================
#  BUOC 3 - chay (cua so Admin)
# ============================================================================
if (-not $Opts) { $Opts = [string]$env:MAS_OPTS }

Write-Host ''
Write-Host '  Dang chuan bi...' -ForegroundColor DarkGray

# ---- tai + giai nen (an het chi tiet) ---------------------------------------
try {
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
} catch {
    $WorkDir = Join-Path $env:TEMP 'MAS_htchuai'
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
    Write-Host '  Khong tai duoc goi. Vui long thu lai sau.' -ForegroundColor Red
    return
}

try {
    Expand-Archive -Path $zip -DestinationPath $WorkDir -Force
} catch {
    Write-Host '  Khong mo duoc goi. Vui long thu lai sau.' -ForegroundColor Red
    return
}

$entry = Get-ChildItem -Path $WorkDir -Recurse -Filter 'MAS_AIO.cmd' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like '*All-In-One-Version-KL*' } |
         Select-Object -First 1

if (-not $entry) {
    Write-Host '  Khong tim thay thanh phan can thiet.' -ForegroundColor Red
    return
}

Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
Write-Host '  Xong.' -ForegroundColor DarkGray

# ---- chay MAS trong chinh cua so nay ---------------------------------------
Write-Banner 'Dang mo...' 'Green'
& cmd.exe /c "`"$($entry.FullName)`" $Opts"
