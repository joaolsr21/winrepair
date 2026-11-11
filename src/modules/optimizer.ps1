# ==============================================================================
# Módulo: Otimizações de Desempenho e Limpeza
# ==============================================================================

function Clear-TempFiles {
    Write-ToolLog "Iniciando limpeza de arquivos temporários e logs do sistema..." "INFO"

    $targets = @(
        "$env:TEMP\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "$env:LOCALAPPDATA\CrashDumps\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
    )

    $deletedCount = 0
    foreach ($target in $targets) {
        if (Test-Path (Split-Path $target)) {
            try {
                $items = Get-ChildItem -Path $target -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $deletedCount++
                }
            } catch {
                # Alguns arquivos em uso pelo sistema não serão removidos (comportamento normal)
            }
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Lixeira esvaziada." "SUCCESS"
    } catch {
        Write-ToolLog "Lixeira já estava vazia ou indisponível." "INFO"
    }

    Write-ToolLog "Limpeza temporária concluída. Itens processados/removidos: $deletedCount." "SUCCESS"
}

function Clear-WindowsUpdateCache {
    Write-ToolLog "Parando serviços do Windows Update..." "INFO"
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "cryptSvc" -Force -ErrorAction SilentlyContinue

        $wuCachePath = "C:\Windows\SoftwareDistribution\Download\*"
        if (Test-Path (Split-Path $wuCachePath)) {
            Write-ToolLog "Removendo cache de downloads corrompidos/antigos do Windows Update..." "INFO"
            Remove-Item -Path $wuCachePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Reiniciando serviços do Windows Update..." "INFO"
        Start-Service -Name "cryptSvc" -ErrorAction SilentlyContinue
        Start-Service -Name "bits" -ErrorAction SilentlyContinue
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

        Write-ToolLog "Cache do Windows Update redefinido com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir cache do Windows Update: $_" "ERROR"
    }
}

function Optimize-SsdTrim {
    Write-ToolLog "Verificando unidades SSD para execução de TRIM (ReTrim)..." "INFO"
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
        foreach ($vol in $volumes) {
            Write-ToolLog "Otimizando unidade $($vol.DriveLetter): ..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue
        }
        Write-ToolLog "Comando TRIM enviado para todas as unidades elegíveis." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao executar TRIM nas unidades: $_" "ERROR"
    }
}

function Set-HibernationState {
    param(
        [Parameter(Mandatory=$true)]
        [bool]$Enable
    )

    try {
        if ($Enable) {
            powercfg.exe -h on
            Write-ToolLog "Hibernação ativada (arquivo hiberfil.sys habilitado)." "SUCCESS"
        } else {
            powercfg.exe -h off
            Write-ToolLog "Hibernação desativada. Espaço em disco liberado (hiberfil.sys excluído)." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao alterar estado de hibernação: $_" "ERROR"
    }
}

function Optimize-TelemetryAndPrivacy {
    Write-ToolLog "Configurando políticas de telemetria e diagnóstico do Windows..." "INFO"
    try {
        # Desabilitar serviço de telemetria conectada e experiências de usuário
        $diagService = Get-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
        if ($diagService) {
            Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço de Rastreamento de Diagnóstico (DiagTrack) desativado." "SUCCESS"
        }

        # Desabilitar dmwappushservice (WAP Push Service)
        $pushService = Get-Service -Name "dmwappushservice" -ErrorAction SilentlyContinue
        if ($pushService) {
            Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço dmwappushservice desativado." "SUCCESS"
        }

        # Registro: Nível de telemetria para o mínimo (Segurança / Básico)
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) {
            New-Item -Path $dataCollectionKey -Force | Out-Null
        }
        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force

        # Desativar ID de Anúncio
        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) {
            New-Item -Path $advertisingKey -Force | Out-Null
        }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

        Write-ToolLog "Configurações de privacidade e redução de telemetria aplicadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar telemetria: $_" "ERROR"
    }
}
