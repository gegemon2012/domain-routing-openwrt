# xray_to_sing-box_tproxy_converter.ps1
# Конвертирует Xray/Amnezia конфиг в Sing-Box формат

param(
    [string]$InputFile = "amnezia_for_xray.json",
    [string]$OutputFile = "config_singbox.json"
)

function Convert-XrayToSingBox {
    param($XrayConfig)
    
    # Извлекаем основные параметры из первого outbound
    $xOut = $XrayConfig.outbounds[0]
    $vnext = $xOut.settings.vnext[0]
    $user = $vnext.users[0]
    $reality = $xOut.streamSettings.realitySettings
    
    # Формируем структуру Sing-Box
    $sbConfig = @{
        log = @{
            level = "error"
        }
        inbounds = @(
            @{
                type = "tproxy"
                tag = "tproxy-in"
                listen = "::"
                listen_port = 12345
                sniff = $true
                sniff_override_destination = $true
            }
        )
        outbounds = @(
            @{
                type = "vless"
                tag = "proxy"
                server = $vnext.address
                server_port = $vnext.port
                uuid = $user.id
                flow = if ($user.PSObject.Properties.Name -contains 'flow') { $user.flow } else { "" }
                network = "tcp"
                tls = @{
                    enabled = $true
                    server_name = if ($reality.PSObject.Properties.Name -contains 'serverName') { $reality.serverName } else { "" }
                    utls = @{
                        enabled = $true
                        fingerprint = if ($reality.PSObject.Properties.Name -contains 'fingerprint') { $reality.fingerprint } else { "chrome" }
                    }
                    reality = @{
                        enabled = $true
                        public_key = if ($reality.PSObject.Properties.Name -contains 'publicKey') { $reality.publicKey } else { "" }
                        short_id = if ($reality.PSObject.Properties.Name -contains 'shortId') { $reality.shortId } else { "" }
                    }
                }
            },
            @{
                type = "direct"
                tag = "direct"
            }
        )
        route = @{
            auto_detect_interface = $true
        }
    }
    
    return $sbConfig
}

try {
    if (-not (Test-Path $InputFile)) {
        Write-Host "[-] Oshibka: Fail $InputFile ne naiden." -ForegroundColor Red
        Read-Host "`nPress Enter to exit"
        exit
    }
    
    Write-Host "[+] Chtenie konfiga: $InputFile" -ForegroundColor Cyan
    $jsonContent = Get-Content $InputFile -Encoding UTF8 -Raw | ConvertFrom-Json
    
    Write-Host "[+] Konvertaciya v Sing-Box format..." -ForegroundColor Cyan
    $result = Convert-XrayToSingBox -XrayConfig $jsonContent
    
    Write-Host "[+] Sohranenie rezultata..." -ForegroundColor Cyan
    $resultJson = $result | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($OutputFile, $resultJson, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "[+] Konfig uspeshno sozdan: $OutputFile" -ForegroundColor Green
    
} catch {
    Write-Host "[-] Oshibka: $_" -ForegroundColor Red
}

Read-Host "`nPress Enter to exit"