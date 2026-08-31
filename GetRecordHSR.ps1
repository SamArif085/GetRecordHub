[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Warp History Honkai: Star Rail..." -ForegroundColor Cyan

# Path Log Khusus Honkai: Star Rail
$localLowPath = "$env:USERPROFILE\AppData\LocalLow\Cognosphere\StarRail"
$playerLog = Join-Path $localLowPath "Player.log"

$gamePath = $null

if (Test-Path $playerLog) {
    Write-Host "Membaca log dari LocalLow..." -ForegroundColor Green
    $logContent = Get-Content $playerLog -Raw -ErrorAction SilentlyContinue
    
    if ($logContent -match "\[Subsystems\] Discovering subsystems at path (.*)") {
        $rawPath = $matches[1].Trim()
        $gamePath = $rawPath.Replace("UnitySubsystems", "").Trim()
    }
}

# Fallback path jika log tidak ditemukan (Sesuaikan drive jika game dipasang di lokasi lain)
if (-not $gamePath -or -not (Test-Path $gamePath)) {
    $gamePath = "C:\Program Files\Star Rail\Games"
}

Write-Host "Lokasi Game: $gamePath" -ForegroundColor Cyan

# Mencari file cache data_2 di direktori webCaches Star Rail
$webCachesDir = Join-Path $gamePath "StarRail_Data\webCaches"
$latestCacheFile = Get-ChildItem -Path $webCachesDir -Recurse -Filter "data_2" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if (-not $latestCacheFile) {
    Write-Host "`nFile data_2 tidak ditemukan di $webCachesDir" -ForegroundColor Red
    Write-Host "Pastikan menu Warp History di dalam game SUDAH dibuka!" -ForegroundColor Yellow
    Read-Host "`nTekan ENTER untuk keluar..."
    return
}

# Salin file cache ke direktori temporary
$copyPath = [IO.Path]::GetTempPath() + [Guid]::NewGuid().ToString()
Copy-Item -Path $latestCacheFile.FullName -Destination $copyPath -Force

$cacheData = Get-Content -Encoding UTF8 -Raw $copyPath
Remove-Item -Path $copyPath -Force

$cacheSplit = $cacheData -split '1/0/'
$latestUrl = $null

for ($i = $cacheSplit.Length - 1; $i -ge 0; $i--) {
    $line = $cacheSplit[$i]

    # Validasi URL API Gacha HSR
    if ($line.StartsWith('http') -and $line.Contains("getGachaLog")) {
        $url = ($line -split "`0")[0]

        try {
            $res = Invoke-WebRequest -Uri $url -ContentType "application/json" -UseBasicParsing | ConvertFrom-Json
            if ($res.retcode -eq 0) {
                $uri = [Uri]$url
                $query = [Web.HttpUtility]::ParseQueryString($uri.Query)
                
                # Filter query parameter penting untuk tracking HSR
                foreach ($key in $query.AllKeys) {
                    if ($key -ne "authkey" -and $key -ne "authkey_ver" -and $key -ne "sign_type" -and $key -ne "game_biz" -and $key -ne "lang") {
                        $query.Remove($key)
                    }
                }

                $latestUrl = $uri.Scheme + "://" + $uri.Host + $uri.AbsolutePath + "?" + $query.ToString()
                break
            }
        } catch {
            continue
        }
    }
}

if ($latestUrl) {
    Set-Clipboard -Value $latestUrl
    Write-Host "`nSUKSES! URL Warp History HSR berhasil ditemukan dan disalin ke Clipboard." -ForegroundColor Green
    Write-Host "Silakan Paste (Ctrl+V) ke website tracker pilihanmu (misal: Star Rail Station)." -ForegroundColor Yellow
} else {
    Write-Host "`nGagal menemukan URL valid di file cache. Buka ulang menu History Warp di dalam game!" -ForegroundColor Red
}

Read-Host "`nTekan ENTER untuk keluar..."