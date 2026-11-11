# ==============================================================================
# Módulo: Criação e Customização de ISO / Imagem do Windows (DISM)
# ==============================================================================

function Get-WimImageInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WimPath
    )

    if (-not (Test-Path $WimPath)) {
        Write-ToolLog "Arquivo WIM/ESD não encontrado: $WimPath" "ERROR"
        return $null
    }

    try {
        $images = Get-WindowsImage -ImagePath $WimPath
        return $images
    } catch {
        Write-ToolLog "Falha ao obter informações do WIM: $_" "ERROR"
        return $null
    }
}

function Mount-CustomWim {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        [Parameter(Mandatory=$true)]
        [string]$MountDir,
        [int]$Index = 1
    )

    if (-not (Test-Path $MountDir)) {
        New-Item -ItemType Directory -Path $MountDir -Force | Out-Null
    }

    Write-ToolLog "Montando imagem $WimPath (Índice $Index) em $MountDir..." "INFO"
    try {
        Mount-WindowsImage -ImagePath $WimPath -Index $Index -Path $MountDir
        Write-ToolLog "Imagem montada com sucesso em $MountDir." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao montar imagem: $_" "ERROR"
    }
}

function Remove-ProvisionedBloatware {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MountDir,
        [string[]]$CustomAppList
    )

    $defaultBloat = @(
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.People",
        "Microsoft.Todos",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxGameOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Clipchamp.Clipchamp"
    )

    $appsToRemove = if ($CustomAppList -and $CustomAppList.Count -gt 0) { $CustomAppList } else { $defaultBloat }

    Write-ToolLog "Verificando pacotes AppX provisionados na imagem montada..." "INFO"
    try {
        $provisioned = Get-AppxProvisionedPackage -Path $MountDir
        $removedCount = 0

        foreach ($pkg in $provisioned) {
            foreach ($bloatName in $appsToRemove) {
                if ($pkg.DisplayName -like "*$bloatName*") {
                    Write-ToolLog "Removendo pacote: $($pkg.DisplayName)..." "INFO"
                    Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                    $removedCount++
                    break
                }
            }
        }
        Write-ToolLog "Remoção de bloatware concluída. Pacotes removidos: $removedCount." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao remover pacotes da imagem: $_" "ERROR"
    }
}

function Add-BypassHardwareChecksToWim {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MountDir
    )

    Write-ToolLog "Injetando chaves de bypass de requisitos (TPM 2.0, SecureBoot, RAM) no registro offline..." "INFO"
    $systemHive = Join-Path $MountDir "Windows\System32\config\SYSTEM"

    if (-not (Test-Path $systemHive)) {
        Write-ToolLog "Hive do sistema não encontrada em $systemHive" "ERROR"
        return
    }

    try {
        reg load HKLM\OFFLINE_SYSTEM "$systemHive" | Out-Null

        $setupLabConfig = "HKLM\OFFLINE_SYSTEM\Setup\LabConfig"
        if (-not (Test-Path $setupLabConfig)) {
            New-Item -Path $setupLabConfig -Force | Out-Null
        }

        # Bypass TPM, SecureBoot, RAM, Storage e CPU
        Set-ItemProperty -Path $setupLabConfig -Name "BypassTPMCheck" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $setupLabConfig -Name "BypassSecureBootCheck" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $setupLabConfig -Name "BypassRAMCheck" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $setupLabConfig -Name "BypassStorageCheck" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $setupLabConfig -Name "BypassCPUCheck" -Value 1 -Type DWord -Force

        # Bypass NRO (Permite conta local no Windows 11 OOBE)
        $oobeConfig = "HKLM\OFFLINE_SYSTEM\Setup\OOBE"
        if (-not (Test-Path $oobeConfig)) {
            New-Item -Path $oobeConfig -Force | Out-Null
        }
        Set-ItemProperty -Path $oobeConfig -Name "BypassNRO" -Value 1 -Type DWord -Force

        [gc]::Collect()
        reg unload HKLM\OFFLINE_SYSTEM | Out-Null
        Write-ToolLog "Requisitos de hardware contornados com sucesso na imagem offline." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao aplicar ajustes no registro offline: $_" "ERROR"
        reg unload HKLM\OFFLINE_SYSTEM -ErrorAction SilentlyContinue | Out-Null
    }
}

function Save-AndDismountWim {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MountDir,
        [bool]$Save = $true
    )

    Write-ToolLog "Desmontando imagem em $MountDir (Salvar=$Save)..." "INFO"
    try {
        if ($Save) {
            Dismount-WindowsImage -Path $MountDir -Save
            Write-ToolLog "Imagem salva e desmontada com sucesso." "SUCCESS"
        } else {
            Dismount-WindowsImage -Path $MountDir -Discard
            Write-ToolLog "Alterações descartadas e imagem desmontada." "INFO"
        }
    } catch {
        Write-ToolLog "Erro ao desmontar imagem: $_" "ERROR"
    }
}
