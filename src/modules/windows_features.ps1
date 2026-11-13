# ==============================================================================
# Módulo: Recursos Opcionais do Windows
# ==============================================================================

function Get-FeatureStatus {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($f.State -eq 'Enabled')
    } catch {
        return $false
    }
}

function Enable-WslFeature {
    Write-ToolLog "Habilitando Subsistema Windows para Linux (WSL) e Plataforma de Máquina Virtual..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart -ErrorAction Stop | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "WSL 2 habilitado com sucesso. (Reinicialização necessária para concluir)." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar WSL: $_" "ERROR"
    }
}

function Enable-WindowsSandbox {
    Write-ToolLog "Habilitando Área Restrita do Windows (Windows Sandbox)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Windows Sandbox habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Sandbox: $_" "ERROR"
    }
}

function Enable-HyperVFeature {
    Write-ToolLog "Habilitando Hyper-V e Ferramentas de Gerenciamento..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Hyper-V habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Hyper-V: $_" "ERROR"
    }
}

function Enable-NetFramework35 {
    Write-ToolLog "Instalando suporte ao .NET Framework 3.5 (.NET 2.0 e 3.0)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog ".NET Framework 3.5 instalado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao instalar .NET 3.5: $_" "ERROR"
    }
}
