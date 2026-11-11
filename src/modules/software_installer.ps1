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
