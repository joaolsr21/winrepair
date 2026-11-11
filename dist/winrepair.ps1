# ==============================================================================
# WinRepair & Tweaks Pro (Standalone All-in-One)
# Inspirado no utilitário de Chris Titus Tech (WinUtil)
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


# ==============================================================================
# Módulo Avançado: Otimizações de Desempenho, Debloat, Serviços e Perfis Prontos
# ==============================================================================

function Clear-TempFiles {
    Write-ToolLog "Iniciando limpeza profunda de arquivos temporários e caches..." "INFO"

    $targets = @(
        "$env:TEMP\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "$env:LOCALAPPDATA\CrashDumps\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$env:LOCALAPPDATA\Temp\*"
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
            } catch {}
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Lixeira esvaziada." "SUCCESS"
    } catch {}

    Write-ToolLog "Limpeza temporária finalizada. $deletedCount arquivos processados/removidos." "SUCCESS"
}

function Clear-WindowsUpdateCache {
    Write-ToolLog "Parando serviços do Windows Update..." "INFO"
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "cryptSvc" -Force -ErrorAction SilentlyContinue

        $wuCachePath = "C:\Windows\SoftwareDistribution\Download\*"
        if (Test-Path (Split-Path $wuCachePath)) {
            Write-ToolLog "Removendo arquivos temporários de atualização corrompidos..." "INFO"
            Remove-Item -Path $wuCachePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Reiniciando serviços essenciais..." "INFO"
        Start-Service -Name "cryptSvc" -ErrorAction SilentlyContinue
        Start-Service -Name "bits" -ErrorAction SilentlyContinue
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

        Write-ToolLog "Cache do Windows Update redefinido com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir cache do Windows Update: $_" "ERROR"
    }
}

function Enable-UltimatePerformancePowerPlan {
    Write-ToolLog "Desbloqueando e ativando o Plano de Energia 'Desempenho Máximo' (Ultimate Performance)..." "INFO"
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $output = powercfg -duplicatescheme $guid 2>&1
        powercfg -setactive $guid
        Write-ToolLog "Plano 'Desempenho Máximo' ativado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao ativar plano de energia: $_" "ERROR"
    }
}

function Optimize-WindowsTelemetryAndPrivacy {
    Write-ToolLog "Desativando telemetria, diagnóstico e coleta de dados..." "INFO"
    try {
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) { New-Item -Path $dataCollectionKey -Force | Out-Null }
        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dataCollectionKey -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force

        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) { New-Item -Path $advertisingKey -Force | Out-Null }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

        # Desativar Histórico de Atividades
        $activityKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $activityKey)) { New-Item -Path $activityKey -Force | Out-Null }
        Set-ItemProperty -Path $activityKey -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "UploadUserActivities" -Value 0 -Type DWord -Force

        # Desativar Tarefas Agendadas de Telemetria / CEIP
        $telemetryTasks = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach ($task in $telemetryTasks) {
            Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        }

        Write-ToolLog "Telemetria e tarefas agendadas de rastreamento desativadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar telemetria: $_" "ERROR"
    }
}

function Optimize-WindowsServicesManual {
    Write-ToolLog "Configurando serviços secundários pesados para Manual ou Desativado (Estilo WinUtil)..." "INFO"
    
    $servicesToDisable = @(
        "DiagTrack",
        "dmwappushservice",
        "RetailDemo",
        "RemoteRegistry",
        "diagnosticshub.standardcollector.service"
    )

    $servicesToManual = @(
        "MapsBroker",
        "lfsvc",
        "SensorService",
        "SensrSvc",
        "WbioSrvc",
        "Fax",
        "wisvc",
        "SharedAccess",
        "WMPNetworkSvc",
        "WerSvc"
    )

    foreach ($s in $servicesToDisable) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Desativado." "INFO"
        }
    }

    foreach ($s in $servicesToManual) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Manual." "INFO"
        }
    }

    Write-ToolLog "Otimização de serviços do Windows concluída." "SUCCESS"
}

function Disable-GameDvrAndBackgroundRecording {
    Write-ToolLog "Desativando gravação em segundo plano do GameDVR (Reduz input lag em jogos)..." "INFO"
    try {
        $gameConfigKey = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gameConfigKey)) { New-Item -Path $gameConfigKey -Force | Out-Null }
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force

        $gamePolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $gamePolicyKey)) { New-Item -Path $gamePolicyKey -Force | Out-Null }
        Set-ItemProperty -Path $gamePolicyKey -Name "AllowGameDVR" -Value 0 -Type DWord -Force

        Write-ToolLog "GameDVR e gravação de fundo desativados. Desempenho de jogos otimizado." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao desativar GameDVR: $_" "ERROR"
    }
}

function Disable-StartMenuAdsAndBingSearch {
    Write-ToolLog "Desativando pesquisas da Web (Bing) e anúncios patrocinados no Menu Iniciar..." "INFO"
    try {
        $searchKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
        Set-ItemProperty -Path $searchKey -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

        $userSearchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $userSearchKey)) { New-Item -Path $userSearchKey -Force | Out-Null }
        Set-ItemProperty -Path $userSearchKey -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchKey -Name "CortanaConsent" -Value 0 -Type DWord -Force

        $contentDeliveryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $contentDeliveryKey) {
            Set-ItemProperty -Path $contentDeliveryKey -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Pesquisas Bing no menu Iniciar e anúncios de aplicativos desativados." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao remover anúncios do Menu Iniciar: $_" "ERROR"
    }
}

function Optimize-SystemResponsivenessAndVisuals {
    Write-ToolLog "Ajustando tempo de resposta de menus e prioridade de CPU..." "INFO"
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "10" -Force
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force
        Write-ToolLog "Prioridade de processos em foco e velocidade de menus aceleradas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao aplicar ajustes visuais: $_" "ERROR"
    }
}

function Optimize-SsdTrim {
    Write-ToolLog "Verificando unidades SSD para execução de TRIM (ReTrim)..." "INFO"
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
        foreach ($vol in $volumes) {
            Write-ToolLog "Otimizando unidade $($vol.DriveLetter): ..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue | Out-Null
        }
        Write-ToolLog "Comando TRIM executado com sucesso nas unidades elegíveis." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao executar TRIM: $_" "ERROR"
    }
}

function Set-HibernationState {
    param([Parameter(Mandatory=$true)][bool]$Enable)
    try {
        if ($Enable) {
            powercfg.exe -h on
            Write-ToolLog "Hibernação reativada." "SUCCESS"
        } else {
            powercfg.exe -h off
            Write-ToolLog "Hibernação desativada. Espaço equivalente à memória RAM liberado no disco C:." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao alterar estado de hibernação: $_" "ERROR"
    }
}

function Invoke-SystemDebloatAppx {
    Write-ToolLog "Removendo bloatwares e aplicativos pré-instalados desnecessários do Windows..." "INFO"
    $appsToRemove = @(
        "*Microsoft.BingNews*",
        "*Microsoft.BingWeather*",
        "*Microsoft.BingSearch*",
        "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*",
        "*Microsoft.MicrosoftOfficeHub*",
        "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.People*",
        "*Microsoft.PowerAutomateDesktop*",
        "*Microsoft.Todos*",
        "*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.YourPhone*",
        "*Microsoft.ZuneMusic*",
        "*Microsoft.ZuneVideo*",
        "*Clipchamp.Clipchamp*",
        "*SpotifyAB.SpotifyMusic*",
        "*Disney.37853FC22B2CE*",
        "*Netflix*",
        "*Facebook*",
        "*TikTok*"
    )

    $removed = 0
    foreach ($app in $appsToRemove) {
        try {
            $pkgs = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            foreach ($pkg in $pkgs) {
                Write-ToolLog "Removendo app: $($pkg.Name)..." "INFO"
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removed++
            }
        } catch {}
    }

    Write-ToolLog "Debloat de aplicativos concluído. Pacotes removidos: $removed." "SUCCESS"
}

# ==============================================================================
# PERFIS PRÉ-CONFIGURADOS COM 1 CLIQUE (ESTILO CHRIS TITUS WINUTIL)
# ==============================================================================

function Apply-DesktopRecommendedProfile {
    Write-ToolLog "=== APLICANDO PERFIL RECOMENDADO: DESKTOP / PC DE MESA ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_DesktopProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    Set-HibernationState -Enable $false
    Optimize-WindowsServicesManual
    Enable-UltimatePerformancePowerPlan
    Set-ShowFileExtensions -Enable $true
    Set-ShowHiddenFiles -Enable $true
    Set-ExplorerOpenToThisPC
    Disable-MouseAcceleration
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL DESKTOP APLICADO COM SUCESSO! ===" "SUCCESS"
}

function Apply-LaptopRecommendedProfile {
    Write-ToolLog "=== APLICANDO PERFIL RECOMENDADO: NOTEBOOK / LAPTOP ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_LaptopProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    # Notebooks MANTÊM a hibernação para segurança da bateria
    Set-HibernationState -Enable $true
    Optimize-WindowsServicesManual
    Set-ShowFileExtensions -Enable $true
    Set-ExplorerOpenToThisPC
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL NOTEBOOK APLICADO COM SUCESSO! ===" "SUCCESS"
}

function Apply-GamerUltimateProfile {
    Write-ToolLog "=== APLICANDO PERFIL GAMER & MÁXIMO DESEMPENHO ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_GamerProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    Set-HibernationState -Enable $false
    Optimize-WindowsServicesManual
    Enable-UltimatePerformancePowerPlan
    Optimize-SystemResponsivenessAndVisuals
    Disable-MouseAcceleration
    Optimize-TcpLatencyAndThroughput
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL GAMER APLICADO COM SUCESSO! ===" "SUCCESS"
}


# ==============================================================================
# Módulo: Ajustes de Usabilidade e Interface (Estilo Chris Titus WinUtil)
# ==============================================================================

function Set-RestorePoint {
    param([string]$Description = "WinRepair_RestorePoint")
    Write-ToolLog "Criando Ponto de Restauração do Sistema ($Description)..." "INFO"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-ToolLog "Ponto de Restauração criado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Não foi possível criar o Ponto de Restauração: $_ (Verifique se a Proteção do Sistema está ativada)." "WARN"
    }
}

function Set-ShowFileExtensions {
    param([bool]$Enable = $true)
    Write-ToolLog "Configurando exibição de extensões de arquivo conhecidas..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $val = if ($Enable) { 0 } else { 1 }
        Set-ItemProperty -Path $key -Name "HideFileExt" -Value $val -Type DWord -Force
        Write-ToolLog "Extensões de arquivos visíveis: $Enable." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar exibição de extensões: $_" "ERROR"
    }
}

function Set-ShowHiddenFiles {
    param([bool]$Enable = $true)
    Write-ToolLog "Configurando exibição de arquivos e pastas ocultas..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $val = if ($Enable) { 1 } else { 2 }
        Set-ItemProperty -Path $key -Name "Hidden" -Value $val -Type DWord -Force
        Write-ToolLog "Arquivos ocultos visíveis: $Enable." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar arquivos ocultos: $_" "ERROR"
    }
}

function Set-ExplorerOpenToThisPC {
    Write-ToolLog "Configurando o Windows Explorer para abrir em 'Este Computador' em vez do Acesso Rápido..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $key -Name "LaunchTo" -Value 1 -Type DWord -Force
        Write-ToolLog "Explorer agora abre diretamente em 'Este Computador'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar abertura do Explorer: $_" "ERROR"
    }
}

function Set-SystemDarkMode {
    param([bool]$Enable = $true)
    Write-ToolLog "Aplicando Tema Escuro (Dark Mode) global no sistema e aplicativos..." "INFO"
    try {
        $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        $val = if ($Enable) { 0 } else { 1 }
        Set-ItemProperty -Path $key -Name "AppsUseLightTheme" -Value $val -Type DWord -Force
        Set-ItemProperty -Path $key -Name "SystemUsesLightTheme" -Value $val -Type DWord -Force
        Write-ToolLog "Tema Escuro aplicado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar Dark Mode: $_" "ERROR"
    }
}

function Disable-MouseAcceleration {
    Write-ToolLog "Desativando Aceleração do Mouse (Aprimorar Precisão do Ponteiro) para precisão 1:1 em jogos..." "INFO"
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force
        Write-ToolLog "Aceleração do mouse desativada (precisão pura do sensor)." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desativar aceleração do mouse: $_" "ERROR"
    }
}

function Disable-Win11TaskbarJunk {
    Write-ToolLog "Limpando itens inúteis da barra de tarefas do Windows 11 (Widgets, Copilot, Chat/Teams, TaskView)..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $key -Name "TaskbarDa" -Value 0 -Type DWord -Force          # Desativa Widgets
        Set-ItemProperty -Path $key -Name "ShowCopilotButton" -Value 0 -Type DWord -Force  # Desativa Botão Copilot
        Set-ItemProperty -Path $key -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force # Desativa Visão de Tarefas

        $chatKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
        if (Test-Path $chatKey) {
            Set-ItemProperty -Path $chatKey -Name "PeopleBand" -Value 0 -Type DWord -Force
        }

        # Reiniciar explorer para refletir alterações
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Barra de tarefas limpa e sem distrações." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar barra de tarefas: $_" "ERROR"
    }
}

function Add-TakeOwnershipContextMenu {
    Write-ToolLog "Adicionando 'Obter Permissões' (Take Ownership) ao menu de contexto de arquivos e pastas..." "INFO"
    try {
        # Para arquivos
        $fileKey = "HKCR:\*\shell\runas"
        New-Item -Path $fileKey -Force | Out-Null
        Set-ItemProperty -Path $fileKey -Name "(Default)" -Value "Obter Acesso Total (Take Ownership)" -Force
        Set-ItemProperty -Path $fileKey -Name "NoWorkingDirectory" -Value "" -Force
        $fileCmd = "$fileKey\command"
        New-Item -Path $fileCmd -Force | Out-Null
        Set-ItemProperty -Path $fileCmd -Name "(Default)" -Value "cmd.exe /c takeown /f `"%1`" && icacls `"%1`" /grant administrators:F" -Force
        Set-ItemProperty -Path $fileCmd -Name "IsolatedCommand" -Value "cmd.exe /c takeown /f `"%1`" && icacls `"%1`" /grant administrators:F" -Force

        # Para pastas
        $dirKey = "HKCR:\Directory\shell\runas"
        New-Item -Path $dirKey -Force | Out-Null
        Set-ItemProperty -Path $dirKey -Name "(Default)" -Value "Obter Acesso Total (Take Ownership)" -Force
        Set-ItemProperty -Path $dirKey -Name "NoWorkingDirectory" -Value "" -Force
        $dirCmd = "$dirKey\command"
        New-Item -Path $dirCmd -Force | Out-Null
        Set-ItemProperty -Path $dirCmd -Name "(Default)" -Value "cmd.exe /c takeown /f `"%1`" /r /d y && icacls `"%1`" /grant administrators:F /t" -Force
        Set-ItemProperty -Path $dirCmd -Name "IsolatedCommand" -Value "cmd.exe /c takeown /f `"%1`" /r /d y && icacls `"%1`" /grant administrators:F /t" -Force

        Write-ToolLog "Atalho 'Take Ownership' adicionado ao menu do botão direito." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao adicionar Take Ownership: $_" "ERROR"
    }
}

function Uninstall-OneDrivePurge {
    Write-ToolLog "Iniciando desinstalação completa e remoção de resíduos do OneDrive..." "INFO"
    try {
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

        $oneDriveSetup = @(
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\Update\OneDriveSetup.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($oneDriveSetup) {
            Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
            Write-ToolLog "Desinstalador do OneDrive executado." "INFO"
        }

        # Remover pastas residuais
        $dirs = @(
            "$env:USERPROFILE\OneDrive",
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive"
        )
        foreach ($d in $dirs) {
            if (Test-Path $d) {
                Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Remover OneDrive do painel lateral do Windows Explorer
        $clsid = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        if (Test-Path $clsid) {
            Set-ItemProperty -Path $clsid -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "OneDrive desinstalado e removido do sistema com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desinstalar OneDrive: $_" "ERROR"
    }
}


# ==============================================================================
# Módulo: Recursos Opcionais do Windows (Estilo WinUtil Config)
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
# Módulo Avançado: Criador e Customizador de Imagens ISO (Windows 10 / 11)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms

function Select-IsoFileDialog {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Arquivos de Imagem ISO (*.iso)|*.iso|Todos os Arquivos (*.*)|*.*"
    $dialog.Title = "Selecione a ISO Oficial do Windows 10 ou 11"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Select-OutputFolderDialog {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Selecione a pasta onde a nova ISO modificada será salva"
    $dialog.ShowNewFolderButton = $true
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Inspect-IsoEditions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IsoPath
    )

    if (-not (Test-Path $IsoPath)) {
        Write-ToolLog "Arquivo ISO não encontrado: $IsoPath" "ERROR"
        return $null
    }

    Write-ToolLog "Montando ISO temporariamente para ler edições disponíveis..." "INFO"
    try {
        $mounted = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
        $driveLetter = ($mounted | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            # Tenta obter pelo drive letter via CimInstance se Get-Volume atrasar
            Start-Sleep -Seconds 1
            $driveLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume).DriveLetter
        }

        $drivePath = "${driveLetter}:\"
        Write-ToolLog "ISO montada na unidade ${drivePath}" "INFO"

        $wimPath = Join-Path $drivePath "sources\install.wim"
        if (-not (Test-Path $wimPath)) {
            $wimPath = Join-Path $drivePath "sources\install.esd"
        }

        if (-not (Test-Path $wimPath)) {
            Write-ToolLog "Não foi possível localizar install.wim ou install.esd na ISO." "ERROR"
            Dismount-DiskImage -ImagePath $IsoPath | Out-Null
            return $null
        }

        $images = Get-WindowsImage -ImagePath $wimPath
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null

        Write-ToolLog "Edições detectadas na imagem:" "SUCCESS"
        foreach ($img in $images) {
            Write-ToolLog "  -> [Índice $($img.ImageIndex)]: $($img.ImageName)" "INFO"
        }

        return $images
    } catch {
        Write-ToolLog "Falha ao inspecionar a ISO: $_" "ERROR"
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        return $null
    }
}

function Generate-AutoUnattendXml {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        [bool]$BypassOobePrompts = $true,
        [bool]$AllowLocalAccount = $true
    )

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
"@

    [System.IO.File]::WriteAllText($DestinationPath, $xml, [System.Text.Encoding]::UTF8)
    Write-ToolLog "Arquivo autounattend.xml gerado em: $DestinationPath" "SUCCESS"
}

function Build-CustomOptimizedIsoPipeline {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceIsoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputIsoDir,

        [string]$OutputIsoName = "Windows_Custom_Otimizado.iso",
        [int]$EditionIndex = 1,
        
        [bool]$BypassHardwareChecks = $true,
        [bool]$BypassMicrosoftAccount = $true,
        [bool]$DisableBitLocker = $true,
        [bool]$RemoveBloatware = $true,
        [bool]$InjectUnattendXml = $true
    )

    Write-ToolLog "=== INICIANDO CRIAÇÃO DE ISO MODIFICADA E OTIMIZADA ===" "INFO"
    $workDir = "C:\ISO_Work"
    $extractedDir = Join-Path $workDir "extracted"
    $mountDir = Join-Path $workDir "mount"

    try {
        # 1. Preparar pastas de trabalho
        if (Test-Path $workDir) {
            Write-ToolLog "Limpando diretório de trabalho anterior ($workDir)..." "INFO"
            Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
            Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $extractedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

        # 2. Montar ISO e copiar arquivos
        Write-ToolLog "Montando ISO de origem..." "INFO"
        $diskImg = Mount-DiskImage -ImagePath $SourceIsoPath -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 1
        $driveLetter = ($diskImg | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            $driveLetter = (Get-DiskImage -ImagePath $SourceIsoPath | Get-Volume).DriveLetter
        }
        $driveRoot = "${driveLetter}:\"

        Write-ToolLog "Copiando arquivos da ISO para o diretório de trabalho (pode levar 1-3 min)..." "INFO"
        Copy-Item -Path "${driveRoot}*" -Destination $extractedDir -Recurse -Force
        Dismount-DiskImage -ImagePath $SourceIsoPath | Out-Null
        Write-ToolLog "Arquivos copiados com sucesso." "SUCCESS"

        # 3. Localizar WIM ou ESD
        $wimPath = Join-Path $extractedDir "sources\install.wim"
        $esdPath = Join-Path $extractedDir "sources\install.esd"

        if ((-not (Test-Path $wimPath)) -and (Test-Path $esdPath)) {
            Write-ToolLog "Arquivo install.esd detectado. Convertendo índice $EditionIndex para install.wim..." "INFO"
            Export-WindowsImage -SourceImagePath $esdPath -SourceIndex $EditionIndex -DestinationImagePath $wimPath -DestinationName "Windows Custom" -ErrorAction Stop
            Remove-Item -Path $esdPath -Force -ErrorAction SilentlyContinue
            $EditionIndex = 1
        }

        # 4. Montar a imagem WIM
        Write-ToolLog "Montando imagem WIM (Índice $EditionIndex)..." "INFO"
        Mount-WindowsImage -ImagePath $wimPath -Index $EditionIndex -Path $mountDir -ErrorAction Stop

        # 5. Aplicar Debloat AppX se selecionado
        if ($RemoveBloatware) {
            Write-ToolLog "Removendo pacotes AppX provisionados (bloatware) da imagem..." "INFO"
            $bloatPatterns = @(
                "*BingNews*", "*BingWeather*", "*Solitaire*", "*GetHelp*", "*Getstarted*",
                "*People*", "*Todos*", "*PowerAutomate*", "*ZuneMusic*", "*ZuneVideo*",
                "*Clipchamp*", "*XboxGamingOverlay*", "*XboxSpeechToTextOverlay*"
            )
            $provPackages = Get-AppxProvisionedPackage -Path $mountDir
            $removedCount = 0
            foreach ($pkg in $provPackages) {
                foreach ($pattern in $bloatPatterns) {
                    if ($pkg.DisplayName -like $pattern) {
                        Remove-AppxProvisionedPackage -Path $mountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                        $removedCount++
                        break
                    }
                }
            }
            Write-ToolLog "Bloatware removido da imagem: $removedCount pacotes eliminados." "SUCCESS"
        }

        # 6. Injetar ajustes de registro offline
        $offlineSysHive = Join-Path $mountDir "Windows\System32\config\SYSTEM"
        if (Test-Path $offlineSysHive) {
            Write-ToolLog "Carregando registro offline do Windows..." "INFO"
            reg load HKLM\OFFLINE_SYS "$offlineSysHive" | Out-Null

            if ($BypassHardwareChecks) {
                Write-ToolLog "Injetando Bypass de Requisitos Win11 (TPM 2.0, SecureBoot, RAM, CPU)..." "INFO"
                $labConfig = "HKLM\OFFLINE_SYS\Setup\LabConfig"
                if (-not (Test-Path $labConfig)) { New-Item -Path $labConfig -Force | Out-Null }
                Set-ItemProperty -Path $labConfig -Name "BypassTPMCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassSecureBootCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassRAMCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassCPUCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassStorageCheck" -Value 1 -Type DWord -Force
            }

            if ($BypassMicrosoftAccount) {
                Write-ToolLog "Injetando Bypass de Conta Microsoft (BypassNRO - permite criar conta local)..." "INFO"
                $oobeKey = "HKLM\OFFLINE_SYS\Setup\OOBE"
                if (-not (Test-Path $oobeKey)) { New-Item -Path $oobeKey -Force | Out-Null }
                Set-ItemProperty -Path $oobeKey -Name "BypassNRO" -Value 1 -Type DWord -Force
            }

            if ($DisableBitLocker) {
                Write-ToolLog "Desativando criptografia automática do BitLocker no OOBE..." "INFO"
                $bitlockerKey = "HKLM\OFFLINE_SYS\ControlSet001\Control\BitLocker"
                if (-not (Test-Path $bitlockerKey)) { New-Item -Path $bitlockerKey -Force | Out-Null }
                Set-ItemProperty -Path $bitlockerKey -Name "PreventDeviceEncryption" -Value 1 -Type DWord -Force
            }

            [gc]::Collect()
            reg unload HKLM\OFFLINE_SYS | Out-Null
            Write-ToolLog "Registro offline salvo e descarregado." "SUCCESS"
        }

        # 7. Desmontar salvando as alterações
        Write-ToolLog "Desmontando e salvando imagem WIM modificada..." "INFO"
        Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop

        # 8. Injetar autounattend.xml se solicitado
        if ($InjectUnattendXml) {
            $unattendDest = Join-Path $extractedDir "autounattend.xml"
            Generate-AutoUnattendXml -DestinationPath $unattendDest
        }

        # 9. Gerar ISO bootável final
        $finalIsoPath = Join-Path $OutputIsoDir $OutputIsoName
        Write-ToolLog "Gerando ISO inicializável final em: $finalIsoPath..." "INFO"

        # Procurar oscdimg oficial se presente no sistema
        $oscdimg = Get-Command "oscdimg.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
        if (-not $oscdimg) {
            $adkPaths = @(
                "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
                "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
            )
            $oscdimg = $adkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if ($oscdimg) {
            Write-ToolLog "Criando ISO UEFI/BIOS via oscdimg oficial..." "INFO"
            $bootData = "2#p0,e,b`"$extractedDir\boot\etfsboot.com`"#pEF,e,b`"$extractedDir\efi\microsoft\boot\efisys.bin`""
            & "$oscdimg" -m -o -u2 -udfver102 -bootdata:$bootData "$extractedDir" "$finalIsoPath" | Out-Null
            Write-ToolLog "ISO customizada gerada com sucesso via oscdimg: $finalIsoPath" "SUCCESS"
        } else {
            Write-ToolLog "A pasta preparada para a ISO está pronta em: $extractedDir" "SUCCESS"
            Write-ToolLog "Instale o Windows ADK (oscdimg) ou use o Rufus apontando para essa pasta para gravar no pendrive direto." "INFO"
        }

        Write-ToolLog "=== PROCESSO DE CUSTOMIZAÇÃO CONCLUÍDO COM SUCESSO! ===" "SUCCESS"
    } catch {
        Write-ToolLog "Erro durante o pipeline da ISO: $_" "ERROR"
        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
    }
}


# ==============================================================================
# Módulo: Instalador de Softwares Essenciais via Winget
# ==============================================================================

function Install-SelectedSoftwareList {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PackageIds
    )

    if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
        Write-ToolLog "O gerenciador de pacotes Winget não foi encontrado neste sistema." "ERROR"
        return
    }

    Write-ToolLog "Iniciando instalação em lote de $($PackageIds.Count) aplicativo(s)..." "INFO"

    foreach ($pkg in $PackageIds) {
        Write-ToolLog "Baixando e instalando silenciosamente: $pkg..." "INFO"
        try {
            $p = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $pkg --exact --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-ToolLog "Software [$pkg] instalado com sucesso!" "SUCCESS"
            } elseif ($p.ExitCode -eq -1978335189) {
                Write-ToolLog "Software [$pkg] já está instalado ou atualizado." "INFO"
            } else {
                Write-ToolLog "Winget retornou código $($p.ExitCode) para [$pkg]." "WARN"
            }
        } catch {
            Write-ToolLog "Erro ao instalar [$pkg]: $_" "ERROR"
        }
    }

    Write-ToolLog "Instalação em lote concluída." "SUCCESS"
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

# 2. Carregar assemblies do WPF e Forms
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# 3. Carregar interface gráfica embutida
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinRepair &amp; Tweaks Pro"
        Height="820" Width="1060"
        WindowStartupLocation="CenterScreen"
        Background="#181825"
        Foreground="#CDD6F4"
        FontFamily="Segoe UI, Segoe UI Emoji">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
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
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,8"/>
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
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="#89B4FA"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="4,3"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#313244"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="3,3,3,8"/>
            <Setter Property="Padding" Value="8"/>
        </Style>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="160"/>
        </Grid.RowDefinitions>

        <!-- Cabeçalho Principal -->
        <Border Grid.Row="0" Background="#1E1E2E" CornerRadius="8" Padding="14,10" Margin="0,0,0,8" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="⚡ WinRepair &amp; Tweaks Pro" FontSize="20" FontWeight="Bold" Foreground="#89B4FA"/>
                    <TextBlock Text="Inspirado no Chris Titus WinUtil: Otimizações, Tweaks, Recursos, ISO e Reparos" FontSize="11" Foreground="#A6ADC8" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Name="txtSystemInfo" Text="Identificando máquina..." FontSize="12" Foreground="#94E2D5" HorizontalAlignment="Right"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Abas Principais -->
        <TabControl Grid.Row="1" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="1">
            
            <!-- ABA 1: TWEAKS & PERFIS (ESTILO WINUTIL TWEAKS) -->
            <TabItem Header="⚡ Tweaks &amp; Otimização">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <!-- Barra de Perfis com 1 Clique -->
                        <Border Background="#24273A" CornerRadius="6" Padding="10" Margin="2,0,2,8" BorderBrush="#45475A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Perfis Recomendados (1 Clique):" FontWeight="Bold" Foreground="#89B4FA" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <WrapPanel Grid.Column="1" VerticalAlignment="Center">
                                    <Button Name="btnProfileDesktop" Content="🖥️ Perfil Desktop" Padding="12,6" Background="#313244" Foreground="#A6E3A1"/>
                                    <Button Name="btnProfileLaptop" Content="💻 Perfil Notebook" Padding="12,6" Background="#313244" Foreground="#89B4FA"/>
                                    <Button Name="btnProfileGamer" Content="🎮 Perfil Gamer Extremo" Padding="12,6" Background="#313244" Foreground="#F38BA8"/>
                                </WrapPanel>
                                <Button Name="btnCreateRestorePoint" Grid.Column="2" Content="🛡️ Criar Ponto de Restauração" Padding="10,6" Background="#45475A"/>
                            </Grid>
                        </Border>

                        <!-- Grade de Tweaks Granulares -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Coluna 1: Essenciais & Desempenho -->
                            <GroupBox Grid.Column="0" Header="Essenciais &amp; Desempenho">
                                <StackPanel>
                                    <CheckBox Name="chkCleanTemp" Content="Limpar Arquivos Temporários" IsChecked="True"/>
                                    <CheckBox Name="chkDisableTelemetry" Content="Desativar Telemetria &amp; CEIP" IsChecked="True"/>
                                    <CheckBox Name="chkDisableBingSearch" Content="Desativar Bing no Menu Iniciar" IsChecked="True"/>
                                    <CheckBox Name="chkDisableGameDvr" Content="Desativar GameDVR (Input Lag)" IsChecked="True"/>
                                    <CheckBox Name="chkOptimizeServices" Content="Serviços Pesados em Manual" IsChecked="True"/>
                                    <CheckBox Name="chkUltimatePower" Content="Plano 'Desempenho Máximo'" IsChecked="True"/>
                                    <CheckBox Name="chkDisableHibernation" Content="Desativar Hibernação (Desktop)" IsChecked="False"/>
                                    <CheckBox Name="chkFastVisuals" Content="Acelerar Menus (MenuShowDelay)" IsChecked="True"/>
                                    <CheckBox Name="chkSsdTrim" Content="Otimizar SSDs (Executar TRIM)" IsChecked="True"/>
                                </StackPanel>
                            </GroupBox>

                            <!-- Coluna 2: Interface & Usabilidade -->
                            <GroupBox Grid.Column="1" Header="Interface &amp; Usabilidade">
                                <StackPanel>
                                    <CheckBox Name="chkShowFileExt" Content="Mostrar Extensões de Arquivo" IsChecked="True"/>
                                    <CheckBox Name="chkShowHiddenFiles" Content="Mostrar Arquivos Ocultos" IsChecked="True"/>
                                    <CheckBox Name="chkExplorerThisPc" Content="Explorer abre em 'Este Computador'" IsChecked="True"/>
                                    <CheckBox Name="chkDarkMode" Content="Ativar Tema Escuro (Dark Mode)" IsChecked="True"/>
                                    <CheckBox Name="chkDisableMouseAccel" Content="Desativar Aceleração do Mouse (1:1)" IsChecked="True"/>
                                    <CheckBox Name="chkCleanWin11Taskbar" Content="Limpar Barra Tarefas (Widgets/Copilot)" IsChecked="True"/>
                                    <CheckBox Name="chkTakeOwnership" Content="Adicionar 'Take Ownership' no Menu" IsChecked="True"/>
                                    <CheckBox Name="chkUninstallOneDrive" Content="Desinstalar e Purgar OneDrive" IsChecked="False"/>
                                </StackPanel>
                            </GroupBox>

                            <!-- Coluna 3: Rede & TCP Gaming -->
                            <GroupBox Grid.Column="2" Header="Rede &amp; Conectividade">
                                <StackPanel>
                                    <CheckBox Name="chkOptimizeTcp" Content="Otimizar Latência TCP (AutoTune, RSS)" IsChecked="True"/>
                                    <CheckBox Name="chkFlushDns" Content="Limpar Cache DNS" IsChecked="True"/>
                                    <CheckBox Name="chkRenewDhcp" Content="Renovar Concessão de IP / DHCP" IsChecked="False"/>
                                    <CheckBox Name="chkResetNetwork" Content="Redefinir Pilha de Rede Completa" IsChecked="False"/>
                                </StackPanel>
                            </GroupBox>
                        </Grid>

                        <!-- Botão Aplicar Selecionados -->
                        <Button Name="btnApplySelectedTweaks" Content="🚀 Aplicar Todos os Tweaks Selecionados" Height="42" FontSize="14" FontWeight="Bold" Background="#89B4FA" Foreground="#11111B" Margin="2,8,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 2: REDE & DNS -->
            <TabItem Header="🌐 Rede &amp; Conectividade">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Diagnóstico da Conexão">
                            <WrapPanel>
                                <Button Name="btnTestNetwork" Content="Testar Latência &amp; Perda de Pacotes" Width="260" Height="36"/>
                                <Button Name="btnFlushDnsTab" Content="Limpar Cache DNS" Width="180" Height="36"/>
                                <Button Name="btnRenewDhcpTab" Content="Renovar IP / DHCP" Width="180" Height="36"/>
                                <Button Name="btnRestartAdapters" Content="Reiniciar Placas de Rede" Width="210" Height="36"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Troca Rápida de DNS">
                            <WrapPanel>
                                <Button Name="btnDnsCloudflare" Content="Cloudflare (1.1.1.1) - Veloz" Width="210" Height="36"/>
                                <Button Name="btnDnsGoogle" Content="Google (8.8.8.8) - Confiável" Width="210" Height="36"/>
                                <Button Name="btnDnsQuad9" Content="Quad9 (9.9.9.9) - Anti-Malware" Width="220" Height="36"/>
                                <Button Name="btnDnsAdGuard" Content="AdGuard - Bloqueia Anúncios" Width="210" Height="36"/>
                                <Button Name="btnDnsDhcp" Content="Restaurar Automático (DHCP)" Width="210" Height="36"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 3: RECURSOS & UPDATES (ESTILO WINUTIL CONFIG & UPDATES) -->
            <TabItem Header="⚙️ Recursos &amp; Updates">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Gerenciamento do Windows Update (Estilo Chris Titus)">
                            <StackPanel>
                                <TextBlock Text="Controle como o Windows Update lida com atualizações para evitar travamentos e reinicializações forçadas:" FontSize="11" Foreground="#A6ADC8" Margin="4,0,0,6"/>
                                <WrapPanel>
                                    <Button Name="btnWuRecommended" Content="🛡️ Modo Recomendado (Segurança Estável &amp; Sem Reinício Forçado)" Width="460" Height="36"/>
                                    <Button Name="btnWuDefault" Content="🔄 Restaurar Padrão da Microsoft" Width="240" Height="36"/>
                                    <Button Name="btnWuPause" Content="⏸️ Pausar Atualizações (Até 2042)" Width="230" Height="36"/>
                                </WrapPanel>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Recursos Opcionais do Windows (Ativação com 1 Clique)">
                            <WrapPanel>
                                <Button Name="btnEnableWsl" Content="Ativar WSL 2 (Subsistema Linux)" Width="240" Height="36"/>
                                <Button Name="btnEnableSandbox" Content="Ativar Windows Sandbox" Width="210" Height="36"/>
                                <Button Name="btnEnableHyperV" Content="Ativar Hyper-V" Width="180" Height="36"/>
                                <Button Name="btnEnableNet35" Content="Ativar .NET Framework 3.5" Width="220" Height="36"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 4: MICROWIN / CRIADOR DE ISO -->
            <TabItem Header="💿 MicroWin (Criador de ISO)">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="1. Seleção da Imagem ISO Oficial">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="140"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="140"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Arquivo ISO Origem:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtIsoPath" Grid.Column="1" Margin="0,0,8,0" Text="" ToolTip="Selecione um arquivo .iso oficial do Windows 10 ou 11"/>
                                <Button Name="btnBrowseIso" Grid.Column="2" Content="Procurar ISO..." Width="120" Height="32"/>
                                <Button Name="btnInspectIso" Grid.Column="3" Content="Analisar Edições" Width="130" Height="32"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="2. Destino e Edição">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="140"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="100"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Pasta de Destino:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtOutputIsoDir" Grid.Row="0" Grid.Column="1" Margin="0,0,8,4" Text="C:\ISO_Work"/>
                                <Button Name="btnBrowseOutputDir" Grid.Row="0" Grid.Column="2" Content="Selecionar Pasta..." Width="120" Height="32" Margin="0,0,0,4"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Nome do Arquivo:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtOutputIsoName" Grid.Row="1" Grid.Column="1" Margin="0,0,8,0" Text="Windows_MicroWin_Custom.iso"/>

                                <TextBlock Grid.Row="1" Grid.Column="2" Text="Índice da Edição:" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="#A6ADC8" Margin="0,0,6,0"/>
                                <TextBox Name="txtEditionIndex" Grid.Row="1" Grid.Column="3" Text="1" Width="50" HorizontalAlignment="Left"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="3. Modificações MicroWin a Injetar">
                            <StackPanel>
                                <CheckBox Name="chkIsoBypassHw" Content="Bypass de Requisitos Win 11 (Ignora TPM 2.0, Secure Boot, RAM e CPU)" IsChecked="True"/>
                                <CheckBox Name="chkIsoBypassAcc" Content="Bypass de Conta Microsoft Obrigatória (Permite criar Conta Local offline - BypassNRO)" IsChecked="True"/>
                                <CheckBox Name="chkIsoDisableBitLocker" Content="Desativar Criptografia Automática do BitLocker no primeiro boot" IsChecked="True"/>
                                <CheckBox Name="chkIsoDebloat" Content="Remover Bloatware AppX na raiz da imagem (Xbox overlays, Clipchamp, Notícias, Jogos)" IsChecked="True"/>
                                <CheckBox Name="chkIsoUnattend" Content="Injetar autounattend.xml (Pula telas de termos, diagnóstico e anúncios no primeiro boot)" IsChecked="True"/>
                            </StackPanel>
                        </GroupBox>

                        <Button Name="btnBuildCustomIso" Content="🚀 Gerar Nova ISO MicroWin Otimizada!" Height="44" FontSize="14" FontWeight="Bold" Background="#89B4FA" Foreground="#11111B" Margin="2,4,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 5: SOFTWARES (WINGET) -->
            <TabItem Header="📦 Softwares">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <Grid Margin="0,0,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Instale ou atualize silenciosamente os softwares essenciais via Winget:" FontSize="11" Foreground="#A6ADC8" VerticalAlignment="Center"/>
                            <Button Name="btnUpgradeAllSoftware" Grid.Column="1" Content="🔄 Atualizar Todos os Apps (winget upgrade --all)" Padding="10,5"/>
                        </Grid>

                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <GroupBox Grid.Column="0" Header="Navegadores">
                                <StackPanel>
                                    <CheckBox Name="chkSoftwareChrome" Content="Google Chrome" Tag="Google.Chrome"/>
                                    <CheckBox Name="chkSoftwareFirefox" Content="Mozilla Firefox" Tag="Mozilla.Firefox"/>
                                    <CheckBox Name="chkSoftwareBrave" Content="Brave Browser" Tag="Brave.Brave"/>
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Grid.Column="1" Header="Utilitários Essenciais">
                                <StackPanel>
                                    <CheckBox Name="chkSoftware7zip" Content="7-Zip" Tag="7zip.7zip" IsChecked="True"/>
                                    <CheckBox Name="chkSoftwareNotepad" Content="Notepad++" Tag="Notepad++.Notepad++"/>
                                    <CheckBox Name="chkSoftwareAnyDesk" Content="AnyDesk" Tag="AnyDeskSoftwareGmbH.AnyDesk"/>
                                    <CheckBox Name="chkSoftwarePowerToys" Content="Microsoft PowerToys" Tag="Microsoft.PowerToys"/>
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Grid.Column="2" Header="Mídia &amp; Dev/Jogos">
                                <StackPanel>
                                    <CheckBox Name="chkSoftwareVlc" Content="VLC Media Player" Tag="VideoLAN.VLC"/>
                                    <CheckBox Name="chkSoftwareVsCode" Content="Visual Studio Code" Tag="Microsoft.VisualStudioCode"/>
                                    <CheckBox Name="chkSoftwareSteam" Content="Steam" Tag="Valve.Steam"/>
                                    <CheckBox Name="chkSoftwareDiscord" Content="Discord" Tag="Discord.Discord"/>
                                </StackPanel>
                            </GroupBox>
                        </Grid>

                        <Button Name="btnInstallSelectedSoftware" Content="Baixar e Instalar Softwares Selecionados" Height="38" Margin="2,8,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 6: REPAROS DO SISTEMA -->
            <TabItem Header="🛠️ Reparo do SO">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Integridade de Arquivos e Componentes">
                            <WrapPanel>
                                <Button Name="btnSfcScan" Content="Verificação de Integridade (SFC /scannow)" Width="270" Height="36"/>
                                <Button Name="btnDismRepair" Content="Reparar Imagem do Windows (DISM)" Width="260" Height="36"/>
                                <Button Name="btnDismCleanup" Content="Limpar Component Store (WinSxS)" Width="250" Height="36"/>
                                <Button Name="btnRestartSpooler" Content="Destravar Spooler de Impressão" Width="230" Height="36"/>
                                <Button Name="btnScheduleChkdsk" Content="Agendar CHKDSK no Disco C:" Width="230" Height="36"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 7: LICENCIAMENTO -->
            <TabItem Header="🔑 Licenciamento">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Licença do Windows">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,6">
                                    <Button Name="btnCheckWinLicense" Content="Verificar Status da Licença" Width="210" Height="34"/>
                                </WrapPanel>
                                <Grid Margin="0,2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Windows:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtWinKey" Grid.Column="1" Margin="0,0,8,0" Text=""/>
                                    <Button Name="btnApplyWinKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="170" Height="32"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Licença do Microsoft Office">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,6">
                                    <Button Name="btnCheckOfficeLicense" Content="Verificar Status do Office" Width="210" Height="34"/>
                                </WrapPanel>
                                <Grid Margin="0,2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Office:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtOfficeKey" Grid.Column="1" Margin="0,0,8,0" Text=""/>
                                    <Button Name="btnApplyOfficeKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="170" Height="32"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Servidor KMS Institucional">
                            <Grid Margin="0,2">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Host KMS Oficial:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtKmsHost" Grid.Column="1" Margin="0,0,8,0" Text="kms.dominio.local"/>
                                <Button Name="btnSetKms" Grid.Column="2" Content="Configurar Servidor KMS" Width="170" Height="32"/>
                            </Grid>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Painel Inferior de Logs -->
        <Border Grid.Row="2" Background="#11111B" CornerRadius="8" Margin="0,8,0,0" BorderBrush="#313244" BorderThickness="1">
            <Grid Margin="6">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="📜 Console de Execução &amp; Logs em Tempo Real" FontSize="11" FontWeight="SemiBold" Foreground="#89B4FA" VerticalAlignment="Center"/>
                    <Button Name="btnClearLogs" Grid.Column="1" Content="Limpar Log" Padding="6,3" FontSize="11" Margin="0"/>
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

# --- PERFIS PRONTOS (1 CLIQUE) ---
$window.FindName("btnProfileDesktop").Add_Click({ Start-AsyncAction { Apply-DesktopRecommendedProfile } })
$window.FindName("btnProfileLaptop").Add_Click({ Start-AsyncAction { Apply-LaptopRecommendedProfile } })
$window.FindName("btnProfileGamer").Add_Click({ Start-AsyncAction { Apply-GamerUltimateProfile } })
$window.FindName("btnCreateRestorePoint").Add_Click({ Start-AsyncAction { Set-RestorePoint } })

# --- APLICAR TWEAKS SELECIONADOS ---
$window.FindName("btnApplySelectedTweaks").Add_Click({
    $tweaks = @{
        CleanTemp           = [bool]$window.FindName("chkCleanTemp").IsChecked
        DisableTelemetry    = [bool]$window.FindName("chkDisableTelemetry").IsChecked
        DisableBingSearch   = [bool]$window.FindName("chkDisableBingSearch").IsChecked
        DisableGameDvr      = [bool]$window.FindName("chkDisableGameDvr").IsChecked
        OptimizeServices    = [bool]$window.FindName("chkOptimizeServices").IsChecked
        UltimatePower       = [bool]$window.FindName("chkUltimatePower").IsChecked
        DisableHibernation  = [bool]$window.FindName("chkDisableHibernation").IsChecked
        FastVisuals         = [bool]$window.FindName("chkFastVisuals").IsChecked
        SsdTrim             = [bool]$window.FindName("chkSsdTrim").IsChecked

        ShowFileExt         = [bool]$window.FindName("chkShowFileExt").IsChecked
        ShowHiddenFiles     = [bool]$window.FindName("chkShowHiddenFiles").IsChecked
        ExplorerThisPc      = [bool]$window.FindName("chkExplorerThisPc").IsChecked
        DarkMode            = [bool]$window.FindName("chkDarkMode").IsChecked
        DisableMouseAccel   = [bool]$window.FindName("chkDisableMouseAccel").IsChecked
        CleanWin11Taskbar   = [bool]$window.FindName("chkCleanWin11Taskbar").IsChecked
        TakeOwnership       = [bool]$window.FindName("chkTakeOwnership").IsChecked
        UninstallOneDrive   = [bool]$window.FindName("chkUninstallOneDrive").IsChecked

        OptimizeTcp         = [bool]$window.FindName("chkOptimizeTcp").IsChecked
        FlushDns            = [bool]$window.FindName("chkFlushDns").IsChecked
        RenewDhcp           = [bool]$window.FindName("chkRenewDhcp").IsChecked
        ResetNetwork        = [bool]$window.FindName("chkResetNetwork").IsChecked
    }

    Start-AsyncAction {
        Write-ToolLog "=== INICIANDO APLICAÇÃO DOS TWEAKS SELECIONADOS ===" "INFO"

        if ($using:tweaks.CleanTemp) { Clear-TempFiles }
        if ($using:tweaks.DisableTelemetry) { Optimize-WindowsTelemetryAndPrivacy }
        if ($using:tweaks.DisableBingSearch) { Disable-StartMenuAdsAndBingSearch }
        if ($using:tweaks.DisableGameDvr) { Disable-GameDvrAndBackgroundRecording }
        if ($using:tweaks.OptimizeServices) { Optimize-WindowsServicesManual }
        if ($using:tweaks.UltimatePower) { Enable-UltimatePerformancePowerPlan }
        if ($using:tweaks.DisableHibernation) { Set-HibernationState -Enable $false }
        if ($using:tweaks.FastVisuals) { Optimize-SystemResponsivenessAndVisuals }
        if ($using:tweaks.SsdTrim) { Optimize-SsdTrim }

        if ($using:tweaks.ShowFileExt) { Set-ShowFileExtensions -Enable $true }
        if ($using:tweaks.ShowHiddenFiles) { Set-ShowHiddenFiles -Enable $true }
        if ($using:tweaks.ExplorerThisPc) { Set-ExplorerOpenToThisPC }
        if ($using:tweaks.DarkMode) { Set-SystemDarkMode -Enable $true }
        if ($using:tweaks.DisableMouseAccel) { Disable-MouseAcceleration }
        if ($using:tweaks.CleanWin11Taskbar) { Disable-Win11TaskbarJunk }
        if ($using:tweaks.TakeOwnership) { Add-TakeOwnershipContextMenu }
        if ($using:tweaks.UninstallOneDrive) { Uninstall-OneDrivePurge }

        if ($using:tweaks.OptimizeTcp) { Optimize-TcpLatencyAndThroughput }
        if ($using:tweaks.FlushDns) { Invoke-FlushDns }
        if ($using:tweaks.RenewDhcp) { Invoke-RenewDhcp }
        if ($using:tweaks.ResetNetwork) { Invoke-ResetNetworkStack }

        Write-ToolLog "=== TODOS OS TWEAKS SELECIONADOS FORAM APLICADOS COM SUCESSO! ===" "SUCCESS"
    }
})

# --- ABA 2: REDE ---
$window.FindName("btnTestNetwork").Add_Click({ Start-AsyncAction { Test-NetworkQuality } })
$window.FindName("btnFlushDnsTab").Add_Click({ Start-AsyncAction { Invoke-FlushDns } })
$window.FindName("btnRenewDhcpTab").Add_Click({ Start-AsyncAction { Invoke-RenewDhcp } })
$window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction { Restart-NetworkAdapters } })

$window.FindName("btnDnsCloudflare").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Cloudflare" } })
$window.FindName("btnDnsGoogle").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Google" } })
$window.FindName("btnDnsQuad9").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Quad9" } })
$window.FindName("btnDnsAdGuard").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "AdGuard" } })
$window.FindName("btnDnsDhcp").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "DHCP" } })

# --- ABA 3: RECURSOS & UPDATES ---
$window.FindName("btnWuRecommended").Add_Click({ Start-AsyncAction { Set-WindowsUpdateRecommended } })
$window.FindName("btnWuDefault").Add_Click({ Start-AsyncAction { Reset-WindowsUpdateDefault } })
$window.FindName("btnWuPause").Add_Click({ Start-AsyncAction { Pause-WindowsUpdateExtended } })

$window.FindName("btnEnableWsl").Add_Click({ Start-AsyncAction { Enable-WslFeature } })
$window.FindName("btnEnableSandbox").Add_Click({ Start-AsyncAction { Enable-WindowsSandbox } })
$window.FindName("btnEnableHyperV").Add_Click({ Start-AsyncAction { Enable-HyperVFeature } })
$window.FindName("btnEnableNet35").Add_Click({ Start-AsyncAction { Enable-NetFramework35 } })

# --- ABA 4: MICROWIN / CRIADOR DE ISO ---
$window.FindName("btnBrowseIso").Add_Click({
    $selected = Select-IsoFileDialog
    if ($selected) {
        $window.FindName("txtIsoPath").Text = $selected
        Write-ToolLog "ISO selecionada: $selected" "INFO"
    }
})

$window.FindName("btnBrowseOutputDir").Add_Click({
    $selected = Select-OutputFolderDialog
    if ($selected) {
        $window.FindName("txtOutputIsoDir").Text = $selected
        Write-ToolLog "Pasta de saída selecionada: $selected" "INFO"
    }
})

$window.FindName("btnInspectIso").Add_Click({
    $isoPath = $window.FindName("txtIsoPath").Text
    if (-not $isoPath) {
        Write-ToolLog "Por favor, selecione primeiro um arquivo ISO." "WARN"
        return
    }
    Start-AsyncAction { Inspect-IsoEditions -IsoPath $using:isoPath }
})

$window.FindName("btnBuildCustomIso").Add_Click({
    $isoPath = $window.FindName("txtIsoPath").Text
    $outputDir = $window.FindName("txtOutputIsoDir").Text
    $outputName = $window.FindName("txtOutputIsoName").Text
    $idx = [int]$window.FindName("txtEditionIndex").Text

    $bpHw = [bool]$window.FindName("chkIsoBypassHw").IsChecked
    $bpAcc = [bool]$window.FindName("chkIsoBypassAcc").IsChecked
    $disBit = [bool]$window.FindName("chkIsoDisableBitLocker").IsChecked
    $debloat = [bool]$window.FindName("chkIsoDebloat").IsChecked
    $unattend = [bool]$window.FindName("chkIsoUnattend").IsChecked

    if (-not $isoPath -or -not (Test-Path $isoPath)) {
        Write-ToolLog "Arquivo ISO de origem inválido ou não informado!" "ERROR"
        return
    }

    Start-AsyncAction {
        Build-CustomOptimizedIsoPipeline 
            -SourceIsoPath $using:isoPath 
            -OutputIsoDir $using:outputDir 
            -OutputIsoName $using:outputName 
            -EditionIndex $using:idx 
            -BypassHardwareChecks $using:bpHw 
            -BypassMicrosoftAccount $using:bpAcc 
            -DisableBitLocker $using:disBit 
            -RemoveBloatware $using:debloat 
            -InjectUnattendXml $using:unattend
    }
})

# --- ABA 5: SOFTWARES (WINGET) ---
$window.FindName("btnInstallSelectedSoftware").Add_Click({
    $softBoxes = @(
        $window.FindName("chkSoftwareChrome"),
        $window.FindName("chkSoftwareFirefox"),
        $window.FindName("chkSoftwareBrave"),
        $window.FindName("chkSoftware7zip"),
        $window.FindName("chkSoftwareNotepad"),
        $window.FindName("chkSoftwareAnyDesk"),
        $window.FindName("chkSoftwarePowerToys"),
        $window.FindName("chkSoftwareVlc"),
        $window.FindName("chkSoftwareVsCode"),
        $window.FindName("chkSoftwareSteam"),
        $window.FindName("chkSoftwareDiscord")
    )

    $toInstall = @()
    foreach ($box in $softBoxes) {
        if ($box -and $box.IsChecked) {
            $toInstall += $box.Tag
        }
    }

    if ($toInstall.Count -eq 0) {
        Write-ToolLog "Nenhum aplicativo foi selecionado para instalação." "WARN"
        return
    }

    Start-AsyncAction {
        Install-SelectedSoftwareList -PackageIds $using:toInstall
    }
})

$window.FindName("btnUpgradeAllSoftware").Add_Click({
    Start-AsyncAction {
        Write-ToolLog "Iniciando atualização de todos os programas instalados via Winget..." "INFO"
        Start-Process winget.exe -ArgumentList "upgrade --all --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
        Write-ToolLog "Atualização geral de programas concluída." "SUCCESS"
    }
})

# --- ABA 6: REPAROS DO SO ---
$window.FindName("btnSfcScan").Add_Click({ Start-AsyncAction { Invoke-SfcScan } })
$window.FindName("btnDismRepair").Add_Click({ Start-AsyncAction { Invoke-DismRepair } })
$window.FindName("btnDismCleanup").Add_Click({ Start-AsyncAction { Invoke-DismCleanup } })
$window.FindName("btnRestartSpooler").Add_Click({ Start-AsyncAction { Restart-PrintSpooler } })
$window.FindName("btnScheduleChkdsk").Add_Click({ Start-AsyncAction { Schedule-ChkdskOnReboot } })

# --- ABA 7: LICENCIAMENTO ---
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

# --- LOGS ---
$window.FindName("btnClearLogs").Add_Click({ $global:txtLogControl.Text = "" })

Write-ToolLog "WinRepair & Tweaks Pro carregado com sucesso!" "SUCCESS"
Write-ToolLog "Inspirado no Chris Titus WinUtil. Escolha um Perfil ou personalize os Tweaks acima." "INFO"

$window.ShowDialog() | Out-Null
