# xray_to_tproxy_converter.ps1
# Конвертирует Xray конфиг в TPROXY-ready формат

param(
    [string]$InputFile = "config.json",
    [string]$OutputFile = "config_tproxy.json"
)

function Generate-MinimalTproxyConfig {
    param($Config, $OutputPath)
    
    # 1. Inbound: TPROXY (dokodemo-door) и SOCKS для тестов
    $Config.inbounds = @(
        @{
            tag = "tproxy-in"
            port = 1100
            protocol = "dokodemo-door"
            settings = @{
                network = "tcp,udp"
                followRedirect = $true
            }
            streamSettings = @{
                sockopt = @{
                    tproxy = "tproxy"
                    mark = 255
                }
            }
        },
        @{
            listen = "127.0.0.1"
            port = 10880
            protocol = "socks"
            settings = @{
                udp = $true
            }
        }
    )
    
    # 2. Outbounds: Настраиваем прокси
    if ($Config.PSObject.Properties.Name -contains 'outbounds') {
        for ($i = 0; $i -lt $Config.outbounds.Count; $i++) {
            $outbound = $Config.outbounds[$i]
            $protocol = $outbound.protocol
            
            # Настраиваем основной прокси (VLESS/REALITY)
            if ($protocol -notin @('freedom', 'dns')) {
                if ($outbound.PSObject.Properties.Name -notcontains 'streamSettings') {
                    $outbound | Add-Member -MemberType NoteProperty -Name 'streamSettings' -Value @{}
                }
                if ($outbound.streamSettings.PSObject.Properties.Name -notcontains 'sockopt') {
                    $outbound.streamSettings | Add-Member -MemberType NoteProperty -Name 'sockopt' -Value @{}
                }
                
                $outbound.streamSettings.sockopt | Add-Member -MemberType NoteProperty -Name 'mark' -Value 255 -Force
                $outbound | Add-Member -MemberType NoteProperty -Name 'tag' -Value "proxy" -Force
            }
        }
    }
    
    # Гарантируем наличие прямого выхода
    $hasDirect = $false
    if ($Config.PSObject.Properties.Name -contains 'outbounds') {
        $hasDirect = ($Config.outbounds | Where-Object { $_.tag -eq 'direct' }).Count -gt 0
    } else {
        $Config | Add-Member -MemberType NoteProperty -Name 'outbounds' -Value @()
    }
    
    if (-not $hasDirect) {
        $Config.outbounds += @{
            protocol = "freedom"
            tag = "direct"
        }
    }
    
    # 3. Маршрутизация
    $Config | Add-Member -MemberType NoteProperty -Name 'routing' -Value @{
        rules = @(
            @{
                type = "field"
                inboundTag = @("tproxy-in")
                outboundTag = "proxy"
            }
        )
    } -Force
    
    # Удаляем секцию DNS
    if ($Config.PSObject.Properties.Name -contains 'dns') {
        $Config.PSObject.Properties.Remove('dns')
    }
    
    # Сохраняем результат
    $outputJson = $Config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($OutputPath, $outputJson, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "[+] Minimalisticheskiy konfig gotov: $OutputPath" -ForegroundColor Green
}

try {
    if (-not (Test-Path $InputFile)) {
        Write-Host "[-] Oshibka: Fail $InputFile ne naiden." -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        exit
    }
    
    Write-Host "[+] Chtenie konfiga: $InputFile" -ForegroundColor Cyan
    $jsonContent = Get-Content $InputFile -Encoding UTF8 -Raw | ConvertFrom-Json
    
    Write-Host "[+] Konvertaciya v TPROXY format..." -ForegroundColor Cyan
    Generate-MinimalTproxyConfig -Config $jsonContent -OutputPath $OutputFile
    
} catch {
    Write-Host "[-] Oshibka: $_" -ForegroundColor Red
}

Read-Host "`nPress Enter to exit"