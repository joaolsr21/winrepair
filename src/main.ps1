# ==============================================================================
# Script Principal: WinRepair & Tweaks Utility
# ==============================================================================

# Garantir TLS moderno e políticas adequadas
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Identificar diretório base
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptRoot) {
    $scriptRoot = Get-Location
}

# Carregar bibliotecas e módulos
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

# 3. Carregar arquivo XAML
if (-not (Test-Path $uiPath)) {
    Write-Error "Arquivo de interface XAML não encontrado em: $uiPath"
    return
}

[xml]$xaml = Get-Content -Path $uiPath -Raw
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Configurar controles globais de logging
$global:txtLogControl = $window.FindName("txtLog")
$global:uiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

# 4. Preencher Informações do Sistema no Cabeçalho
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $window.FindName("txtSystemInfo").Text = "$($os.Caption) ($($os.OSArchitecture)) | $ramGb GB RAM | Host: $($env:COMPUTERNAME)"
} catch {
    $window.FindName("txtSystemInfo").Text = "Windows $($env:OS) | Host: $($env:COMPUTERNAME)"
}

# Helper para executar tarefas em background e evitar congelamento da UI
function Start-AsyncAction {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action
    )

    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            & $using:Action
        } catch {
            Write-ToolLog "Erro na execução da tarefa: $_" "ERROR"
        }
    }) | Out-Null
}

# ==============================================================================
# VINCULAÇÃO DE EVENTOS DA INTERFACE (Binds)
# ==============================================================================

# --- ABA 1: REDE ---
$window.FindName("btnFlushDns").Add_Click({
    Start-AsyncAction { Invoke-FlushDns }
})

$window.FindName("btnResetNetwork").Add_Click({
    Start-AsyncAction { Invoke-ResetNetworkStack }
})

$window.FindName("btnRenewDhcp").Add_Click({
    Start-AsyncAction { Invoke-RenewDhcp }
})

$window.FindName("btnRestartAdapters").Add_Click({
    Start-AsyncAction { Restart-NetworkAdapters }
})

$window.FindName("btnDnsCloudflare").Add_Click({
    Start-AsyncAction { Set-CustomDns -Provider "Cloudflare" }
})

$window.FindName("btnDnsGoogle").Add_Click({
    Start-AsyncAction { Set-CustomDns -Provider "Google" }
})

$window.FindName("btnDnsDhcp").Add_Click({
    Start-AsyncAction { Set-CustomDns -Provider "DHCP" }
})

# --- ABA 2: OTIMIZAÇÃO ---
$window.FindName("btnClearTemp").Add_Click({
    Start-AsyncAction { Clear-TempFiles }
})

$window.FindName("btnClearWuCache").Add_Click({
    Start-AsyncAction { Clear-WindowsUpdateCache }
})

$window.FindName("btnSsdTrim").Add_Click({
    Start-AsyncAction { Optimize-SsdTrim }
})

$window.FindName("btnOptimizeTelemetry").Add_Click({
    Start-AsyncAction { Optimize-TelemetryAndPrivacy }
})

$window.FindName("btnDisableHibernation").Add_Click({
    Start-AsyncAction { Set-HibernationState -Enable $false }
})

$window.FindName("btnEnableHibernation").Add_Click({
    Start-AsyncAction { Set-HibernationState -Enable $true }
})

# --- ABA 3: REPARO DO SISTEMA ---
$window.FindName("btnSfcScan").Add_Click({
    Start-AsyncAction { Invoke-SfcScan }
})

$window.FindName("btnDismRepair").Add_Click({
    Start-AsyncAction { Invoke-DismRepair }
})

$window.FindName("btnDismCleanup").Add_Click({
    Start-AsyncAction { Invoke-DismCleanup }
})

$window.FindName("btnScheduleChkdsk").Add_Click({
    Start-AsyncAction { Schedule-ChkdskOnReboot }
})

$window.FindName("btnRestartSpooler").Add_Click({
    Start-AsyncAction { Restart-PrintSpooler }
})

# --- ABA 4: CRIADOR DE ISO ---
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
    Start-AsyncAction {
        Mount-CustomWim -WimPath $using:wimPath -MountDir $using:mountDir -Index $using:index
    }
})

$window.FindName("btnDebloatWim").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction {
        Remove-ProvisionedBloatware -MountDir $using:mountDir
    }
})

$window.FindName("btnBypassWim").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction {
        Add-BypassHardwareChecksToWim -MountDir $using:mountDir
    }
})

$window.FindName("btnSaveDismount").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction {
        Save-AndDismountWim -MountDir $using:mountDir -Save $true
    }
})

$window.FindName("btnDiscardDismount").Add_Click({
    $mountDir = $window.FindName("txtMountDir").Text
    Start-AsyncAction {
        Save-AndDismountWim -MountDir $using:mountDir -Save $false
    }
})

# --- ABA 5: LICENCIAMENTO ---
$window.FindName("btnCheckWinLicense").Add_Click({
    Start-AsyncAction { Get-WindowsActivationStatus }
})

$window.FindName("btnApplyWinKey").Add_Click({
    $key = $window.FindName("txtWinKey").Text
    if (-not $key) {
        Write-ToolLog "Por favor, digite a chave de produto do Windows." "WARN"
        return
    }
    Start-AsyncAction {
        Install-WindowsProductKey -ProductKey $using:key
    }
})

$window.FindName("btnCheckOfficeLicense").Add_Click({
    Start-AsyncAction { Get-OfficeActivationStatus }
})

$window.FindName("btnApplyOfficeKey").Add_Click({
    $key = $window.FindName("txtOfficeKey").Text
    if (-not $key) {
        Write-ToolLog "Por favor, digite a chave de produto do Office." "WARN"
        return
    }
    Start-AsyncAction {
        Install-OfficeProductKey -ProductKey $using:key
    }
})

$window.FindName("btnSetKms").Add_Click({
    $kmsHost = $window.FindName("txtKmsHost").Text
    if (-not $kmsHost) {
        Write-ToolLog "Informe o endereço do servidor KMS institucional." "WARN"
        return
    }
    Start-AsyncAction {
        Set-EnterpriseKmsServer -KmsHost $using:kmsHost
    }
})

# --- PAINEL DE LOGS ---
$window.FindName("btnClearLogs").Add_Click({
    $global:txtLogControl.Text = ""
})

# Inicialização
Write-ToolLog "WinRepair & Tweaks Utility inicializado com sucesso!" "SUCCESS"
Write-ToolLog "Selecione uma das abas acima para executar as ações desejadas." "INFO"

# Exibir Janela
$window.ShowDialog() | Out-Null
