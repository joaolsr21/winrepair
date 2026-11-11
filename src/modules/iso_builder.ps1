# ==============================================================================
# Módulo Avançado: Criador e Customizador de Imagens ISO (Windows 10 / 11)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms

function Select-IsoFileDialog {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Arquivos de Imagem ISO (*.iso)|*.iso|Todos os Arquivos (*.*)|*.*"
    $dialog.Title = "Selecione a ISO Oficial do Windows 10 ou 11"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Select-OutputFolderDialog {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Selecione a pasta onde a nova ISO modificada será salva"
    $dialog.ShowNewFolderButton = $true
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Inspect-IsoEditions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IsoPath
    )

    if (-not (Test-Path $IsoPath)) {
        Write-ToolLog "Arquivo ISO não encontrado: $IsoPath" "ERROR"
        return $null
    }

    Write-ToolLog "Montando ISO temporariamente para ler edições disponíveis..." "INFO"
    try {
        $mounted = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
        $driveLetter = ($mounted | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            # Tenta obter pelo drive letter via CimInstance se Get-Volume atrasar
            Start-Sleep -Seconds 1
            $driveLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume).DriveLetter
        }

        $drivePath = "${driveLetter}:\"
        Write-ToolLog "ISO montada na unidade ${drivePath}" "INFO"

        $wimPath = Join-Path $drivePath "sources\install.wim"
        if (-not (Test-Path $wimPath)) {
            $wimPath = Join-Path $drivePath "sources\install.esd"
        }

        if (-not (Test-Path $wimPath)) {
            Write-ToolLog "Não foi possível localizar install.wim ou install.esd na ISO." "ERROR"
            Dismount-DiskImage -ImagePath $IsoPath | Out-Null
            return $null
        }

        $images = Get-WindowsImage -ImagePath $wimPath
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null

        Write-ToolLog "Edições detectadas na imagem:" "SUCCESS"
        foreach ($img in $images) {
            Write-ToolLog "  -> [Índice $($img.ImageIndex)]: $($img.ImageName)" "INFO"
        }

        return $images
    } catch {
        Write-ToolLog "Falha ao inspecionar a ISO: $_" "ERROR"
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        return $null
    }
}

function Generate-AutoUnattendXml {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        [bool]$BypassOobePrompts = $true,
        [bool]$AllowLocalAccount = $true
    )

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
"@

    [System.IO.File]::WriteAllText($DestinationPath, $xml, [System.Text.Encoding]::UTF8)
    Write-ToolLog "Arquivo autounattend.xml gerado em: $DestinationPath" "SUCCESS"
}

function Build-CustomOptimizedIsoPipeline {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceIsoPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputIsoDir,

        [string]$OutputIsoName = "Windows_Custom_Otimizado.iso",
        [int]$EditionIndex = 1,
        
        [bool]$BypassHardwareChecks = $true,
        [bool]$BypassMicrosoftAccount = $true,
        [bool]$DisableBitLocker = $true,
        [bool]$RemoveBloatware = $true,
        [bool]$InjectUnattendXml = $true
    )

    Write-ToolLog "=== INICIANDO CRIAÇÃO DE ISO MODIFICADA E OTIMIZADA ===" "INFO"
    $workDir = "C:\ISO_Work"
    $extractedDir = Join-Path $workDir "extracted"
    $mountDir = Join-Path $workDir "mount"

    try {
        # 1. Preparar pastas de trabalho
        if (Test-Path $workDir) {
            Write-ToolLog "Limpando diretório de trabalho anterior ($workDir)..." "INFO"
            Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
            Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $extractedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

        # 2. Montar ISO e copiar arquivos
        Write-ToolLog "Montando ISO de origem..." "INFO"
        $diskImg = Mount-DiskImage -ImagePath $SourceIsoPath -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 1
        $driveLetter = ($diskImg | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            $driveLetter = (Get-DiskImage -ImagePath $SourceIsoPath | Get-Volume).DriveLetter
        }
        $driveRoot = "${driveLetter}:\"

        Write-ToolLog "Copiando arquivos da ISO para o diretório de trabalho (pode levar 1-3 min)..." "INFO"
        Copy-Item -Path "${driveRoot}*" -Destination $extractedDir -Recurse -Force
        Dismount-DiskImage -ImagePath $SourceIsoPath | Out-Null
        Write-ToolLog "Arquivos copiados com sucesso." "SUCCESS"

        # 3. Localizar WIM ou ESD
        $wimPath = Join-Path $extractedDir "sources\install.wim"
        $esdPath = Join-Path $extractedDir "sources\install.esd"

        if ((-not (Test-Path $wimPath)) -and (Test-Path $esdPath)) {
            Write-ToolLog "Arquivo install.esd detectado. Convertendo índice $EditionIndex para install.wim..." "INFO"
            Export-WindowsImage -SourceImagePath $esdPath -SourceIndex $EditionIndex -DestinationImagePath $wimPath -DestinationName "Windows Custom" -ErrorAction Stop
            Remove-Item -Path $esdPath -Force -ErrorAction SilentlyContinue
            $EditionIndex = 1
        }

        # 4. Montar a imagem WIM
        Write-ToolLog "Montando imagem WIM (Índice $EditionIndex)..." "INFO"
        Mount-WindowsImage -ImagePath $wimPath -Index $EditionIndex -Path $mountDir -ErrorAction Stop

        # 5. Aplicar Debloat AppX se selecionado
        if ($RemoveBloatware) {
            Write-ToolLog "Removendo pacotes AppX provisionados (bloatware) da imagem..." "INFO"
            $bloatPatterns = @(
                "*BingNews*", "*BingWeather*", "*Solitaire*", "*GetHelp*", "*Getstarted*",
                "*People*", "*Todos*", "*PowerAutomate*", "*ZuneMusic*", "*ZuneVideo*",
                "*Clipchamp*", "*XboxGamingOverlay*", "*XboxSpeechToTextOverlay*"
            )
            $provPackages = Get-AppxProvisionedPackage -Path $mountDir
            $removedCount = 0
            foreach ($pkg in $provPackages) {
                foreach ($pattern in $bloatPatterns) {
                    if ($pkg.DisplayName -like $pattern) {
                        Remove-AppxProvisionedPackage -Path $mountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                        $removedCount++
                        break
                    }
                }
            }
            Write-ToolLog "Bloatware removido da imagem: $removedCount pacotes eliminados." "SUCCESS"
        }

        # 6. Injetar ajustes de registro offline
        $offlineSysHive = Join-Path $mountDir "Windows\System32\config\SYSTEM"
        if (Test-Path $offlineSysHive) {
            Write-ToolLog "Carregando registro offline do Windows..." "INFO"
            reg load HKLM\OFFLINE_SYS "$offlineSysHive" | Out-Null

            if ($BypassHardwareChecks) {
                Write-ToolLog "Injetando Bypass de Requisitos Win11 (TPM 2.0, SecureBoot, RAM, CPU)..." "INFO"
                $labConfig = "HKLM\OFFLINE_SYS\Setup\LabConfig"
                if (-not (Test-Path $labConfig)) { New-Item -Path $labConfig -Force | Out-Null }
                Set-ItemProperty -Path $labConfig -Name "BypassTPMCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassSecureBootCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassRAMCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassCPUCheck" -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $labConfig -Name "BypassStorageCheck" -Value 1 -Type DWord -Force
            }

            if ($BypassMicrosoftAccount) {
                Write-ToolLog "Injetando Bypass de Conta Microsoft (BypassNRO - permite criar conta local)..." "INFO"
                $oobeKey = "HKLM\OFFLINE_SYS\Setup\OOBE"
                if (-not (Test-Path $oobeKey)) { New-Item -Path $oobeKey -Force | Out-Null }
                Set-ItemProperty -Path $oobeKey -Name "BypassNRO" -Value 1 -Type DWord -Force
            }

            if ($DisableBitLocker) {
                Write-ToolLog "Desativando criptografia automática do BitLocker no OOBE..." "INFO"
                $bitlockerKey = "HKLM\OFFLINE_SYS\ControlSet001\Control\BitLocker"
                if (-not (Test-Path $bitlockerKey)) { New-Item -Path $bitlockerKey -Force | Out-Null }
                Set-ItemProperty -Path $bitlockerKey -Name "PreventDeviceEncryption" -Value 1 -Type DWord -Force
            }

            [gc]::Collect()
            reg unload HKLM\OFFLINE_SYS | Out-Null
            Write-ToolLog "Registro offline salvo e descarregado." "SUCCESS"
        }

        # 7. Desmontar salvando as alterações
        Write-ToolLog "Desmontando e salvando imagem WIM modificada..." "INFO"
        Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop

        # 8. Injetar autounattend.xml se solicitado
        if ($InjectUnattendXml) {
            $unattendDest = Join-Path $extractedDir "autounattend.xml"
            Generate-AutoUnattendXml -DestinationPath $unattendDest
        }

        # 9. Gerar ISO bootável final
        $finalIsoPath = Join-Path $OutputIsoDir $OutputIsoName
        Write-ToolLog "Gerando ISO inicializável final em: $finalIsoPath..." "INFO"

        # Procurar oscdimg oficial se presente no sistema
        $oscdimg = Get-Command "oscdimg.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
        if (-not $oscdimg) {
            $adkPaths = @(
                "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
                "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
            )
            $oscdimg = $adkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if ($oscdimg) {
            Write-ToolLog "Criando ISO UEFI/BIOS via oscdimg oficial..." "INFO"
            $bootData = "2#p0,e,b`"$extractedDir\boot\etfsboot.com`"#pEF,e,b`"$extractedDir\efi\microsoft\boot\efisys.bin`""
            & "$oscdimg" -m -o -u2 -udfver102 -bootdata:$bootData "$extractedDir" "$finalIsoPath" | Out-Null
            Write-ToolLog "ISO customizada gerada com sucesso via oscdimg: $finalIsoPath" "SUCCESS"
        } else {
            Write-ToolLog "A pasta preparada para a ISO está pronta em: $extractedDir" "SUCCESS"
            Write-ToolLog "Instale o Windows ADK (oscdimg) ou use o Rufus apontando para essa pasta para gravar no pendrive direto." "INFO"
        }

        Write-ToolLog "=== PROCESSO DE CUSTOMIZAÇÃO CONCLUÍDO COM SUCESSO! ===" "SUCCESS"
    } catch {
        Write-ToolLog "Erro durante o pipeline da ISO: $_" "ERROR"
        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
    }
}
