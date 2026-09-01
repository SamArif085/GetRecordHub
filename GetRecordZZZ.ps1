[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Signal Search ZZZ secara Global..." -ForegroundColor Cyan

$gamePath = $null

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ZenlessZoneZero Game",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Zenless Zone Zero",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\HYP_14_1_official",
    "HKCU:\SOFTWARE\miHoYo\ZenlessZoneZero",
    "HKCU:\SOFTWARE\Cognosphere\ZenlessZoneZero"
)

foreach ($reg in $registryPaths) {
    if (Test-Path $reg) {
        $installDir = (Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue).InstallPath
        if (-not $installDir) {
            $installDir = (Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue).InstallDir
        }
        if ($installDir -and (Test-Path $installDir)) {
            $gamePath = $installDir
            break
        }
    }
}

if (-not $gamePath -or -not (Test-Path $gamePath)) {
    $possibleLogs = @(
        "$env:USERPROFILE\AppData\LocalLow\miHoYo\ZenlessZoneZero\Player.log",
        "$env:USERPROFILE\AppData\LocalLow\Cognosphere\ZenlessZoneZero\Player.log"
    )

    foreach ($logFile in $possibleLogs) {
        if (Test-Path $logFile) {
            $logContent = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($logContent -match "\[Subsystems\] Discovering subsystems at path (.*)") {
                $rawPath = $matches[1].Trim()
                $parsedPath = $rawPath.Replace("UnitySubsystems", "").Trim()
                if (Test-Path $parsedPath) {
                    $gamePath = $parsedPath
                    break
                }
            }
        }
    }
}

if (-not $gamePath -or -not (Test-Path $gamePath)) {
    Write-Host "Mencari folder game di seluruh Drive..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    
    foreach ($drive in $drives) {
        $searchPattern = Join-Path $drive "*\ZenlessZoneZero Game"
        $foundDirs = Get-Item $searchPattern -ErrorAction SilentlyContinue
        if ($foundDirs) {
            $gamePath = $foundDirs[0].FullName
            break
        }
    }
}

if (-not $gamePath -or -not (Test-Path $gamePath)) {
    Write-Host "`nGagal menemukan lokasi instalasi Zenless Zone Zero di PC ini!" -ForegroundColor Red
    Read-Host "`nTekan ENTER untuk keluar..."
    return
}

Write-Host "Lokasi Game Ditemukan: $gamePath" -ForegroundColor Green

$webCachesDir = Join-Path $gamePath "webCaches"
$latestCacheFile = Get-ChildItem -Path $webCachesDir -Recurse -Filter "data_2" -ErrorAction SilentlyContinue | 
Sort-Object LastWriteTime -Descending | 
Select-Object -First 1

if (-not $latestCacheFile) {
    Write-Host "`nFile cache Gacha (data_2) tidak ditemukan di: $webCachesDir" -ForegroundColor Red
    Write-Host "Pastikan menu History Gacha di dalam game SUDAH dibuka minimal 1x!" -ForegroundColor Yellow
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
    Write-Host "`nSUKSES! URL Search History berhasil ditemukan dan disalin ke Clipboard." -ForegroundColor Green
    Write-Host "Silakan Paste (Ctrl+V) ke website tracker pilihanmu." -ForegroundColor Yellow
}
else {
    Write-Host "`nGagal menemukan URL valid di file cache. Buka ulang menu History di game!" -ForegroundColor Red
}

Read-Host "`nTekan ENTER untuk keluar..."