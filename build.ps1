# ==============================================================================
# Script de Build: Empacotador para Execução Única via irm | iex
# ==============================================================================
param(
    [string]$OutputDir = "$PSScriptRoot\dist",
    [string]$OutputFile = "winrepair.ps1"
)

Write-Host "[*] Iniciando compilação do WinRepair com suporte UTF-8..." -ForegroundColor Cyan

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$destination = Join-Path $OutputDir $OutputFile

$banner = @"
# ==============================================================================
# WinRepair & Tweaks Utility (Standalone All-in-One)
# Execução direta via: irm <URL> | iex
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

"@

# Coletar arquivos do core e modules
$coreFiles = @(
    "$PSScriptRoot\src\core\elevation.ps1",
    "$PSScriptRoot\src\core\logger.ps1"
)

$moduleFiles = @(
    "$PSScriptRoot\src\modules\network.ps1",
    "$PSScriptRoot\src\modules\optimizer.ps1",
    "$PSScriptRoot\src\modules\system_repair.ps1",
    "$PSScriptRoot\src\modules\iso_builder.ps1",
    "$PSScriptRoot\src\modules\licensing.ps1"
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($banner)

# Adicionar arquivos do core lendo explicitamente como UTF-8
foreach ($f in $coreFiles) {
    if (Test-Path $f) {
        Write-Host " -> Agregando $(Split-Path $f -Leaf)..." -ForegroundColor Gray
        $content = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
        [void]$sb.AppendLine($content)
        [void]$sb.AppendLine()
    }
}

# Adicionar módulos lendo explicitamente como UTF-8
foreach ($f in $moduleFiles) {
    if (Test-Path $f) {
        Write-Host " -> Agregando $(Split-Path $f -Leaf)..." -ForegroundColor Gray
        $content = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
        [void]$sb.AppendLine($content)
        [void]$sb.AppendLine()
    }
}

# Adicionar lógica de runtime com XAML embutido lido como UTF-8
$xamlPath = "$PSScriptRoot\src\ui\app.xaml"
$xamlContent = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)

$runtimeScript = @"
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
[xml]`$xaml = @'
$xamlContent
'@

`$reader = New-Object System.Xml.XmlNodeReader `$xaml
`$window = [Windows.Markup.XamlReader]::Load(`$reader)

`$global:txtLogControl = `$window.FindName("txtLog")
`$global:uiDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

# Informações do Sistema
try {
    `$os = Get-CimInstance Win32_OperatingSystem
    `$cs = Get-CimInstance Win32_ComputerSystem
    `$ramGb = [math]::Round(`$cs.TotalPhysicalMemory / 1GB, 1)
    `$window.FindName("txtSystemInfo").Text = "`$(`$os.Caption) (`$(`$os.OSArchitecture)) | `$ramGb GB RAM | Host: `$(`$env:COMPUTERNAME)"
} catch {
    `$window.FindName("txtSystemInfo").Text = "Windows `$(`$env:OS) | Host: `$(`$env:COMPUTERNAME)"
}

function Start-AsyncAction {
    param([Parameter(Mandatory=`$true)][scriptblock]`$Action)
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            & `$using:Action
        } catch {
            Write-ToolLog "Erro na execução da tarefa: `$_" "ERROR"
        }
    }) | Out-Null
}

# Binds de Eventos
`$window.FindName("btnFlushDns").Add_Click({ Start-AsyncAction { Invoke-FlushDns } })
`$window.FindName("btnResetNetwork").Add_Click({ Start-AsyncAction { Invoke-ResetNetworkStack } })
`$window.FindName("btnRenewDhcp").Add_Click({ Start-AsyncAction { Invoke-RenewDhcp } })
`$window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction { Restart-NetworkAdapters } })
`$window.FindName("btnDnsCloudflare").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "Cloudflare" } })
`$window.FindName("btnDnsGoogle").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "Google" } })
`$window.FindName("btnDnsDhcp").Add_Click({ Start-AsyncAction { Set-CustomDns -Provider "DHCP" } })

`$window.FindName("btnClearTemp").Add_Click({ Start-AsyncAction { Clear-TempFiles } })
`$window.FindName("btnClearWuCache").Add_Click({ Start-AsyncAction { Clear-WindowsUpdateCache } })
`$window.FindName("btnSsdTrim").Add_Click({ Start-AsyncAction { Optimize-SsdTrim } })
`$window.FindName("btnOptimizeTelemetry").Add_Click({ Start-AsyncAction { Optimize-TelemetryAndPrivacy } })
`$window.FindName("btnDisableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable `$false } })
`$window.FindName("btnEnableHibernation").Add_Click({ Start-AsyncAction { Set-HibernationState -Enable `$true } })

`$window.FindName("btnSfcScan").Add_Click({ Start-AsyncAction { Invoke-SfcScan } })
`$window.FindName("btnDismRepair").Add_Click({ Start-AsyncAction { Invoke-DismRepair } })
`$window.FindName("btnDismCleanup").Add_Click({ Start-AsyncAction { Invoke-DismCleanup } })
`$window.FindName("btnScheduleChkdsk").Add_Click({ Start-AsyncAction { Schedule-ChkdskOnReboot } })
`$window.FindName("btnRestartSpooler").Add_Click({ Start-AsyncAction { Restart-PrintSpooler } })

`$window.FindName("btnGetWimInfo").Add_Click({
    `$wimPath = `$window.FindName("txtWimPath").Text
    Start-AsyncAction {
        `$info = Get-WimImageInfo -WimPath `$using:wimPath
        if (`$info) {
            foreach (`$img in `$info) {
                Write-ToolLog "Índice [`$(`$img.ImageIndex)]: `$(`$img.ImageName) (`$(`$img.ImageSize / 1GB -as [int]) GB)" "INFO"
            }
        }
    }
})

`$window.FindName("btnMountWim").Add_Click({
    `$wimPath = `$window.FindName("txtWimPath").Text
    `$mountDir = `$window.FindName("txtMountDir").Text
    `$index = [int]`$window.FindName("txtWimIndex").Text
    Start-AsyncAction { Mount-CustomWim -WimPath `$using:wimPath -MountDir `$using:mountDir -Index `$using:index }
})

`$window.FindName("btnDebloatWim").Add_Click({
    `$mountDir = `$window.FindName("txtMountDir").Text
    Start-AsyncAction { Remove-ProvisionedBloatware -MountDir `$using:mountDir }
})

`$window.FindName("btnBypassWim").Add_Click({
    `$mountDir = `$window.FindName("txtMountDir").Text
    Start-AsyncAction { Add-BypassHardwareChecksToWim -MountDir `$using:mountDir }
})

`$window.FindName("btnSaveDismount").Add_Click({
    `$mountDir = `$window.FindName("txtMountDir").Text
    Start-AsyncAction { Save-AndDismountWim -MountDir `$using:mountDir -Save `$true }
})

`$window.FindName("btnDiscardDismount").Add_Click({
    `$mountDir = `$window.FindName("txtMountDir").Text
    Start-AsyncAction { Save-AndDismountWim -MountDir `$using:mountDir -Save `$false }
})

`$window.FindName("btnCheckWinLicense").Add_Click({ Start-AsyncAction { Get-WindowsActivationStatus } })
`$window.FindName("btnApplyWinKey").Add_Click({
    `$key = `$window.FindName("txtWinKey").Text
    if (-not `$key) { Write-ToolLog "Informe a chave do Windows." "WARN"; return }
    Start-AsyncAction { Install-WindowsProductKey -ProductKey `$using:key }
})

`$window.FindName("btnCheckOfficeLicense").Add_Click({ Start-AsyncAction { Get-OfficeActivationStatus } })
`$window.FindName("btnApplyOfficeKey").Add_Click({
    `$key = `$window.FindName("txtOfficeKey").Text
    if (-not `$key) { Write-ToolLog "Informe a chave do Office." "WARN"; return }
    Start-AsyncAction { Install-OfficeProductKey -ProductKey `$using:key }
})

`$window.FindName("btnSetKms").Add_Click({
    `$kmsHost = `$window.FindName("txtKmsHost").Text
    if (-not `$kmsHost) { Write-ToolLog "Informe o host KMS." "WARN"; return }
    Start-AsyncAction { Set-EnterpriseKmsServer -KmsHost `$using:kmsHost }
})

`$window.FindName("btnClearLogs").Add_Click({ `$global:txtLogControl.Text = "" })

Write-ToolLog "WinRepair & Tweaks Utility carregado com sucesso!" "SUCCESS"
`$window.ShowDialog() | Out-Null
"@

[void]$sb.AppendLine($runtimeScript)

# Salvar com UTF-8 BOM para garantir compatibilidade total no irm | iex do PowerShell 5.1 e 7
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($destination, $sb.ToString(), $utf8Bom)

Write-Host "[+] Compilação concluída com sucesso: $destination" -ForegroundColor Green
