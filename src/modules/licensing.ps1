# ==============================================================================
# Módulo: Gerenciamento e Ativação de Licenças (Windows & Microsoft Office)
# ==============================================================================

function Get-WindowsActivationStatus {
    Write-ToolLog "Consultando status atual de licenciamento do Windows..." "INFO"
    try {
        $wpa = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.ApplicationId -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Select-Object -First 1
        
        $statusText = switch ($wpa.LicenseStatus) {
            0 { "Não Licenciado" }
            1 { "Licenciado / Ativado Permanente" }
            2 { "Período OOBE Grace" }
            3 { "Período de Tolerância (Grace)" }
            4 { "Período de Não Genuinidade" }
            5 { "Notificação de Tolerância" }
            default { "Status Desconhecido ($($wpa.LicenseStatus))" }
        }

        Write-ToolLog "Edição: $($wpa.Name)" "INFO"
        Write-ToolLog "Status da Licença: $statusText" $(if ($wpa.LicenseStatus -eq 1) { "SUCCESS" } else { "WARN" })
        Write-ToolLog "Chave Parcial Instalada: ...-$($wpa.PartialProductKey)" "INFO"
        return $statusText
    } catch {
        Write-ToolLog "Falha ao consultar WMI. Executando slmgr.vbs /xpr..." "WARN"
        $slmgrOut = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /xpr
        Write-ToolLog "$slmgrOut" "INFO"
    }
}

function Install-WindowsProductKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductKey
    )

    $cleanKey = $ProductKey.Trim().ToUpper()
    if ($cleanKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
        Write-ToolLog "Formato de chave inválido! Utilize o formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" "ERROR"
        return
    }

    Write-ToolLog "Instalando chave de produto no Windows ($cleanKey)..." "INFO"
    try {
        $ipkResult = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /ipk $cleanKey
        Write-ToolLog "$ipkResult" "INFO"

        Write-ToolLog "Solicitando ativação online junto aos servidores de licenciamento da Microsoft..." "INFO"
        $atoResult = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /ato
        Write-ToolLog "$atoResult" "SUCCESS"

        Get-WindowsActivationStatus | Out-Null
    } catch {
        Write-ToolLog "Erro durante o processo de ativação do Windows: $_" "ERROR"
    }
}

function Find-OfficeOsppPath {
    $possiblePaths = @(
        "${env:ProgramFiles}\Microsoft Office\Office16\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
        "${env:ProgramFiles}\Microsoft Office\Office15\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS",
        "${env:ProgramFiles}\Microsoft Office\Office14\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office14\OSPP.VBS"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Get-OfficeActivationStatus {
    Write-ToolLog "Localizando instalação do Microsoft Office..." "INFO"
    $ospp = Find-OfficeOsppPath

    if (-not $ospp) {
        Write-ToolLog "Nenhuma instalação corporativa/padrão do Microsoft Office com ospp.vbs foi encontrada neste computador." "WARN"
        return
    }

    Write-ToolLog "Script de licenciamento encontrado em: $ospp" "INFO"
    try {
        $statusOut = cscript.exe //NoLogo "$ospp" /dstatus
        Write-ToolLog "$statusOut" "INFO"
    } catch {
        Write-ToolLog "Erro ao consultar status do Office: $_" "ERROR"
    }
}

function Install-OfficeProductKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductKey
    )

    $cleanKey = $ProductKey.Trim().ToUpper()
    if ($cleanKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
        Write-ToolLog "Formato de chave inválido! Utilize o padrão: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" "ERROR"
        return
    }

    $ospp = Find-OfficeOsppPath
    if (-not $ospp) {
        Write-ToolLog "Instalação do Microsoft Office não encontrada." "ERROR"
        return
    }

    Write-ToolLog "Instalando chave de produto no Microsoft Office..." "INFO"
    try {
        $argKey = "/inpkey:$cleanKey"
        $inpResult = cscript.exe //NoLogo "$ospp" $argKey
        Write-ToolLog "$inpResult" "INFO"

        Write-ToolLog "Tentando ativação do Office..." "INFO"
        $actResult = cscript.exe //NoLogo "$ospp" /act
        Write-ToolLog "$actResult" "SUCCESS"

        Get-OfficeActivationStatus
    } catch {
        Write-ToolLog "Erro ao ativar Office: $_" "ERROR"
    }
}

function Set-EnterpriseKmsServer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$KmsHost,
        [int]$Port = 1688
    )

    Write-ToolLog "Configurando servidor KMS institucional ($($KmsHost):$($Port))..." "INFO"
    try {
        $kmsTarget = "$($KmsHost):$($Port)"
        cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /skms $kmsTarget
        Write-ToolLog "Servidor KMS do Windows configurado." "SUCCESS"

        $ospp = Find-OfficeOsppPath
        if ($ospp) {
            $argHost = "/sethst:$($KmsHost)"
            $argPort = "/setprt:$($Port)"
            cscript.exe //NoLogo "$ospp" $argHost
            cscript.exe //NoLogo "$ospp" $argPort
            Write-ToolLog "Servidor KMS do Office configurado." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao configurar KMS: $_" "ERROR"
    }
}
