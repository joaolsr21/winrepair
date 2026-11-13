# ==============================================================================
# Módulo: Ajustes de Usabilidade e Interface
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
