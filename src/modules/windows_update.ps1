# ==============================================================================
# Módulo: Gerenciamento do Windows Update (Estilo Chris Titus Updates)
# ==============================================================================

function Set-WindowsUpdateRecommended {
    Write-ToolLog "Configurando Windows Update para o Modo Recomendado (Apenas Segurança Estável)..." "INFO"
    Write-ToolLog "Atrasa atualizações de recursos instáveis por 1 ano e evita reinicializações forçadas." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        
        $auPath = "$wuPath\AU"
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }

        # Não reiniciar automaticamente se houver usuário conectado
        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        # Notificar para agendar reinicialização
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Type DWord -Force

        # Adiar atualizações de recursos por 365 dias (estabilidade máxima)
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force

        # Adiar atualizações de qualidade por 4 dias (para evitar bugs de lançamento)
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 4 -Type DWord -Force

        Write-ToolLog "Windows Update configurado no modo 'Segurança e Estabilidade Recomendada'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar Windows Update: $_" "ERROR"
    }
}

function Reset-WindowsUpdateDefault {
    Write-ToolLog "Restaurando Windows Update para as configurações originais de fábrica..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (Test-Path $wuPath) {
            Remove-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue
        }

        $auPath = "$wuPath\AU"
        if (Test-Path $auPath) {
            Remove-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $auPath -Name "AUOptions" -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Windows Update restaurado para o padrão original da Microsoft." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao restaurar Windows Update: $_" "ERROR"
    }
}

function Pause-WindowsUpdateExtended {
    Write-ToolLog "Pausando atualizações do Windows Update por período estendido..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        
        $futureDate = "2042-01-01T00:00:00Z"
        Set-ItemProperty -Path $wuPath -Name "PauseUpdatesExpiryTime" -Value $futureDate -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseFeatureUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseQualityUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force

        Write-ToolLog "Atualizações do Windows pausadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao pausar atualizações: $_" "ERROR"
    }
}
