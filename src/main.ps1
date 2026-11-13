# ==============================================================================
# Script Principal: WinRepair & Tweaks Pro (Estilo Chris Titus WinUtil)
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Identificar diretório base
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptRoot) {
    $scriptRoot = Get-Location
}

$srcCore = Join-Path $scriptRoot "core"
$srcModules = Join-Path $scriptRoot "modules"
$uiPath = Join-Path $scriptRoot "ui\app.xaml"

# Importar scripts auxiliares modulares
if (Test-Path $srcCore) {
    . (Join-Path $srcCore "elevation.ps1")
    . (Join-Path $srcCore "logger.ps1")
    . (Join-Path $srcModules "network.ps1")
    . (Join-Path $srcModules "optimizer.ps1")
    . (Join-Path $srcModules "tweaks_system.ps1")
    . (Join-Path $srcModules "windows_features.ps1")
    . (Join-Path $srcModules "windows_update.ps1")
    . (Join-Path $srcModules "system_repair.ps1")
    . (Join-Path $srcModules "iso_builder.ps1")
    . (Join-Path $srcModules "software_installer.ps1")
    . (Join-Path $srcModules "licensing.ps1")
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

# 3. Carregar arquivo XAML com codificação UTF-8 estrita
if (-not (Test-Path $uiPath)) {
    Write-Error "Arquivo XAML não encontrado em: $uiPath"
    return
}

$xamlText = [System.IO.File]::ReadAllText($uiPath, [System.Text.Encoding]::UTF8)
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Controles globais sincronizados entre threads
$global:txtLogControl = $window.FindName("txtLog")
$global:WinRepairSync = [hashtable]::Synchronized(@{
    LogQueue   = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    ActiveJobs = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
})

# Preparar InitialSessionState para tarefas assíncronas em Runspaces
$global:BaseInitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$global:BaseInitialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry("WinRepairSync", $global:WinRepairSync, $null)))
foreach ($fn in (Get-ChildItem Function:\ | Where-Object { -not $_.ModuleName -and $_.Name.Length -gt 2 -and $_.Name -notmatch ':' })) {
    try {
        $global:BaseInitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn.Name, $fn.Definition)))
    } catch {}
}

# Timer da UI para atualizar logs em tempo real e limpar Runspaces concluídos
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$uiTimer.Add_Tick({
    $line = $null
    $updated = $false
    while ($global:WinRepairSync.LogQueue.TryDequeue([ref]$line)) {
        $global:txtLogControl.AppendText("$line`r`n")
        $updated = $true
    }
    if ($updated) {
        $global:txtLogControl.ScrollToEnd()
    }

    for ($i = $global:WinRepairSync.ActiveJobs.Count - 1; $i -ge 0; $i--) {
        $job = $global:WinRepairSync.ActiveJobs[$i]
        if ($job.Handle.IsCompleted) {
            try { $job.PowerShell.EndInvoke($job.Handle) | Out-Null } catch {}
            $job.PowerShell.Dispose()
            $job.Runspace.Close()
            $job.Runspace.Dispose()
            $global:WinRepairSync.ActiveJobs.RemoveAt($i)
        }
    }
})
$uiTimer.Start()

# 4. Informações da máquina no cabeçalho
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $window.FindName("txtSystemInfo").Text = "$($os.Caption) ($($os.OSArchitecture)) | $ramGb GB RAM | Host: $($env:COMPUTERNAME)"
} catch {
    $window.FindName("txtSystemInfo").Text = "Windows $($env:OS) | Host: $($env:COMPUTERNAME)"
}

function Start-AsyncAction {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [hashtable]$Vars = @{}
    )
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($global:BaseInitialSessionState)
    $rs.Open()
    foreach ($k in $Vars.Keys) {
        $rs.SessionStateProxy.SetVariable($k, $Vars[$k])
    }
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $wrappedCode = "try {`n$($Action.ToString())`n} catch { Write-ToolLog `"Erro na execução da tarefa: `$_`" 'ERROR' }"
    [void]$ps.AddScript($wrappedCode)
    $handle = $ps.BeginInvoke()
    [void]$global:WinRepairSync.ActiveJobs.Add([pscustomobject]@{
        PowerShell = $ps
        Runspace   = $rs
        Handle     = $handle
    })
}

# ==============================================================================
# VINCULAÇÃO DE EVENTOS (BINDS)
# ==============================================================================

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

    Start-AsyncAction -Vars @{ tweaks = $tweaks } -Action {
        Write-ToolLog "=== INICIANDO APLICAÇÃO DOS TWEAKS SELECIONADOS ===" "INFO"

        if ($tweaks.CleanTemp) { Clear-TempFiles }
        if ($tweaks.DisableTelemetry) { Optimize-WindowsTelemetryAndPrivacy }
        if ($tweaks.DisableBingSearch) { Disable-StartMenuAdsAndBingSearch }
        if ($tweaks.DisableGameDvr) { Disable-GameDvrAndBackgroundRecording }
        if ($tweaks.OptimizeServices) { Optimize-WindowsServicesManual }
        if ($tweaks.UltimatePower) { Enable-UltimatePerformancePowerPlan }
        if ($tweaks.DisableHibernation) { Set-HibernationState -Enable $false }
        if ($tweaks.FastVisuals) { Optimize-SystemResponsivenessAndVisuals }
        if ($tweaks.SsdTrim) { Optimize-SsdTrim }

        if ($tweaks.ShowFileExt) { Set-ShowFileExtensions -Enable $true }
        if ($tweaks.ShowHiddenFiles) { Set-ShowHiddenFiles -Enable $true }
        if ($tweaks.ExplorerThisPc) { Set-ExplorerOpenToThisPC }
        if ($tweaks.DarkMode) { Set-SystemDarkMode -Enable $true }
        if ($tweaks.DisableMouseAccel) { Disable-MouseAcceleration }
        if ($tweaks.CleanWin11Taskbar) { Disable-Win11TaskbarJunk }
        if ($tweaks.TakeOwnership) { Add-TakeOwnershipContextMenu }
        if ($tweaks.UninstallOneDrive) { Uninstall-OneDrivePurge }

        if ($tweaks.OptimizeTcp) { Optimize-TcpLatencyAndThroughput }
        if ($tweaks.FlushDns) { Invoke-FlushDns }
        if ($tweaks.RenewDhcp) { Invoke-RenewDhcp }
        if ($tweaks.ResetNetwork) { Invoke-ResetNetworkStack }

        Write-ToolLog "=== TODOS OS TWEAKS SELECIONADOS FORAM APLICADOS COM SUCESSO! ===" "SUCCESS"
    }
})

# --- ABA 2: REDE & DIAGNOSTICO COMPLETO ---
$window.FindName("btnNetQuickDiag").Add_Click({ Start-AsyncAction { Invoke-QuickIntegratedNetworkDiag } })
$window.FindName("btnNetDetailed").Add_Click({ Start-AsyncAction { Invoke-DetailedInternetTest } })
$window.FindName("btnNetSpeedtest").Add_Click({ Start-AsyncAction { Invoke-DownloadSpeedTest } })
$window.FindName("btnNetWifi").Add_Click({ Start-AsyncAction { Invoke-WifiDiagnostics -GenerateHtmlReport $false } })
$window.FindName("btnNetWifiReport").Add_Click({ Start-AsyncAction { Invoke-WifiDiagnostics -GenerateHtmlReport $true } })

$window.FindName("btnNetTestPort").Add_Click({
    $target = $window.FindName("txtNetTarget").Text
    $portVal = 443
    if (-not [int]::TryParse($window.FindName("txtNetPort").Text, [ref]$portVal)) {
        Write-ToolLog "Informe um número de porta TCP válido (ex: 80, 443, 3389)." "WARN"
        return
    }
    if (-not $target) { $target = "google.com" }
    Start-AsyncAction -Vars @{ target = $target; portVal = $portVal } -Action {
        Test-SpecificTcpPort -TargetHost $target -Port $portVal
    }
})

$window.FindName("btnNetPathping").Add_Click({
    $target = $window.FindName("txtNetTarget").Text
    Start-AsyncAction -Vars @{ target = $target } -Action { Invoke-PathpingAnalysis -TargetHost $target }
})

$window.FindName("btnNetTracert").Add_Click({
    $target = $window.FindName("txtNetTarget").Text
    Start-AsyncAction -Vars @{ target = $target } -Action { Invoke-TracertAnalysis -TargetHost $target }
})

$window.FindName("btnNetPingCont").Add_Click({
    $target = $window.FindName("txtNetTarget").Text
    Start-ContinuousPingWindow -TargetHost $target
})

$window.FindName("btnNetstatEst").Add_Click({ Start-AsyncAction { Get-ActiveConnectionsNetstat -Mode "Established" } })
$window.FindName("btnNetstatList").Add_Click({ Start-AsyncAction { Get-ActiveConnectionsNetstat -Mode "Listening" } })
$window.FindName("btnNetstatAll").Add_Click({ Start-AsyncAction { Get-ActiveConnectionsNetstat -Mode "All" } })
$window.FindName("btnNetSubnetScan").Add_Click({ Start-AsyncAction { Invoke-LocalSubnetScan -SaveAndOpenReport $true } })
$window.FindName("btnNetIpConfig").Add_Click({ Start-AsyncAction { Get-IpConfigAllDetails } })

$window.FindName("btnNetSimpleRepair").Add_Click({ Start-AsyncAction { Invoke-SimpleNetworkRepair } })
$window.FindName("btnNetResetDeep").Add_Click({ Start-AsyncAction { Invoke-ResetNetworkStack } })
$window.FindName("btnNetForensicReport").Add_Click({ Start-AsyncAction { Export-ForensicNetworkReport } })
$window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction { Restart-NetworkAdapters } })
$window.FindName("btnOptimizeTcpTab").Add_Click({ Start-AsyncAction { Optimize-TcpLatencyAndThroughput } })

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
    Start-AsyncAction -Vars @{ isoPath = $isoPath } -Action { Inspect-IsoEditions -IsoPath $isoPath }
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

    Start-AsyncAction -Vars @{
        isoPath    = $isoPath
        outputDir  = $outputDir
        outputName = $outputName
        idx        = $idx
        bpHw       = $bpHw
        bpAcc      = $bpAcc
        disBit     = $disBit
        debloat    = $debloat
        unattend   = $unattend
    } -Action {
        Build-CustomOptimizedIsoPipeline `
            -SourceIsoPath $isoPath `
            -OutputIsoDir $outputDir `
            -OutputIsoName $outputName `
            -EditionIndex $idx `
            -BypassHardwareChecks $bpHw `
            -BypassMicrosoftAccount $bpAcc `
            -DisableBitLocker $disBit `
            -RemoveBloatware $debloat `
            -InjectUnattendXml $unattend
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

    Start-AsyncAction -Vars @{ toInstall = $toInstall } -Action {
        Install-SelectedSoftwareList -PackageIds $toInstall
    }
})

$window.FindName("btnUpgradeAllSoftware").Add_Click({
    Start-AsyncAction {
        Write-ToolLog "Iniciando atualização de todos os programas instalados via Winget..." "INFO"
        Start-Process winget.exe -ArgumentList "upgrade --all --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
        Write-ToolLog "Atualização geral concluída." "SUCCESS"
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
    Start-AsyncAction -Vars @{ key = $key } -Action { Install-WindowsProductKey -ProductKey $key }
})

$window.FindName("btnCheckOfficeLicense").Add_Click({ Start-AsyncAction { Get-OfficeActivationStatus } })
$window.FindName("btnApplyOfficeKey").Add_Click({
    $key = $window.FindName("txtOfficeKey").Text
    if (-not $key) { Write-ToolLog "Informe a chave do Office." "WARN"; return }
    Start-AsyncAction -Vars @{ key = $key } -Action { Install-OfficeProductKey -ProductKey $key }
})

$window.FindName("btnSetKms").Add_Click({
    $kmsHost = $window.FindName("txtKmsHost").Text
    if (-not $kmsHost) { Write-ToolLog "Informe o host KMS." "WARN"; return }
    Start-AsyncAction -Vars @{ kmsHost = $kmsHost } -Action { Set-EnterpriseKmsServer -KmsHost $kmsHost }
})

# --- LOGS ---
$window.FindName("btnClearLogs").Add_Click({ $global:txtLogControl.Text = "" })

Write-ToolLog "WinRepair & Tweaks Pro carregado com sucesso!" "SUCCESS"
Write-ToolLog "Inspirado no Chris Titus WinUtil. Escolha um Perfil ou personalize os Tweaks acima." "INFO"

$window.Add_Closed({ $uiTimer.Stop() })
$window.ShowDialog() | Out-Null
