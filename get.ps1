# ============================================================================
#  Microsoft Activation Scripts - htchuai fork
#
#  Usage (PowerShell):
#
#      irm https://htchuai.dpdns.org/get | iex
#
#  Optional switches are forwarded to MAS, e.g.:
#
#      & ([scriptblock]::Create((irm https://htchuai.dpdns.org/get))) /HWID
#
#  KEY: script se hoi key va kiem tra qua https://htchuai.dpdns.org/api/mas/key
#       Key hop le moi vao duoc menu chinh cua MAS.
#       Key duoc luu tai %LOCALAPPDATA%\MAS_htchuai\key.txt -> lan sau khong hoi lai.
#       Chay khong hoi (tu dong): dat truoc $env:MAS_KEY = 'MAS-XXXX-XXXX-XXXX-XXXX'
# ============================================================================

$ErrorActionPreference = 'Stop'

# ---- config -----------------------------------------------------------------
$ForkName    = 'Microsoft Activation Scripts (htchuai fork)'
$PackageUrls = @(
    'https://github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/archive/refs/heads/master.zip',
    'https://codeload.github.com/lehuy01092009-bit/Microsoft-Activation-Scripts/zip/refs/heads/master'
)
$GetSource   = 'https://htchuai.dpdns.org/get'   # used for self-elevation
$KeyApi      = 'https://htchuai.dpdns.org/api/mas/key'
$KeyStore    = Join-Path $env:LOCALAPPDATA 'MAS_htchuai\key.txt'
$WorkDir     = Join-Path $env:SystemRoot 'Temp\MAS_htchuai'
# -----------------------------------------------------------------------------

function Write-Banner($text, $color = 'Green') {
    Write-Host ''
    Write-Host ('  ' + '=' * 68) -ForegroundColor $color
    Write-Host ('    ' + $text) -ForegroundColor $color
    Write-Host ('  ' + '=' * 68) -ForegroundColor $color
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
    try {
        $raw = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
    } catch { }
    if (-not $raw) {
        try { $raw = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
    }
    if (-not $raw) { $raw = $env:COMPUTERNAME }
    $raw = ([string]$raw).Trim().ToUpper()
    if (-not $raw) { $raw = 'UNKNOWN' }
    $sha  = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

# ---- goi API kiem tra key ---------------------------------------------------

function Invoke-MasKeyCheck([string]$Key) {
    try {
        $res = Invoke-RestMethod -Uri $KeyApi -Method Post -TimeoutSec 30 -Body @{
            key  = $Key
            hwid = (Get-MasHWID)
        }
        return $res
    } catch {
        return [pscustomobject]@{
            ok   = $false
            code = 'network'
            msg  = "Khong ket noi duoc server key. Kiem tra mang roi thu lai. ($($_.Exception.Message))"
        }
    }
}

# ---- environment sanity -----------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ([Environment]::OSVersion.Version.Build -lt 7600) {
    Write-Host 'MAS requires Windows Vista/7 or later.' -ForegroundColor Red
    return
}

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Host 'Windows PowerShell 5.1 is required (not PowerShell Core).' -ForegroundColor Red
    return
}

# ---- elevate ----------------------------------------------------------------

if (-not (Test-Admin)) {
    Write-Host ''
    Write-Host '  Administrator privileges are required.' -ForegroundColor Yellow
    Write-Host '  Re-launching elevated...' -ForegroundColor Yellow
    $sw = "-NoProfile -ExecutionPolicy Bypass -Command `"irm $GetSource | iex`""
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $sw
    } catch {
        Write-Host '  Elevation was cancelled.' -ForegroundColor Red
    }
    return
}

Write-Banner $ForkName

# ---- key check --------------------------------------------------------------

$SavedKey = $null
if (Test-Path $KeyStore) {
    try { $SavedKey = ([string](Get-Content -Path $KeyStore -TotalCount 1)).Trim() } catch { $SavedKey = $null }
}
if ($env:MAS_KEY) { $SavedKey = $env:MAS_KEY.Trim() }

$KeyOK   = $false
$attempt = 0

while (-not $KeyOK -and $attempt -lt 5) {
    $attempt++
    $inputKey = $SavedKey

    if (-not $inputKey) {
        Write-Host '  ' + ('-' * 68) -ForegroundColor Cyan
        Write-Host '    NHAP KEY DE SU DUNG' -ForegroundColor Cyan
        Write-Host '    (key lay tu admin, dang MAS-XXXX-XXXX-XXXX-XXXX)' -ForegroundColor DarkGray
        Write-Host '  ' + ('-' * 68) -ForegroundColor Cyan
        $inputKey = Read-Host '  Key'
    }

    $inputKey = ([string]$inputKey).Trim().ToUpper()

    if (-not $inputKey) {
        Write-Host '  Ban chua nhap key.' -ForegroundColor Red
        if ($env:MAS_KEY) { break }
        continue
    }

    Write-Host '  Dang kiem tra key...' -ForegroundColor DarkGray
    $res = Invoke-MasKeyCheck $inputKey

    if ($res.ok) {
        try {
            $dir = Split-Path -Path $KeyStore -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -Path $KeyStore -Value $inputKey -Encoding ASCII
        } catch { }
        if ($res.expires_at) {
            Write-Host "  Key hop le - con $($res.days_left) ngay ($($res.devices) thiet bi)." -ForegroundColor Green
        } else {
            Write-Host "  Key hop le - vinh vien ($($res.devices) thiet bi)." -ForegroundColor Green
        }
        $KeyOK = $true
        break
    }

    Write-Host "  $($res.msg)" -ForegroundColor Red
    if ($env:MAS_KEY) { break }

    # key luu san sai -> xoa de hoi lai
    $SavedKey = $null
    Remove-Item -Path $KeyStore -Force -ErrorAction SilentlyContinue
}

if (-not $KeyOK) {
    Write-Banner 'KHONG THE KHOI CHAY' 'Red'
    Write-Host '  Key khong hop le hoac da het han.' -ForegroundColor Red
    Write-Host '  Lien he admin de lay key moi.' -ForegroundColor Yellow
    Write-Host ''
    Read-Host '  Nhan Enter de thoat'
    return
}

# ---- download ---------------------------------------------------------------

try {
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
} catch {
    # thu muc mac dinh khong dung duoc -> chuyen sang %TEMP%
    $WorkDir = Join-Path $env:TEMP 'MAS_htchuai'
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

$zip   = Join-Path $WorkDir 'mas.zip'
$lived = $false

foreach ($url in $PackageUrls) {
    try {
        Write-Host '  Downloading package...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 90
        $lived = $true
        break
    } catch {
        Write-Host "    unavailable: $url" -ForegroundColor DarkGray
    }
}

if (-not $lived) {
    Write-Host ''
    Write-Host '  Could not download the MAS package.' -ForegroundColor Red
    Write-Host '  Download the ZIP manually and run MAS_AIO.cmd from it.' -ForegroundColor Yellow
    return
}

Write-Host '  Extracting...' -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $WorkDir -Force

$entry = Get-ChildItem -Path $WorkDir -Recurse -Filter 'MAS_AIO.cmd' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -like '*All-In-One-Version-KL*' } |
         Select-Object -First 1

if (-not $entry) {
    Write-Host '  MAS_AIO.cmd not found in the package.' -ForegroundColor Red
    return
}

# ---- launch -----------------------------------------------------------------

Write-Banner 'Starting...' 'Green'

$pass = @($args)
& cmd.exe /c "`"$($entry.FullName)`" $($pass -join ' ')"
