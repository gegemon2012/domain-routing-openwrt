# Convert-LstToJson.ps1 (красивый JSON)

$lstFiles = Get-ChildItem -Filter "*.lst"

if ($lstFiles.Count -eq 0) {
    Write-Host "No .lst files found." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "Found files: $($lstFiles.Count)"

foreach ($file in $lstFiles) {
    $outputFile = [System.IO.Path]::ChangeExtension($file.Name, "json")
    
    $lines = Get-Content $file.FullName -Encoding UTF8 | Where-Object {
        $_.Trim() -ne "" -and $_ -notmatch "^\s*#" -and $_ -match "\."
    }
    
    # Убираем кавычки в начале и/или в конце каждой строки
    $cleanIps = $lines | ForEach-Object { 
        $_.Trim() -replace '^"', '' -replace '"$', ''
    } | Sort-Object -Unique
    
    # Конвертируем очищенные строки в JSON
    $cleanIps | ConvertTo-Json | Set-Content $outputFile -Encoding UTF8
    
    Write-Host "OK: $($file.Name) -> $outputFile ($($cleanIps.Count) entries)" -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
Read-Host "Press Enter to exit"
