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
