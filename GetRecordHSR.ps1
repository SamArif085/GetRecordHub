[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Warp History Honkai: Star Rail..." -ForegroundColor Cyan

$gamePath = $null

$localLowPaths = @(
    "$env:USERPROFILE\AppData\LocalLow\Cognosphere\StarRail\Player.log",
    "$env:USERPROFILE\AppData\LocalLow\miHoYo\StarRail\Player.log"
)

foreach ($logPath in $localLowPaths) {
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        if ($logContent -match "\[Subsystems\] Discovering subsystems at path (.*)") {
            $rawPath = $matches[1].Trim()
            $possiblePath = $rawPath.Replace("UnitySubsystems", "").Trim()
            if (Test-Path (Join-Path $possiblePath "StarRail_Data")) {
                $gamePath = $possiblePath
                Write-Host "Lokasi game ditemukan lewat Player.log!" -ForegroundColor Green
                break
            }
        }
    }
}

if (-not $gamePath) {
    $proc = Get-Process -Name "StarRail" -ErrorAction SilentlyContinue
    if ($proc) {
        $procPath = Split-Path -Path $proc.Path -Parent
        if (Test-Path (Join-Path $procPath "StarRail_Data")) {
            $gamePath = $procPath
            Write-Host "Lokasi game ditemukan dari game yang sedang berjalan!" -ForegroundColor Green
        }
    }
}

if (-not $gamePath) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Cognosphere\Star Rail",
        "HKLM:\SOFTWARE\miHoYo\Star Rail",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Star Rail",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Honkai: Star Rail",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Star Rail",
        "HKCU:\Software\Cognosphere\Star Rail",
        "HKCU:\Software\miHoYo\Star Rail"
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            $props = Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue
            $dir = $props.InstallLocation
            if (-not $dir) { $dir = $props.Path }
            if ($dir -and (Test-Path (Join-Path $dir "StarRail_Data"))) {
                $gamePath = $dir
                Write-Host "Lokasi game ditemukan lewat Registry Windows!" -ForegroundColor Green
                break
            }
        }
    }
}

if (-not $gamePath) {
    Write-Host "Pemeriksaan jalur folder umum di seluruh disk..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    
    $commonSubPaths = @(
        "online game\HoYoPlay\games\Star Rail",
        "online game\HoYoPlay\games\Star Rail Games",
        "online game\Star Rail",
        "online game\Star Rail Games",
        "Game\HoYoPlay\games\Star Rail Games",
        "Game\HoYoPlay\games\Star Rail",
        "Games\HoYoPlay\games\Star Rail Games",
        "Games\HoYoPlay\games\Star Rail",
        "HoYoPlay\games\Star Rail Games",
        "HoYoPlay\games\Star Rail",
        "Star Rail\Games",
        "Star Rail Games",
        "Star Rail",
        "Honkai Star Rail",
        "Program Files\Star Rail Games",
        "Program Files\HoYoPlay\games\Star Rail"
    )

    foreach ($drive in $drives) {
        foreach ($sub in $commonSubPaths) {
            $checkPath = Join-Path $drive $sub
            if (Test-Path (Join-Path $checkPath "StarRail_Data")) {
                $gamePath = $checkPath
                Write-Host "Lokasi game ditemukan di: $gamePath" -ForegroundColor Green
                break
            }
        }
        if ($gamePath) { break }
    }
}

if (-not $gamePath -or -not (Test-Path $gamePath)) {
    Write-Host "`nGagal menemukan folder install Star Rail secara otomatis." -ForegroundColor Red
    $userPath = Read-Host "Silakan paste folder lokasi Star Rail (misal C:\online game\HoYoPlay\games\Star Rail)"
    if ($userPath -and (Test-Path (Join-Path $userPath "StarRail_Data"))) {
        $gamePath = $userPath
    }
    else {
        Write-Host "Folder tidak valid / tidak memiliki StarRail_Data. Proses dibatalkan." -ForegroundColor Red
        Read-Host "Tekan ENTER untuk keluar..."
        return
    }
}

Write-Host "Lokasi Game Terverifikasi: $gamePath" -ForegroundColor Cyan

$webCachesDir = Join-Path $gamePath "StarRail_Data\webCaches"
$latestCacheFile = Get-ChildItem -Path $webCachesDir -Recurse -Filter "data_2" -ErrorAction SilentlyContinue | 
Sort-Object LastWriteTime -Descending | 
Select-Object -First 1

if (-not $latestCacheFile) {
    Write-Host "`nFile data_2 tidak ditemukan di $webCachesDir" -ForegroundColor Red
    Write-Host "Pastikan menu Warp History di dalam game SUDAH pernah dibuka!" -ForegroundColor Yellow
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
                
                foreach ($key in $query.AllKeys) {
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
    Write-Host "`nSUKSES! URL Warp History HSR berhasil ditemukan dan disalin ke Clipboard." -ForegroundColor Green
    Write-Host "Silakan Paste (Ctrl+V) ke website tracker pilihanmu." -ForegroundColor Yellow
}
else {
    Write-Host "`nGagal menemukan URL valid di file cache. Buka ulang menu Warp History di dalam game!" -ForegroundColor Red
}

Read-Host "`nTekan ENTER untuk keluar..."