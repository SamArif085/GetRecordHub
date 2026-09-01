[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web

$ProgressPreference = 'SilentlyContinue'
Write-Host "Mencari URL Signal Search Zenless Zone Zero..." -ForegroundColor Cyan

$gamePath = $null

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
            
            # Sanitasi jika mengarah ke subfolder ZenlessZoneZero_Data
            if ($possiblePath.EndsWith("ZenlessZoneZero_Data\") -or $possiblePath.EndsWith("ZenlessZoneZero_Data")) {
                $possiblePath = Split-Path -Path $possiblePath -Parent
            }

            if (Test-Path (Join-Path $possiblePath "ZenlessZoneZero.exe")) {
                $gamePath = $possiblePath
                Write-Host "Lokasi game ditemukan lewat Player.log!" -ForegroundColor Green
                break
            }
        }
    }
}

if (-not $gamePath) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ZenlessZoneZero Game",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Zenless Zone Zero",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\HYP_14_1_official",
        "HKCU:\SOFTWARE\miHoYo\ZenlessZoneZero",
        "HKCU:\SOFTWARE\Cognosphere\ZenlessZoneZero"
    )

    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            try {
                $item = Get-Item -Path $reg -ErrorAction SilentlyContinue
                $installDir = $item.GetValue("InstallPath", $null)
                if (-not $installDir) { $installDir = $item.GetValue("InstallDir", $null) }
                if (-not $installDir) { $installDir = $item.GetValue("InstallLocation", $null) }
                
                if ($installDir) {
                    if ($installDir.EndsWith("ZenlessZoneZero_Data\") -or $installDir.EndsWith("ZenlessZoneZero_Data")) {
                        $installDir = Split-Path -Path $installDir -Parent
                    }
                    if (Test-Path (Join-Path $installDir "ZenlessZoneZero.exe")) {
                        $gamePath = $installDir
                        Write-Host "Lokasi game ditemukan lewat Windows Registry!" -ForegroundColor Green
                        break
                    }
                }
            } catch { continue }
        }
    }
}

if (-not $gamePath) {
    Write-Host "Mencari lokasi install ZZZ di seluruh disk..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    
    $commonSubPaths = @(
        "Game\HoYoPlay\games\ZenlessZoneZero Game",
        "Games\HoYoPlay\games\ZenlessZoneZero Game",
        "HoYoPlay\games\ZenlessZoneZero Game",
        "ZenlessZoneZero\Games",
        "ZenlessZoneZero Game",
        "Program Files\ZenlessZoneZero Game",
        "Program Files\HoYoPlay\games\ZenlessZoneZero Game"
    )

    foreach ($drive in $drives) {
        foreach ($sub in $commonSubPaths) {
            $checkPath = Join-Path $drive $sub
            if (Test-Path (Join-Path $checkPath "ZenlessZoneZero.exe")) {
                $gamePath = $checkPath
                Write-Host "Lokasi game ditemukan di: $gamePath" -ForegroundColor Green
                break
            }
        }
        if ($gamePath) { break }
    }
}

if (-not $gamePath -or -not (Test-Path $gamePath)) {
    Write-Host "`nGagal menemukan folder install Zenless Zone Zero secara otomatis." -ForegroundColor Red
    Write-Host "Pastikan menu Signal Search / History di dalam game SUDAH pernah dibuka!" -ForegroundColor Yellow
    Read-Host "`nTekan ENTER untuk keluar..."
    return
}

Write-Host "Lokasi Game Terverifikasi: $gamePath" -ForegroundColor Cyan

$webCachesDir = Join-Path $gamePath "webCaches"
if (-not (Test-Path $webCachesDir)) {
    $webCachesDir = Join-Path $gamePath "ZenlessZoneZero_Data\webCaches"
}

$latestCacheFile = Get-ChildItem -Path $webCachesDir -Recurse -Filter "data_2" -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if (-not $latestCacheFile) {
    Write-Host "`nFile data_2 tidak ditemukan di $webCachesDir" -ForegroundColor Red
    Write-Host "Pastikan menu Signal Search / History di dalam game SUDAH dibuka!" -ForegroundColor Yellow
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
        } catch {
            continue
        }
    }
}

if ($latestUrl) {
    Set-Clipboard -Value $latestUrl
    Write-Host "`nSUKSES! URL Signal Search ZZZ berhasil ditemukan dan disalin ke Clipboard." -ForegroundColor Green
    Write-Host "Silakan Paste (Ctrl+V) ke website tracker pilihanmu." -ForegroundColor Yellow
} else {
    Write-Host "`nGagal menemukan URL valid di file cache. Buka ulang menu History di dalam game!" -ForegroundColor Red
}

Read-Host "`nTekan ENTER untuk keluar..."