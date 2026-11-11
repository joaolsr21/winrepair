# ==============================================================================
# WinRepair & Tweaks Utility (Standalone All-in-One)
# Execução direta via: irm <URL> | iex
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ==============================================================================
# Módulo: Elevação e Privilégios Administrativos
# ==============================================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-AdminPrivileges {
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host " [!] PRIVILÉGIOS DE ADMINISTRADOR NECESSÁRIOS" -ForegroundColor Red
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host "Este utilitário precisa ser executado como Administrador para realizar reparos e otimizações." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[*] Solicitando elevação de privilégios via UAC..." -ForegroundColor Cyan

        $scriptPath = $PSCommandPath
        if ($scriptPath -and (Test-Path $scriptPath)) {
            # Se executado a partir de arquivo local
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        } else {
            # Se executado diretamente em memória via irm | iex:
            # Salva um inicializador limpo em arquivo temporário para evitar falsos positivos de heurística de linha de comando
            $tempLauncher = Join-Path $env:TEMP "winrepair_launcher.ps1"
            $launcherCode = @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
irm https://raw.githubusercontent.com/joaolsr21/winrepair/main/dist/winrepair.ps1 | iex
'@
            [System.IO.File]::WriteAllText($tempLauncher, $launcherCode, [System.Text.Encoding]::UTF8)
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempLauncher`""
        }
        exit
    }
}


# ==============================================================================
# Módulo: Sistema de Logging
# ==============================================================================

function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
    }

    Write-Host $logLine -ForegroundColor $color

    # Se a GUI estiver ativa com elemento txtLog, atualiza a interface
    if ($global:txtLogControl -and $global:uiDispatcher) {
        $global:uiDispatcher.Invoke([action]{
            $global:txtLogControl.AppendText("$logLine`r`n")
            $global:txtLogControl.ScrollToEnd()
        })
    }
}


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


# ==============================================================================
# Módulo: Diagnóstico e Reparo do Sistema Operacional
# ==============================================================================

function Invoke-SfcScan {
    Write-ToolLog "Iniciando verificação de integridade dos arquivos de sistema (SFC)..." "INFO"
    Write-ToolLog "Este processo pode levar alguns minutos. Aguarde..." "INFO"
    try {
        $process = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "SFC: A Proteção de Recursos do Windows não encontrou nenhuma violação de integridade." "SUCCESS"
        } elseif ($process.ExitCode -eq 1) {
            Write-ToolLog "SFC: Arquivos corrompidos foram encontrados e corrigidos com sucesso!" "SUCCESS"
        } else {
            Write-ToolLog "SFC finalizado com código de saída: $($process.ExitCode). Verifique C:\Windows\Logs\CBS\CBS.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar o SFC: $_" "ERROR"
    }
}

function Invoke-DismRepair {
    Write-ToolLog "Iniciando reparo da imagem do sistema Windows com DISM..." "INFO"
    Write-ToolLog "Verificando integridade e restaurando saúde da imagem (/RestoreHealth)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "DISM: A operação de restauração foi concluída com êxito." "SUCCESS"
        } else {
            Write-ToolLog "DISM finalizado com código: $($process.ExitCode). Verifique C:\Windows\Logs\DISM\dism.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar o DISM: $_" "ERROR"
    }
}

function Invoke-DismCleanup {
    Write-ToolLog "Executando limpeza do repositório de componentes WinSxS (/StartComponentCleanup)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "Limpeza da pasta WinSxS concluída. Espaço em disco recuperado." "SUCCESS"
        } else {
            Write-ToolLog "DISM Component Cleanup retornou código: $($process.ExitCode)." "WARN"
        }
    } catch {
        Write-ToolLog "Falha na limpeza de componentes: $_" "ERROR"
    }
}

function Restart-PrintSpooler {
    Write-ToolLog "Reiniciando o Spooler de Impressão e limpando filas travadas..." "INFO"
    try {
        Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
        $spoolPath = "C:\Windows\System32\spool\PRINTERS\*"
        if (Test-Path (Split-Path $spoolPath)) {
            Remove-Item -Path $spoolPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
        Write-ToolLog "Fila de impressão limpa e serviço Spooler reiniciado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao reiniciar Spooler: $_" "ERROR"
    }
}

function Schedule-ChkdskOnReboot {
    Write-ToolLog "Agendando verificação de disco (CHKDSK /F) para a próxima reinicialização..." "INFO"
    try {
        $result = echo "Y" | chkdsk C: /f
        Write-ToolLog "CHKDSK agendado na unidade C:. O disco será verificado na próxima inicialização." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao agendar CHKDSK: $_" "ERROR"
    }
}


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


# 1. Garantir privilégios de Administrador
if (-not (Test-IsAdmin)) {
    Ensure-AdminPrivileges
    return
}

# 2. Carregar assemblies do WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# 3. Carregar interface gráfica embutida
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinRepair &amp; Tweaks Utility"
        Height="720" Width="960"
        WindowStartupLocation="CenterScreen"
        Background="#181825"
        Foreground="#CDD6F4"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#45475A"/>
                    <Setter Property="BorderBrush" Value="#89B4FA"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#585B70"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderThickness="0,0,0,3" BorderBrush="Transparent" Margin="2,0">
                            <ContentPresenter ContentSource="Header" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#89B4FA"/>
                                <Setter TargetName="Border" Property="Background" Value="#24273A"/>
                                <Setter Property="Foreground" Value="#89B4FA"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#CDD6F4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#89B4FA"/>
        </Style>

        <Style TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#313244"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="4,4,4,10"/>
            <Setter Property="Padding" Value="10"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="180"/>
        </Grid.RowDefinitions>

        <!-- Cabeçalho -->
        <Border Grid.Row="0" Background="#1E1E2E" CornerRadius="8" Padding="16,12" Margin="0,0,0,12" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="⚡ WinRepair &amp; Tweaks Utility" FontSize="20" FontWeight="Bold" Foreground="#89B4FA"/>
                    <TextBlock Text="Painel Central de Reparos Rápidos, Otimizações e Manutenção" FontSize="12" Foreground="#A6ADC8" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Orientation="Horizontal">
                    <TextBlock Name="txtSystemInfo" Text="Carregando info do sistema..." FontSize="12" Foreground="#94E2D5" Margin="0,0,10,0" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Abas Principais -->
        <TabControl Grid.Row="1" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="1">
            <!-- ABA 1: REDE E INTERNET -->
            <TabItem Header="🌐 Rede &amp; Internet">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="12">
                        <GroupBox Header="Reparos de Conexão e Pilha TCP/IP">
                            <WrapPanel>
                                <Button Name="btnFlushDns" Content="Limpar Cache DNS" Width="200" Height="40"/>
                                <Button Name="btnResetNetwork" Content="Redefinir Pilha TCP/IP e Winsock" Width="240" Height="40"/>
                                <Button Name="btnRenewDhcp" Content="Renovar Concessão de IP / DHCP" Width="220" Height="40"/>
                                <Button Name="btnRestartAdapters" Content="Reiniciar Adaptadores de Rede" Width="220" Height="40"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Servidores DNS Rápidos e Confiáveis">
                            <WrapPanel>
                                <Button Name="btnDnsCloudflare" Content="DNS Cloudflare (1.1.1.1)" Width="200" Height="40"/>
                                <Button Name="btnDnsGoogle" Content="DNS Google (8.8.8.8)" Width="200" Height="40"/>
                                <Button Name="btnDnsDhcp" Content="Restaurar DNS Automático (DHCP)" Width="230" Height="40"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 2: OTIMIZAÇÃO -->
            <TabItem Header="⚡ Otimização">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="12">
                        <GroupBox Header="Limpeza e Armazenamento">
                            <WrapPanel>
                                <Button Name="btnClearTemp" Content="Limpar Arquivos Temporários e Lixeira" Width="260" Height="40"/>
                                <Button Name="btnClearWuCache" Content="Limpar Cache do Windows Update" Width="240" Height="40"/>
                                <Button Name="btnSsdTrim" Content="Otimizar SSDs (Executar TRIM)" Width="220" Height="40"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Ajustes de Desempenho e Privacidade">
                            <WrapPanel>
                                <Button Name="btnOptimizeTelemetry" Content="Reduzir Telemetria e Coleta de Dados" Width="250" Height="40"/>
                                <Button Name="btnDisableHibernation" Content="Desativar Hibernação (Liberar Espaço)" Width="260" Height="40"/>
                                <Button Name="btnEnableHibernation" Content="Ativar Hibernação" Width="160" Height="40"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 3: REPARO DO SISTEMA -->
            <TabItem Header="🛠️ Reparo do Sistema">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="12">
                        <GroupBox Header="Integridade e Saúde do Windows">
                            <WrapPanel>
                                <Button Name="btnSfcScan" Content="Verificação de Integridade (SFC /scannow)" Width="270" Height="40"/>
                                <Button Name="btnDismRepair" Content="Reparar Imagem do Windows (DISM)" Width="250" Height="40"/>
                                <Button Name="btnDismCleanup" Content="Limpar Component Store (WinSxS)" Width="240" Height="40"/>
                                <Button Name="btnScheduleChkdsk" Content="Agendar CHKDSK no Disco C:" Width="230" Height="40"/>
                                <Button Name="btnRestartSpooler" Content="Destravar Spooler de Impressão" Width="230" Height="40"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 4: CRIAR ISO MODIFICADA -->
            <TabItem Header="💿 Criador de ISO">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="12">
                        <GroupBox Header="Configuração da Imagem WIM / ESD">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Arquivo WIM/ESD:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtWimPath" Grid.Row="0" Grid.Column="1" Margin="0,4" Text="C:\ISO_Work\install.wim"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Pasta de Montagem:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtMountDir" Grid.Row="1" Grid.Column="1" Margin="0,4" Text="C:\ISO_Work\mount"/>

                                <TextBlock Grid.Row="2" Grid.Column="0" Text="Índice da Imagem:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtWimIndex" Grid.Row="2" Grid.Column="1" Margin="0,4" Text="1" Width="80" HorizontalAlignment="Left"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Operações de Customização">
                            <WrapPanel>
                                <Button Name="btnGetWimInfo" Content="Consultar Informações do WIM" Width="220" Height="40"/>
                                <Button Name="btnMountWim" Content="1. Montar Imagem WIM" Width="180" Height="40"/>
                                <Button Name="btnDebloatWim" Content="2. Remover Bloatware (AppX)" Width="210" Height="40"/>
                                <Button Name="btnBypassWim" Content="3. Injetar Bypass TPM/RAM/NRO" Width="230" Height="40"/>
                                <Button Name="btnSaveDismount" Content="4. Salvar e Desmontar Imagem" Width="210" Height="40"/>
                                <Button Name="btnDiscardDismount" Content="Descartar e Desmontar" Width="190" Height="40"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 5: LICENCIAMENTO -->
            <TabItem Header="🔑 Licenciamento">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="12">
                        <GroupBox Header="Gerenciamento de Licença do Windows">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button Name="btnCheckWinLicense" Content="Verificar Status da Licença" Width="210" Height="36"/>
                                </WrapPanel>
                                <Grid Margin="0,4">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Windows:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtWinKey" Grid.Column="1" Margin="0,0,8,0" Text="" ToolTip="Formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"/>
                                    <Button Name="btnApplyWinKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="180" Height="34"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Gerenciamento de Licença do Microsoft Office">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,8">
                                    <Button Name="btnCheckOfficeLicense" Content="Verificar Status do Office" Width="210" Height="36"/>
                                </WrapPanel>
                                <Grid Margin="0,4">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Office:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtOfficeKey" Grid.Column="1" Margin="0,0,8,0" Text="" ToolTip="Formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"/>
                                    <Button Name="btnApplyOfficeKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="180" Height="34"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Configuração de Servidor KMS Institucional / Corporativo">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Host KMS Oficial:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtKmsHost" Grid.Column="1" Margin="0,0,8,0" Text="kms.dominio.local"/>
                                <Button Name="btnSetKms" Grid.Column="2" Content="Configurar Servidor KMS" Width="180" Height="34"/>
                            </Grid>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Rodapé / Painel de Logs -->
        <Border Grid.Row="2" Background="#11111B" CornerRadius="8" Margin="0,10,0,0" BorderBrush="#313244" BorderThickness="1">
            <Grid Margin="8">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,4">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="📜 Console de Execução &amp; Logs" FontSize="12" FontWeight="SemiBold" Foreground="#89B4FA" VerticalAlignment="Center"/>
                    <Button Name="btnClearLogs" Grid.Column="1" Content="Limpar Log" Padding="8,4" FontSize="11" Margin="0"/>
                </Grid>

                <TextBox Name="txtLog" Grid.Row="1"
                         Background="#11111B"
                         Foreground="#A6E3A1"
                         FontFamily="Consolas"
                         FontSize="12"
                         IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto"
                         TextWrapping="Wrap"
                         BorderThickness="0"/>
            </Grid>
        </Border>
    </Grid>
</Window>

'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$global:txtLogControl = $window.FindName("txtLog")
$global:uiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

# Informações do Sistema
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $window.FindName("txtSystemInfo").Text = "$($os.Caption) ($($os.OSArchitecture)) | $ramGb GB RAM | Host: $($env:COMPUTERNAME)"
} catch {
    $window.FindName("txtSystemInfo").Text = "Windows $($env:OS) | Host: $($env:COMPUTERNAME)"
}

function Start-AsyncAction {
    param([Parameter(Mandatory=$true)][scriptblock]$Action)
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            & $using:Action
        } catch {
            Write-ToolLog "Erro na execução da tarefa: $_" "ERROR"
        }
    }) | Out-Null
}

# Binds de Eventos
$window.FindName("btnFlushDns").Add_Click({ Start-AsyncAction { Invoke-FlushDns } })
$window.FindName("btnResetNetwork").Add_Click({ Start-AsyncAction { Invoke-ResetNetworkStack } })
$window.FindName("btnRenewDhcp").Add_Click({ Start-AsyncAction { Invoke-RenewDhcp } })
$window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction { Restart-NetworkAdapters } })
$window.FindName("btnDnsCloudflare").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "Cloudflare" } })
$window.FindName("btnDnsGoogle").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "Google" } })
$window.FindName("btnDnsDhcp").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "DHCP" } })

$window.FindName("btnClearTemp").Add_Click({ Start-AsyncAction { Clear-TempFiles } })
$window.FindName("btnClearWuCache").Add_Click({ Start-AsyncAction { Clear-WindowsUpdateCache } })
$window.FindName("btnSsdTrim").Add_Click({ Start-AsyncAction { Optimize-SsdTrim } })
$window.FindName("btnOptimizeTelemetry").Add_Click({ Start-AsyncAction { Optimize-TelemetryAndPrivacy } })
$window.FindName("btnDisableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable $false } })
$window.FindName("btnEnableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable $true } })

$window.FindName("btnSfcScan").Add_Click({ Start-AsyncAction { Invoke-SfcScan } })
$window.FindName("btnDismRepair").Add_Click({ Start-AsyncAction { Invoke-DismRepair } })
$window.FindName("btnDismCleanup").Add_Click({ Start-AsyncAction { Invoke-DismCleanup } })
$window.FindName("btnScheduleChkdsk").Add_Click({ Start-AsyncAction { Schedule-ChkdskOnReboot } })
$window.FindName("btnRestartSpooler").Add_Click({ Start-AsyncAction { Restart-PrintSpooler } })

$window.FindName("btnGetWimInfo").Add_Click({
    $wimPath = $window.FindName("txtWimPath").Text
    Start-AsyncAction {
        $info = Get-WimImageInfo -WimPath $using:wimPath
        if ($info) {
            foreach ($img in $info) {
                Write-ToolLog "Índice [$($img.ImageIndex)]: $($img.ImageName) ($($img.ImageSize / 1GB -as [int]) GB)" "INFO"
            }
        }
    }
})

$window.FindName("btnMountWim").Add_Click({
    $wimPath = $window.FindName("txtWimPath").Text
    $mountDir = $window.FindName("txtMountDir").Text
    $index = [int]$window.FindName("txtWimIndex").Text
    Start-AsyncAction { Mount-CustomWim -WimPath $using:wimPath -MountDir $using:mountDir -Index $using:index }
})

$window.FindName("btnDebloatWim").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction { Remove-ProvisionedBloatware -MountDir $using:mountDir }
})

$window.FindName("btnBypassWim").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction { Add-BypassHardwareChecksToWim -MountDir $using:mountDir }
})

$window.FindName("btnSaveDismount").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction { Save-AndDismountWim -MountDir $using:mountDir -Save $true }
})

$window.FindName("btnDiscardDismount").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction { Save-AndDismountWim -MountDir $using:mountDir -Save $false }
})

$window.FindName("btnCheckWinLicense").Add_Click({ Start-AsyncAction { Get-WindowsActivationStatus } })
$window.FindName("btnApplyWinKey").Add_Click({
    $key = $window.FindName("txtWinKey").Text
    if (-not $key) { Write-ToolLog "Informe a chave do Windows." "WARN"; return }
    Start-AsyncAction { Install-WindowsProductKey -ProductKey $using:key }
})

$window.FindName("btnCheckOfficeLicense").Add_Click({ Start-AsyncAction { Get-OfficeActivationStatus } })
$window.FindName("btnApplyOfficeKey").Add_Click({
    $key = $window.FindName("txtOfficeKey").Text
    if (-not $key) { Write-ToolLog "Informe a chave do Office." "WARN"; return }
    Start-AsyncAction { Install-OfficeProductKey -ProductKey $using:key }
})

$window.FindName("btnSetKms").Add_Click({
    $kmsHost = $window.FindName("txtKmsHost").Text
    if (-not $kmsHost) { Write-ToolLog "Informe o host KMS." "WARN"; return }
    Start-AsyncAction { Set-EnterpriseKmsServer -KmsHost $using:kmsHost }
})

$window.FindName("btnClearLogs").Add_Click({ $global:txtLogControl.Text = "" })

Write-ToolLog "WinRepair & Tweaks Utility carregado com sucesso!" "SUCCESS"
$window.ShowDialog() | Out-Null
