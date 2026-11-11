# ==============================================================================
# Módulo: Diagnóstico e Reparo de Rede / Internet
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
    Write-ToolLog "Iniciando redefinição da pilha TCP/IP e Winsock..." "INFO"
    try {
        $winsockResult = netsh winsock reset
        Write-ToolLog "Winsock redefinido. ($winsockResult)" "INFO"

        $tcpResult = netsh int ip reset
        Write-ToolLog "Pilha TCP/IP redefinida." "INFO"

        Write-ToolLog "Pilha de rede reinicializada com êxito. É recomendável reiniciar o computador." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir rede: $_" "ERROR"
    }
}

function Invoke-RenewDhcp {
    Write-ToolLog "Liberando concessões de IP ativas..." "INFO"
    try {
        ipconfig /release | Out-Null
        Start-Sleep -Seconds 1
        Write-ToolLog "Renovando endereço IP com o servidor DHCP..." "INFO"
        ipconfig /renew | Out-Null
        Write-ToolLog "Concessão de IP renovada com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao renovar concessão de IP: $_" "ERROR"
    }
}

function Set-CustomDns {
    param (
        [ValidateSet("Cloudflare", "Google", "DHCP")]
        [string]$Provider = "Cloudflare"
    )

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) {
        Write-ToolLog "Nenhum adaptador de rede físico ativo encontrado." "WARN"
        return
    }

    foreach ($adapter in $adapters) {
        Write-ToolLog "Configurando DNS no adaptador: $($adapter.Name)..." "INFO"
        try {
            if ($Provider -eq "Cloudflare") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses @("1.1.1.1", "1.0.0.1")
                Write-ToolLog "DNS Cloudflare (1.1.1.1 / 1.0.0.1) aplicado a $($adapter.Name)." "SUCCESS"
            }
            elseif ($Provider -eq "Google") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses @("8.8.8.8", "8.8.4.4")
                Write-ToolLog "DNS Google (8.8.8.8 / 8.8.4.4) aplicado a $($adapter.Name)." "SUCCESS"
            }
            elseif ($Provider -eq "DHCP") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-ToolLog "DNS restaurado para automático (DHCP) em $($adapter.Name)." "SUCCESS"
            }
        } catch {
            Write-ToolLog "Falha ao definir DNS em $($adapter.Name): $_" "ERROR"
        }
    }
}

function Restart-NetworkAdapters {
    Write-ToolLog "Reiniciando adaptadores de rede físicos..." "INFO"
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    foreach ($adapter in $adapters) {
        try {
            Write-ToolLog "Reiniciando $($adapter.Name)..." "INFO"
            Restart-NetAdapter -Name $adapter.Name -Confirm:$false
            Write-ToolLog "Adaptador $($adapter.Name) reiniciado." "SUCCESS"
        } catch {
            Write-ToolLog "Falha ao reiniciar $($adapter.Name): $_" "ERROR"
        }
    }
}
