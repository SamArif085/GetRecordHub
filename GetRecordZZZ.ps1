[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Signal Search Zenless Zone Zero..." -ForegroundColor Cyan

$gamePath = $null

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 1. METODE 1: Coba baca dari Player.log (Cognosphere / miHoYo)
$localLowPaths = @(
    "$env:USERPROFILE\AppData\LocalLow\Cognosphere\ZenlessZoneZero\Player.log",
    "$env:USERPROFILE\AppData\LocalLow\miHoYo\ZenlessZoneZero\Player.log"
)

foreach ($logPath in $localLowPaths) {
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        if ($logContent -match "\[Subsystems\] Discovering subsystems at path (.*)") {
            $rawPath = $matches[1].Trim()
            $possiblePath = $rawPath.Replace("UnitySubsystems", "").Trim()
            
            if ($possiblePath.EndsWith("ZenlessZoneZero_Data\") -or $possiblePath.EndsWith("ZenlessZoneZero_Data")) {
                $possiblePath = Split-Path -Path $possiblePath -Parent
            }

            if (Test-Path (Join-Path $possiblePath "ZenlessZoneZero_Data")) {
                $gamePath = $possiblePath
                Write-Host "Lokasi game ditemukan lewat Player.log!" -ForegroundColor Green
                break
            }
        }
    }
}

# 2. METODE 2: Coba cari dari Proses Aktif ZZZ yang sedang berjalan
if (-not $gamePath) {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "*Zenless*" -or $_.Name -like "*ZZZ*" -or $_.CommandLine -like "*ZenlessZoneZero*" }

    foreach ($p in $procs) {
        if ($p.ExecutablePath) {
            $pDir = Split-Path -Path $p.ExecutablePath -Parent
            
            # Cek apakah folder tersebut tempat game (ada ZenlessZoneZero_Data)
            if (Test-Path (Join-Path $pDir "ZenlessZoneZero_Data")) {
                $gamePath = $pDir
                Write-Host "Lokasi game ditemukan dari proses aktif ($($p.Name))!" -ForegroundColor Green
                break
            }
        }
    }
}

# 3. METODE 3: Coba baca dari Windows Registry (HoYoPlay + Standard Registry)
if (-not $gamePath) {
    $regPaths = @(
        "HKCU:\Software\Cognosphere\HYP\1_1\nap_global",
        "HKCU:\Software\miHoYo\HYP\1_1\nap_global",
        "HKCU:\Software\Cognosphere\HYP\1_1\nap_cn",
        "HKCU:\Software\miHoYo\HYP\1_1\nap_cn",
        "HKCU:\Software\Cognosphere\ZenlessZoneZero",
        "HKCU:\Software\miHoYo\ZenlessZoneZero",
        "HKLM:\SOFTWARE\Cognosphere\ZenlessZoneZero",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ZenlessZoneZero Game",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Zenless Zone Zero",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\HYP_14_1_official"
    )

    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $props = Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue
            
            # Prioritaskan GameInstallPath dari HoYoPlay
            $targetDir = $props.GameInstallPath
            if (-not $targetDir) { $targetDir = $props.InstallLocation }
            if (-not $targetDir) { $targetDir = $props.InstallPath }
            if (-not $targetDir) { $targetDir = $props.InstallDir }
            if (-not $targetDir) { $targetDir = $props.Path }

            # Dekode jika tipe data berupa Byte Array (REG_BINARY)
            if ($targetDir -is [byte[]]) {
                $targetDir = [System.Text.Encoding]::UTF8.GetString($targetDir).Trim("`0").Trim()
            }

            if ($targetDir) {
                $targetDir = [string]$targetDir -replace '"', ''
                
                # Rapikan jika path menunjuk ke subfolder Data
                if ($targetDir.EndsWith("ZenlessZoneZero_Data\") -or $targetDir.EndsWith("ZenlessZoneZero_Data")) {
                    $targetDir = Split-Path -Path $targetDir -Parent
                }
                
                # Verifikasi keberadaan ZenlessZoneZero_Data atau file .exe
                if (Test-Path (Join-Path $targetDir "ZenlessZoneZero_Data")) {
                    $gamePath = $targetDir
                    Write-Host "Lokasi game ditemukan lewat Registry: $reg" -ForegroundColor Green
                    break
                }
            }
        }
    }
}

# 4. METODE 4: Auto Scan Seluruh Disk (Dilengkapi Struktur Folder Custom)
if (-not $gamePath) {
    Write-Host "Pemeriksaan jalur folder umum di seluruh disk..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    $commonSubPaths = @(
        "online game\HoYoPlay\games\ZenlessZoneZero Game",
        "online game\ZenlessZoneZero Game",
        "Game\HoYoPlay\games\ZenlessZoneZero Game",
        "Games\HoYoPlay\games\ZenlessZoneZero Game",
        "HoYoPlay\games\ZenlessZoneZero Game",
        "ZenlessZoneZero\Games",
        "ZenlessZoneZero Game",
        "Zenless Zone Zero",
        "Program Files\ZenlessZoneZero Game",
        "Program Files\HoYoPlay\games\ZenlessZoneZero Game",
        "Program Files (x86)\ZenlessZoneZero Game"
    )

    foreach ($drive in $drives) {
        foreach ($sub in $commonSubPaths) {
            $checkPath = Join-Path $drive $sub
            if (Test-Path (Join-Path $checkPath "ZenlessZoneZero_Data")) {
                $gamePath = $checkPath
                Write-Host "Lokasi game ditemukan di: $gamePath" -ForegroundColor Green
                break
            }
        }
        if ($gamePath) { break }
    }
}

# ELEVASI KE ADMINISTRATOR JIKA SEMUA METODE OTOMATIS GAGAL
if (-not $gamePath -and -not (Test-IsAdmin)) {
    Write-Host "`nMetode otomatis biasa gagal. Meminta hak akses Administrator untuk memindai ulang..." -ForegroundColor Yellow
    
    if ($MyInvocation.MyCommand.Path) {
        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        return
    }
    else {
        # Jalankan ulang URL script GetRecordZZZ.ps1 lewat Administrator
        $cmd = '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm "https://raw.githubusercontent.com/SamArif085/GetRecordZZZ/main/GetRecordZZZ.ps1")'
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
        return
    }
}

# FALLBACK MANUAL INPUT
if (-not $gamePath -or -not (Test-Path $gamePath)) {
    Write-Host "`nGagal menemukan folder install Zenless Zone Zero secara otomatis." -ForegroundColor Red
    $userPath = Read-Host "Silakan paste folder lokasi Zenless Zone Zero (misal C:\online game\HoYoPlay\games\ZenlessZoneZero Game)"
    if ($userPath -and (Test-Path (Join-Path $userPath "ZenlessZoneZero_Data"))) {
        $gamePath = $userPath
    }
    else {
        Write-Host "Folder tidak valid / tidak memiliki ZenlessZoneZero_Data. Proses dibatalkan." -ForegroundColor Red
        Read-Host "Tekan ENTER untuk keluar..."
        return
    }
}

Write-Host "Lokasi Game Terverifikasi: $gamePath" -ForegroundColor Cyan

# 5. Cari file cache data_2
$webCachesDir = Join-Path $gamePath "webCaches"
if (-not (Test-Path $webCachesDir)) {
    $webCachesDir = Join-Path $gamePath "ZenlessZoneZero_Data\webCaches"
}

$latestCacheFile = Get-ChildItem -Path $webCachesDir -Recurse -Filter "data_2" -ErrorAction SilentlyContinue | 
Sort-Object LastWriteTime -Descending | 
Select-Object -First 1

if (-not $latestCacheFile) {
    Write-Host "`nFile data_2 tidak ditemukan di $webCachesDir" -ForegroundColor Red
    Write-Host "Pastikan menu Signal Search / History di dalam game SUDAH pernah dibuka!" -ForegroundColor Yellow
    Read-Host "`nTekan ENTER untuk keluar..."
    return
}

$copyPath = [IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString()
Copy-Item -Path $latestCacheFile.FullName -Destination $copyPath -Force

$cacheData = Get-Content -Encoding UTF8 -Raw $copyPath
Remove-Item -Path $copyPath -Force

$cacheSplit = $cacheData -split '1/0/'
$latestUrl = $null

for ($i = $cacheSplit.Length - 1; $i -ge 0; $i--) {
    $line = $cacheSplit[$i]

    if ($line.StartsWith('http') -and $line.Contains("getGachaLog")) {
        $url = ($line -split "`0")[0]

        try {
            $res = Invoke-WebRequest -Uri $url -ContentType "application/json" -UseBasicParsing | ConvertFrom-Json
            if ($res.retcode -eq 0) {
                $uri = [Uri]$url
                $query = [Web.HttpUtility]::ParseQueryString($uri.Query)
                
                foreach ($key in @($query.AllKeys)) {
                    if ($key -ne "authkey" -and $key -ne "authkey_ver" -and $key -ne "sign_type" -and $key -ne "game_biz" -and $key -ne "lang") {
                        $query.Remove($key)
                    }
                }

                $latestUrl = $uri.Scheme + "://" + $uri.Host + $uri.AbsolutePath + "?" + $query.ToString()
                break
            }
        }
        catch {
            continue
        }
    }
}

if ($latestUrl) {
    Set-Clipboard -Value $latestUrl
    Write-Host "`nSUKSES! URL Signal Search ZZZ berhasil ditemukan dan disalin ke Clipboard." -ForegroundColor Green
    Write-Host "Silakan Paste (Ctrl+V) ke website tracker pilihanmu." -ForegroundColor Yellow
}
else {
    Write-Host "`nGagal menemukan URL valid di file cache. Buka ulang menu History di dalam game!" -ForegroundColor Red
}

Read-Host "`nTekan ENTER untuk keluar..."