$cacheFile = Join-Path $env:LOCALAPPDATA "PlatformProcess\Cache\data_1"
$tempCopy = Join-Path $env:TEMP "endfield_data1_temp.tmp"

if (-not (Test-Path $cacheFile)) {
    Write-Host "[X] Berkas data_1 tidak ditemukan." -ForegroundColor Red
} else {
    try {
        # Duplikat file data_1 ke folder Temp Windows untuk bypass file lock
        Copy-Item -Path $cacheFile -Destination $tempCopy -Force

        # Baca isi file dari salinan sementara
        $bytes = [System.IO.File]::ReadAllBytes($tempCopy)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)

        # Hapus file sementara setelah dibaca
        Remove-Item -Path $tempCopy -Force -ErrorAction SilentlyContinue

        # Pattern untuk menangkap URL Webview Gryphline
        $pattern = 'https://ef-webview\.gryphline\.com/[^\s"''<>\x00-\x1f]+'
        $matches = [regex]::Matches($text, $pattern)

        # Filter URL khusus gacha / record
        $gachaUrls = $matches | Where-Object { $_.Value -match 'record' -or $_.Value -match 'gacha' }

        if ($gachaUrls.Count -gt 0) {
            $latestUrl = $gachaUrls[-1].Value
            Set-Clipboard -Value $latestUrl
            Write-Host "`n[V] BERHASIL MENEMUKAN URL GACHA!" -ForegroundColor Green
            Write-Host "URL sudah disalin ke Clipboard.`n" -ForegroundColor Cyan
            Write-Host "URL: $latestUrl`n" -ForegroundColor Gray
        } else {
            Write-Host "`n[!] URL Riwayat Gacha belum terekam di data_1." -ForegroundColor Yellow
            Write-Host "Pastikan kamu sudah menekan tombol 'Riwayat / History' di menu Headhunting!" -ForegroundColor Yellow
            
            if ($matches.Count -gt 0) {
                Write-Host "`nURL Webview terakhir yang ditemukan di cache:" -ForegroundColor DarkGray
                Write-Host $matches[-1].Value -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "[X] Gagal membaca file: $_" -ForegroundColor Red
    }
}

Write-Host "`nTekan Enter untuk menutup..." -ForegroundColor DarkGray
$null = Read-Host