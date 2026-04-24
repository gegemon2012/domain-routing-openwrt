# V2Raya_routing_domain_converter.ps1
# Вставьте домены, потом нажмите Enter, потом Enter ещё раз (пустую строку) для завершения

function Parse-Domains {
    param([string[]]$Lines)
    
    $allText = $Lines -join " "
    
    # Очищаем текст от мусора
    $cleaned = $allText -replace "['\"",\t\r\n]", " "
    
    # Регулярное выражение для доменов
    $pattern = '\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,12}\b'
    
    $domains = [Regex]::Matches($cleaned, $pattern, 'IgnoreCase') | ForEach-Object {
        $_.Value.ToLower()
    } | Sort-Object -Unique
    
    return $domains
}

# Устанавливаем кодировку консоли на UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Vvedite domeny (vstavte cherez Ctrl+V, potom nazhmite Enter, potom eshe odin raz Enter dlya zaversheniya):" -ForegroundColor Cyan
Write-Host "(Pustaya stroka zavershaet vvod)" -ForegroundColor Gray

try {
    $lines = @()
    while ($true) {
        $line = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) {
            break
        }
        $lines += $line
    }
    
    if ($lines.Count -eq 0) {
        Write-Host "Vvod pust." -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        exit
    }
    
    $domains = Parse-Domains -Lines $lines
    
    if ($domains.Count -eq 0) {
        Write-Host "Domeny ne naideny." -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        exit
    }
    
    Write-Host "`nRezultat:" -ForegroundColor Green
    foreach ($d in $domains) {
        Write-Host "domain(domain: $d) ->proxy"
    }
    
} catch {
    Write-Host "Oshibka: $_" -ForegroundColor Red
}

Write-Host "`nDone." -ForegroundColor Cyan
Read-Host "Press Enter to exit"