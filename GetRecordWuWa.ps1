[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Convene History Wuthering Waves..." -ForegroundColor Cyan

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

try {
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamPath) {
        $steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
    }

    if ($steamPath) {
        $vdfPath = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        $steamLibraries = [System.Collections.Generic.List[string]]::new()
        $steamLibraries.Add($steamPath)

        if (Test-Path $vdfPath) {
            $vdfContent = Get-Content $vdfPath -Raw -ErrorAction SilentlyContinue
            $matches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
            foreach ($m in $matches) {
                $lib = $m.Groups[1].Value.Replace("\\", "\")
                if (Test-Path $lib) { $steamLibraries.Add($lib) }
            }
        }

        # App ID Resmi (3513350) dan Playtest (2772750)
        $wuwaAppIds = @("3513350", "2772750")

        foreach ($lib in ($steamLibraries | Select-Object -Unique)) {
            foreach ($appId in $wuwaAppIds) {
                $manifestPath = Join-Path $lib "steamapps\appmanifest_$appId.acf"
                if (Test-Path $manifestPath) {
                    # Cek folder umum tempat file log berada
                    $candidateLog = Join-Path $lib "steamapps\common\Wuthering Waves\Client\Saved\Logs\Client.log"
                    if (Test-Path $candidateLog) {
                        $foundLogFiles.Add($candidateLog)
                        Write-Host "Lokasi game ditemukan dari Steam Manifest (App ID: $appId)!" -ForegroundColor Green
                    }
                }
            }
        }
    }
}
catch {}

if ($foundLogFiles.Count -eq 0) {
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
        }
        catch {}
    }
}

$localAppDataLog = "$env:LOCALAPPDATA\Client\Saved\Logs\Client.log"
if (Test-Path $localAppDataLog -ErrorAction SilentlyContinue) { $foundLogFiles.Add($localAppDataLog) }

if ($foundLogFiles.Count -eq 0) {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "*Wuthering*" -or $_.Name -like "*Client-Win64*" -or $_.CommandLine -like "*Wuthering Waves*" }

    foreach ($p in $procs) {
        if ($p.ExecutablePath) {
            $pDir = Split-Path -Path $p.ExecutablePath -Parent
            if ($pDir -like "*Client*") {
                $baseDir = ($pDir -split '\\Client\\')[0]
                $candidateLog = Join-Path $baseDir "Client\Saved\Logs\Client.log"
                if (Test-Path $candidateLog -ErrorAction SilentlyContinue) {
                    $foundLogFiles.Add($candidateLog)
                    Write-Host "Lokasi log ditemukan dari proses aktif ($($p.Name))!" -ForegroundColor Green
                    break
                }
            }
        }
    }
}

if ($foundLogFiles.Count -eq 0) {
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
}

if ($foundLogFiles.Count -eq 0 -and -not (Test-IsAdmin)) {
    Write-Host "`n[!] Metode pencarian otomatis tanpa Admin gagal." -ForegroundColor Yellow
    Write-Host "Meminta hak akses Administrator untuk memindai ulang..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    
    if ($MyInvocation.MyCommand.Path) {
        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        return
    }
    else {
        $cmd = '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm "https://raw.githubusercontent.com/SamArif085/GetRecordZZZ/main/GetRecordWuWa.ps1")'
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
        return
    }
}

$targetLogFile = $null
$uniqueLogs = Get-Item -Path ($foundLogFiles | Select-Object -Unique) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($uniqueLogs -and $uniqueLogs.Count -gt 0) {
    $targetLogFile = $uniqueLogs[0].FullName
}
else {
    Write-Host "`n[X] Gagal menemukan file Client.log secara otomatis." -ForegroundColor Red
    $userPath = Read-Host "Silakan tempel (paste) folder lokasi Wuthering Waves (misal: G:\Game\Steam\steamapps\common\Wuthering Waves)"
    if ($userPath) {
        $manualLog = Join-Path $userPath "Client\Saved\Logs\Client.log"
        if (Test-Path $manualLog) {
            $targetLogFile = $manualLog
        }
    }
}

if (-not $targetLogFile -or -not (Test-Path $targetLogFile)) {
    Write-Host "`nFile Client.log tidak terverifikasi. Proses dibatalkan." -ForegroundColor Red
    Read-Host "Tekan ENTER untuk keluar..."
    return
}

Write-Host "File Log Terverifikasi: $targetLogFile" -ForegroundColor Green

$freshUrl = $null
$regex = 'https://aki-gm-resources(-oversea)?\.aki-game\.(net|com)/aki/gacha/index\.html#/record[^"\s]*'

try {
    $fileShare = [System.IO.FileShare]([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    $fileStream = [System.IO.File]::Open($targetLogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $fileShare)
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
}
catch {
    Write-Host "`n[!] Gagal membaca isi log: $_" -ForegroundColor Red
}

if ($freshUrl) {
    Set-Clipboard -Value $freshUrl
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host "[SUKSES] URL Convene History Berhasil Disalin ke Clipboard!" -ForegroundColor Green
    Write-Host "URL: $freshUrl" -ForegroundColor Gray
    Write-Host "========================================================" -ForegroundColor Green
}
else {
    Write-Host "`n[!] File Client.log ditemukan, tetapi URL belum tercatat." -ForegroundColor Red
    Write-Host "Buka game -> Convene History -> Klik panah 'Next Page' ( > ) -> Jalankan lagi!" -ForegroundColor Yellow
}

Read-Host "`nTekan ENTER untuk keluar..."