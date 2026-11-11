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
