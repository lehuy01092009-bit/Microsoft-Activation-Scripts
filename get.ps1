# ============================================================================
#  Microsoft Activation Scripts - htchuai fork
#
#  Usage (PowerShell, as Administrator):
#
#      irm https://htchuai.dpdns.org/get | iex
#
#  Optional switches are forwarded to MAS, e.g.:
#
#      & ([scriptblock]::Create((irm https://htchuai.dpdns.org/get))) /HWID
#
#  This loader downloads the htchuai-fork MAS package, extracts it, and launches
#  the All-In-One script.
# ============================================================================

$ErrorActionPreference = 'Stop'

# ---- config -----------------------------------------------------------------
$ForkName    = 'Microsoft Activation Scripts (htchuai fork)'
$PackageUrls = @(
    'https://github.com/htchuai/Microsoft-Activation-Scripts/archive/refs/heads/master.zip',
    'https://git.htchuai.dpdns.org/Microsoft-Activation-Scripts/archive/refs/heads/master.zip'
)
$GetSource   = 'https://htchuai.dpdns.org/get'   # used for self-elevation
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

# ---- download ---------------------------------------------------------------

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

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
