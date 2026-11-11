# ==============================================================================
# Script Principal: WinRepair & Tweaks Pro
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

# Importar scripts auxiliares se estiver em desenvolvimento modular
if (Test-Path $srcCore) {
    . (Join-Path $srcCore "elevation.ps1")
    . (Join-Path $srcCore "logger.ps1")
    . (Join-Path $srcModules "network.ps1")
    . (Join-Path $srcModules "optimizer.ps1")
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

# 2. Carregar assemblies do WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

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

# --- ABA 1: REDE ---
$window.FindName("btnTestNetwork").Add_Click({ Start-AsyncAction { Test-NetworkQuality } })
$window.FindName("btnFlushDns").Add_Click({ Start-AsyncAction { Invoke-FlushDns } })
$window.FindName("btnRenewDhcp").Add_Click({ Start-AsyncAction { Invoke-RenewDhcp } })
$window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction { Restart-NetworkAdapters } })
$window.FindName("btnOptimizeTcp").Add_Click({ Start-AsyncAction { Optimize-TcpLatencyAndThroughput } })
$window.FindName("btnResetNetwork").Add_Click({ Start-AsyncAction { Invoke-ResetNetworkStack } })

$window.FindName("btnDnsCloudflare").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Cloudflare" } })
$window.FindName("btnDnsGoogle").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Google" } })
$window.FindName("btnDnsQuad9").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "Quad9" } })
$window.FindName("btnDnsAdGuard").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "AdGuard" } })
$window.FindName("btnDnsDhcp").Add_Click({ Start-AsyncAction { Set-QuickDnsProvider -Provider "DHCP" } })

# --- ABA 2: OTIMIZAÇÃO & DEBLOAT ---
$window.FindName("btnClearTemp").Add_Click({ Start-AsyncAction { Clear-TempFiles } })
$window.FindName("btnClearWuCache").Add_Click({ Start-AsyncAction { Clear-WindowsUpdateCache } })
$window.FindName("btnSsdTrim").Add_Click({ Start-AsyncAction { Optimize-SsdTrim } })
$window.FindName("btnUltimatePower").Add_Click({ Start-AsyncAction { Enable-UltimatePerformancePowerPlan } })
$window.FindName("btnDisableGameDvr").Add_Click({ Start-AsyncAction { Disable-GameDvrAndBackgroundRecording } })
$window.FindName("btnFastVisuals").Add_Click({ Start-AsyncAction { Optimize-SystemResponsivenessAndVisuals } })
$window.FindName("btnDisableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable $false } })
$window.FindName("btnEnableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable $true } })
$window.FindName("btnDebloatApps").Add_Click({ Start-AsyncAction { Invoke-SystemDebloatAppx } })
$window.FindName("btnOptimizeTelemetry").Add_Click({ Start-AsyncAction { Optimize-WindowsTelemetryAndPrivacy } })
$window.FindName("btnDisableStartAds").Add_Click({ Start-AsyncAction { Disable-StartMenuAdsAndBingSearch } })

# --- ABA 3: REPARO DO SISTEMA ---
$window.FindName("btnSfcScan").Add_Click({ Start-AsyncAction { Invoke-SfcScan } })
$window.FindName("btnDismRepair").Add_Click({ Start-AsyncAction { Invoke-DismRepair } })
$window.FindName("btnDismCleanup").Add_Click({ Start-AsyncAction { Invoke-DismCleanup } })
$window.FindName("btnRestartSpooler").Add_Click({ Start-AsyncAction { Restart-PrintSpooler } })
$window.FindName("btnScheduleChkdsk").Add_Click({ Start-AsyncAction { Schedule-ChkdskOnReboot } })

# --- ABA 4: CRIADOR DE ISO CUSTOMIZADA ---
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
        Write-ToolLog "Por favor, selecione primeiro uma imagem ISO." "WARN"
        return
    }
    Start-AsyncAction {
        Inspect-IsoEditions -IsoPath $using:isoPath
    }
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

# --- ABA 6: LICENCIAMENTO ---
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

# Logs
$window.FindName("btnClearLogs").Add_Click({ $global:txtLogControl.Text = "" })

Write-ToolLog "WinRepair & Tweaks Pro carregado com sucesso!" "SUCCESS"
Write-ToolLog "Selecione uma das abas acima para iniciar otimizações ou reparos." "INFO"

$window.ShowDialog() | Out-Null
