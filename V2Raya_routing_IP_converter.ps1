# V2Raya_routing_IP_converter.ps1
# Вставьте IP, потом нажмите Enter, потом Enter ещё раз (пустую строку) для завершения

function Parse-AndFixNetworks {
    param([string[]]$Lines)
    
    $allText = $lines -join " "
    
    # Извлекаем всё, что похоже на IP или CIDR
    $pattern = '([0-9a-fA-F\.\:/]+)'
    $rawParts = [Regex]::Matches($allText, $pattern) | ForEach-Object { $_.Value }
    
    $networks = @()
    $ipv4List = @()
    $ipv6List = @()
    
    foreach ($item in $rawParts) {
        $cleanItem = $item.Trim("'", '"', ',')
        if ([string]::IsNullOrWhiteSpace($cleanItem) -or $cleanItem -eq "/") { continue }
        
        # Нормализуем CIDR
        $normalized = $cleanItem
        if ($cleanItem -match '^(\d+\.\d+\.\d+\.\d+)$') {
            # Одиночный IPv4 -> /32
            $normalized = "$cleanItem/32"
        }
        elseif ($cleanItem -match '^([a-fA-F0-9:]+)$' -and $cleanItem -match ':') {
            # Одиночный IPv6 -> /128
            $normalized = "$cleanItem/128"
        }
        elseif ($cleanItem -match '^(\d+\.\d+\.\d+\.\d+)/(\d+)$') {
            # IPv4 CIDR - оставляем как есть
        }
        elseif ($cleanItem -match '^([a-fA-F0-9:]+)/(\d+)$') {
            # IPv6 CIDR - оставляем как есть
        }
        else {
            continue
        }
        
        # Разделяем IPv4 и IPv6 для сортировки
        if ($normalized -match ':') {
            $ipv6List += $normalized
        } else {
            $ipv4List += $normalized
        }
    }
    
    # Сортируем и объединяем
    $ipv4List = $ipv4List | Sort-Object -Unique
    $ipv6List = $ipv6List | Sort-Object -Unique
    
    return @($ipv4List) + @($ipv6List)
}

# Устанавливаем кодировку консоли на UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Vvedite IP-adresa ili seti (vstavte cherez Ctrl+V, potom nazhmite Enter, potom eshe odin raz Enter dlya zaversheniya):" -ForegroundColor Cyan
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
    
    $nets = Parse-AndFixNetworks -Lines $lines
    
    if ($nets.Count -eq 0) {
        Write-Host "Validnye IP-seti ne naideny." -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        exit
    }
    
    # Формат: ip("1.1.1.1/32","8.8.8.8/32") ->proxy
    $formatted = $nets -join '","'
    Write-Host "`nRezultat:" -ForegroundColor Green
    Write-Host "ip(`"$formatted`") ->proxy"
    
} catch {
    Write-Host "Oshibka: $_" -ForegroundColor Red
}

Write-Host "`nDone." -ForegroundColor Cyan
Read-Host "Press Enter to exit"