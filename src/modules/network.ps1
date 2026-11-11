# ==============================================================================
# Módulo Avançado: Diagnóstico, Otimizações e Reparo de Rede / Internet
# ==============================================================================

function Invoke-FlushDns {
    Write-ToolLog "Limpando o cache do resolvedor DNS..." "INFO"
    try {
        Clear-DnsClientCache
        Write-ToolLog "Cache DNS limpo com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao limpar cache DNS: $_" "ERROR"
    }
}

function Invoke-ResetNetworkStack {
    Write-ToolLog "Iniciando redefinição profunda da pilha TCP/IP e Winsock..." "INFO"
    try {
        netsh winsock reset | Out-Null
        netsh int ip reset | Out-Null
        netsh int ipv6 reset | Out-Null
        netsh advfirewall reset | Out-Null
        Write-ToolLog "Winsock, IPv4, IPv6 e Firewall redefinidos para os padrões de fábrica." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir pilha de rede: $_" "ERROR"
    }
}

function Invoke-RenewDhcp {
    Write-ToolLog "Liberando e renovando endereço IP via DHCP..." "INFO"
    try {
        ipconfig /release | Out-Null
        Start-Sleep -Milliseconds 800
        ipconfig /renew | Out-Null
        Write-ToolLog "Concessão de IP renovada com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao renovar concessão DHCP: $_" "ERROR"
    }
}

function Set-QuickDnsProvider {
    param(
        [ValidateSet("Cloudflare", "Google", "Quad9", "AdGuard", "DHCP")]
        [string]$Provider = "Cloudflare"
    )

    $dnsServers = switch ($Provider) {
        "Cloudflare" { @("1.1.1.1", "1.0.0.1") }
        "Google"     { @("8.8.8.8", "8.8.4.4") }
        "Quad9"      { @("9.9.9.9", "149.112.112.112") }     # Foco em Segurança/Bloqueio de Malware
        "AdGuard"    { @("94.140.14.14", "94.140.15.15") }   # Foco em Bloqueio de Anúncios e Rastreadores
        "DHCP"       { $null }
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) {
        Write-ToolLog "Nenhum adaptador físico ativo encontrado." "WARN"
        return
    }

    foreach ($adapter in $adapters) {
        try {
            if ($Provider -eq "DHCP") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-ToolLog "[$($adapter.Name)] DNS restaurado para automático (DHCP)." "SUCCESS"
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers
                Write-ToolLog "[$($adapter.Name)] DNS $Provider aplicado: $($dnsServers -join ', ')." "SUCCESS"
            }
        } catch {
            Write-ToolLog "Falha ao definir DNS em $($adapter.Name): $_" "ERROR"
        }
    }
}

function Optimize-TcpLatencyAndThroughput {
    Write-ToolLog "Aplicando otimizações avançadas na pilha TCP/IP (Baixa Latência & Alto Rendimento)..." "INFO"
    try {
        # 1. Habilitar ajuste automático de janela TCP
        netsh int tcp set global autotuninglevel=normal | Out-Null
        Write-ToolLog "TCP Auto-Tuning configurado para Normal." "INFO"

        # 2. Habilitar RSS (Receive Side Scaling) para distribuir pacotes de rede entre os núcleos da CPU
        netsh int tcp set global rss=enabled | Out-Null
        Write-ToolLog "RSS (Receive Side Scaling) habilitado." "INFO"

        # 3. Habilitar ECN (Explicit Congestion Notification)
        netsh int tcp set global ecncapability=enabled | Out-Null
        Write-ToolLog "ECN (Explicit Congestion Notification) habilitado." "INFO"

        # 4. Configurar algoritmo de congestionamento TCP para CTCP ou CUBIC (se disponível)
        try {
            netsh int tcp set supplemental template=custom congestionprovider=ctcp | Out-Null
        } catch {}

        # 5. Ajustes de Registro: Desativar Limitação de Rede (Network Throttling Index) e Acelerar ACK
        $gamingNetKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $gamingNetKey) {
            Set-ItemProperty -Path $gamingNetKey -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
            Set-ItemProperty -Path $gamingNetKey -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Otimizações de latência e taxa de transferência TCP aplicadas com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao otimizar TCP/IP: $_" "ERROR"
    }
}

function Test-NetworkQuality {
    Write-ToolLog "Iniciando diagnóstico rápido de qualidade da conexão..." "INFO"
    try {
        $targets = @("1.1.1.1", "8.8.8.8")
        foreach ($target in $targets) {
            $ping = Test-Connection -ComputerName $target -Count 4 -ErrorAction SilentlyContinue
            if ($ping) {
                $avgLatency = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 1)
                $packetLoss = [math]::Round(((4 - $ping.Count) / 4) * 100, 1)
                Write-ToolLog "Destino: $target | Latência Média: ${avgLatency}ms | Perda de Pacotes: ${packetLoss}%" "INFO"
            } else {
                Write-ToolLog "Falha de comunicação com o host $target." "WARN"
            }
        }

        # Obter IP Externo
        try {
            $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3).Trim()
            Write-ToolLog "Endereço IP Público: $publicIp" "SUCCESS"
        } catch {
            Write-ToolLog "Não foi possível obter o IP público externo." "INFO"
        }
    } catch {
        Write-ToolLog "Erro no diagnóstico de rede: $_" "ERROR"
    }
}

function Restart-NetworkAdapters {
    Write-ToolLog "Reiniciando adaptadores de rede físicos..." "INFO"
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    foreach ($adapter in $adapters) {
        try {
            Restart-NetAdapter -Name $adapter.Name -Confirm:$false
            Write-ToolLog "Adaptador $($adapter.Name) reiniciado." "SUCCESS"
        } catch {
            Write-ToolLog "Falha ao reiniciar $($adapter.Name): $_" "ERROR"
        }
    }
}
