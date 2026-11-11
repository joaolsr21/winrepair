# ==============================================================================
# Módulo Avançado: Otimizações de Desempenho, Debloat e Ajustes do Sistema
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
        # GUID do Ultimate Performance
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $output = powercfg -duplicatescheme $guid 2>&1
        powercfg -setactive $guid
        Write-ToolLog "Plano 'Desempenho Máximo' ativado para CPU e componentes com latência mínima." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao ativar o plano de energia: $_" "ERROR"
    }
}

function Optimize-WindowsTelemetryAndPrivacy {
    Write-ToolLog "Desativando rastreamento de telemetria, diagnóstico e coleta de dados..." "INFO"
    try {
        # 1. Serviços de telemetria
        $services = @("DiagTrack", "dmwappushservice", "diagnosticshub.standardcollector.service")
        foreach ($s in $services) {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
                Write-ToolLog "Serviço $s desativado." "INFO"
            }
        }

        # 2. Desativar Telemetria via Registro (Políticas de Grupo)
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) { New-Item -Path $dataCollectionKey -Force | Out-Null }
        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dataCollectionKey -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force

        # 3. Desativar ID de Anúncio e Sugestões do Windows
        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) { New-Item -Path $advertisingKey -Force | Out-Null }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

        # 4. Desativar Tarefas Agendadas de Coleta / CEIP (Customer Experience Improvement)
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

        Write-ToolLog "Políticas e tarefas de telemetria desativadas com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar telemetria: $_" "ERROR"
    }
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
        # Desativar Bing no Menu Iniciar
        $searchKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
        Set-ItemProperty -Path $searchKey -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

        $userSearchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $userSearchKey)) { New-Item -Path $userSearchKey -Force | Out-Null }
        Set-ItemProperty -Path $userSearchKey -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchKey -Name "CortanaConsent" -Value 0 -Type DWord -Force

        # Desativar aplicativos sugeridos / instalados silenciosamente pela Microsoft
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
    Write-ToolLog "Ajustando tempo de resposta de menus e animações do Windows..." "INFO"
    try {
        # Acelerar abertura de menus suspensos (MenuShowDelay de 400ms para 10ms)
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "10" -Force

        # Otimizar agendador de prioridade de CPU para programas em primeiro plano
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force

        Write-ToolLog "Prioridade de processos e velocidade de menus aceleradas." "SUCCESS"
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
