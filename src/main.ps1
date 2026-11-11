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

# Controles globais de log
$global:txtLogControl = $window.FindName("txtLog")
$global:uiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

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
    param([Parameter(Mandatory=$true)][scriptblock]$Action)
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            & $using:Action
        } catch {
            Write-ToolLog "Erro na execução da tarefa: $_" "ERROR"
        }
    }) | Out-Null
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
    Start-AsyncAction { Inspect-IsoEditions -IsoPath `$using:isoPath }
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
        Build-CustomOptimizedIsoPipeline `
            -SourceIsoPath $using:isoPath `
            -OutputIsoDir $using:outputDir `
            -OutputIsoName $using:outputName `
            -EditionIndex $using:idx `
            -BypassHardwareChecks $using:bpHw `
            -BypassMicrosoftAccount $using:bpAcc `
            -DisableBitLocker $using:disBit `
            -RemoveBloatware $using:debloat `
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
