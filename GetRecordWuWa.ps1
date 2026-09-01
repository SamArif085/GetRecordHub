[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($IsAdmin) {
    Write-Host "[MODE] Jalur Administrator (Elevated Permissions)" -ForegroundColor Cyan
} else {
    Write-Host "[MODE] Jalur Pengguna Biasa (Non-Admin)" -ForegroundColor DarkGray
}

Write-Host "Mencari URL Convene History Wuthering Waves..." -ForegroundColor Cyan

Add-Type -TypeDefinition @"
namespace WuWaTracker.Import {
    public static class ClientLogXorDecoderV1 {
        public static void Decode(byte[] data) {
            for (int i = 0; i < data.Length; i++) {
                byte b = data[i];
                data[i] = (byte)(b ^ (((b & 1) != 0) ? 0xA5 : 0xEF));
            }
        }
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null

$foundLogFiles = [System.Collections.Generic.List[string]]::new()

$regPaths = @(
    "Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
    "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
)

foreach ($rp in $regPaths) {
    try {
        $props = (Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue).PSObject.Properties
        foreach ($p in $props) {
            if ($p.Value -like "*wuthering*" -and ($p.Value -like "*client-win64-shipping*" -or $p.Name -like "*client-win64-shipping*")) {
                $rawPath = if ($p.Value -like "*App=*") { ($p.Value -split 'App=')[1] } else { $p.Name }
                if ($rawPath -and $rawPath -like "*Client*") {
                    $baseDir = ($rawPath -split '\\Client\\')[0]
                    $candidateLog = Join-Path $baseDir "Client\Saved\Logs\Client.log"
                    if (Test-Path $candidateLog -ErrorAction SilentlyContinue) { $foundLogFiles.Add($candidateLog) }
                }
            }
        }
    } catch {}
}

$localAppDataLog = "$env:LOCALAPPDATA\Client\Saved\Logs\Client.log"
if (Test-Path $localAppDataLog -ErrorAction SilentlyContinue) { $foundLogFiles.Add($localAppDataLog) }

$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
foreach ($d in $drives) {
    $pathsToTest = @(
        "$d`:\SteamLibrary\steamapps\common\Wuthering Waves\Client\Saved\Logs\Client.log",
        "$d`:\Program Files (x86)\Steam\steamapps\common\Wuthering Waves\Client\Saved\Logs\Client.log",
        "$d`:\Steam\steamapps\common\Wuthering Waves\Client\Saved\Logs\Client.log",
        "$d`:\Program Files\Epic Games\WutheringWavesj3oFh\Client\Saved\Logs\Client.log",
        "$d`:\Wuthering Waves\Client\Saved\Logs\Client.log",
        "$d`:\Wuthering Waves\Wuthering Waves Game\Client\Saved\Logs\Client.log",
        "$d`:\Program Files\Wuthering Waves\Wuthering Waves Game\Client\Saved\Logs\Client.log",
        "$d`:\Games\Wuthering Waves\Client\Saved\Logs\Client.log"
    )
    foreach ($pt in $pathsToTest) {
        if (Test-Path $pt -ErrorAction SilentlyContinue) { $foundLogFiles.Add($pt) }
    }
}

$uniqueLogs = Get-Item -Path ($foundLogFiles | Select-Object -Unique) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($null -eq $uniqueLogs -or $uniqueLogs.Count -eq 0) {
    Write-Host "`n[X] Tidak dapat menemukan lokasi file Client.log di komputer ini." -ForegroundColor Red
    Read-Host "Tekan ENTER untuk keluar..."
    return
}

$targetLogFile = $uniqueLogs[0]
Write-Host "File log aktif: $($targetLogFile.FullName)" -ForegroundColor Green

$freshUrl = $null
$permissionError = $false
$regex = 'https://aki-gm-resources(-oversea)?\.aki-game\.(net|com)/aki/gacha/index\.html#/record[^"\s]*'

try {
    $fileShare = [System.IO.FileShare]([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    $fileStream = [System.IO.File]::Open($targetLogFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $fileShare)
    $memStream = New-Object System.IO.MemoryStream
    $fileStream.CopyTo($memStream)
    $bytes = $memStream.ToArray()
    $memStream.Dispose()
    $fileStream.Dispose()

    [WuWaTracker.Import.ClientLogXorDecoderV1]::Decode($bytes)
    $logContent = [System.Text.Encoding]::UTF8.GetString($bytes)

    if ($logContent -match $regex) {
        $matches = [regex]::Matches($logContent, $regex)
        $freshUrl = $matches[$matches.Count - 1].Value
    }
} catch [System.UnauthorizedAccessException] {
    $permissionError = $true
} catch {
    if ($_.Exception.InnerException -is [System.UnauthorizedAccessException] -or $_.Exception.Message -like "*access*denied*") {
        $permissionError = $true
    }
}

if ($permissionError -and -not $IsAdmin) {
    Write-Host "`n[!] Akses file ditolak karena keterbatasan hak akses Non-Admin." -ForegroundColor Yellow
    Write-Host "Mengalihkan ke mode Administrator..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

if ($freshUrl) {
    Set-Clipboard -Value $freshUrl
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host "[SUKSES] URL Convene History Berhasil Disalin ke Clipboard!" -ForegroundColor Green
    Write-Host "URL: $freshUrl" -ForegroundColor Gray
    Write-Host "========================================================" -ForegroundColor Green
} else {
    Write-Host "`n[!] File Client.log berhasil dibuka, tetapi URL belum tercatat." -ForegroundColor Red
    Write-Host "Buka game -> Convene History -> Klik panah 'Next Page' ( > ) -> Jalankan lagi!" -ForegroundColor Yellow
}

Read-Host "`nTekan ENTER untuk keluar..."