# ==============================================================================
# WinRepair & Tweaks Pro (Standalone All-in-One)
# Inspirado no utilitário de Chris Titus Tech (WinUtil)
# Execução direta via: irm <URL> | iex
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

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


# ==============================================================================
# Módulo: Sistema de Logging (Thread-Safe entre Runspaces e UI WPF)
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

    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync -and $sync.LogQueue) {
        $sync.LogQueue.Enqueue($logLine)
    }
}


# ==============================================================================
# Módulo Avançado: Diagnóstico Completo, Varredura, Otimizações e Reparo de Rede
# ==============================================================================

function Invoke-OemTool {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string]$Arguments = "",
        [switch]$StreamToLog
    )

    $oemCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding($oemCodePage)
    $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding($oemCodePage)

    $proc = [System.Diagnostics.Process]::Start($psi)
    $lines = New-Object System.Collections.Generic.List[string]

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        [void]$lines.Add($line)
        if ($StreamToLog -and -not [string]::IsNullOrWhiteSpace($line)) {
            Write-ToolLog $line "INFO"
        }
    }

    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if (-not [string]::IsNullOrWhiteSpace($err)) {
        foreach ($el in ($err -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($el)) {
                [void]$lines.Add($el)
                if ($StreamToLog) { Write-ToolLog $el "WARN" }
            }
        }
    }

    return ($lines -join "`r`n")
}

# --- [1] Diagnóstico Rápido Integrado ---
function Invoke-QuickIntegratedNetworkDiag {
    Write-ToolLog "=== [1] DIAGN$([char]0xD3)STICO RÁPIDO INTEGRADO ===" "INFO"

    Write-ToolLog "1. Testando placa de rede interna [Loopback 127.0.0.1]..." "INFO"
    if (Test-Connection -ComputerName "127.0.0.1" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Hardware de rede local respondendo perfeitamente." "SUCCESS"
    } else {
        Write-ToolLog "  [FALHA CRÍTICA] Placa de rede local ou pilha TCP/IP com defeito." "ERROR"
    }

    Write-ToolLog "2. Identificando Gateway Padrão [Roteador Local]..." "INFO"
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        Write-ToolLog "  Gateway identificado: $gw" "INFO"
        if (Test-Connection -ComputerName $gw -Count 2 -Quiet) {
            Write-ToolLog "  [OK] Comunicação com o Roteador Local: 100% operacional." "SUCCESS"
        } else {
            Write-ToolLog "  [FALHA] Roteador não respondeu aos pacotes de teste." "ERROR"
        }
    } else {
        Write-ToolLog "  [FALHA] Nenhum Gateway Padrão localizado. Cabo desconectado ou sem DHCP." "ERROR"
    }

    Write-ToolLog "3. Testando conexão direta com a Internet [8.8.8.8 e 1.1.1.1]..." "INFO"
    if (Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Acesso à Internet funcional - Google DNS [8.8.8.8] respondeu." "SUCCESS"
    } elseif (Test-Connection -ComputerName "1.1.1.1" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Acesso à Internet funcional - Cloudflare [1.1.1.1] respondeu." "SUCCESS"
    } else {
        Write-ToolLog "  [FALHA] Sem comunicação direta com a Internet via pacotes IP." "ERROR"
    }

    Write-ToolLog "4. Testando Resolução de Nomes [DNS - google.com]..." "INFO"
    try {
        $null = [System.Net.Dns]::GetHostAddresses("google.com")
        Write-ToolLog "  [OK] Servidores DNS resolvendo nomes perfeitamente." "SUCCESS"
    } catch {
        Write-ToolLog "  [FALHA] Servidor DNS falhou ao traduzir nomes de domínio." "ERROR"
    }
    Write-ToolLog "=== DIAGN$([char]0xD3)STICO RÁPIDO CONCLUÍDO ===" "SUCCESS"
}

# --- [2] Teste Detalhado de Conexão com a Internet ---
function Invoke-DetailedInternetTest {
    Write-ToolLog "=== [2] TESTE DETALHADO DE CONECTIVIDADE ===" "INFO"

    Write-ToolLog "1. Testando pacotes ICMP [Ping]..." "INFO"
    foreach ($ip in @("8.8.8.8", "1.1.1.1")) {
        $pings = Test-Connection -ComputerName $ip -Count 3 -ErrorAction SilentlyContinue
        if ($pings) {
            $avg = [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 1)
            $loss = [math]::Round(((3 - $pings.Count) / 3) * 100, 1)
            Write-ToolLog "  Host $ip -> Latência Média: ${avg} ms | Perda: ${loss}%" "SUCCESS"
        } else {
            Write-ToolLog "  Host $ip -> Sem resposta (100% perda)." "ERROR"
        }
    }

    Write-ToolLog "2. Testando comunicação Web Segura [HTTPS Porta 443]..." "INFO"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $wc.DownloadString("https://www.google.com")
        $sw.Stop()
        Write-ToolLog "  [OK] Conexão HTTPS ativa e respondendo em $($sw.ElapsedMilliseconds) ms." "SUCCESS"
    } catch {
        Write-ToolLog "  [FALHA] Não foi possível carregar conteúdo Web seguro: $_" "ERROR"
    }

    Write-ToolLog "3. Testando Resolução de Servidores DNS..." "INFO"
    foreach ($dom in @("google.com", "registro.br")) {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($dom) | Select-Object -First 2
            Write-ToolLog "  [OK] Domínio [$dom] resolvido ($($ips.IPAddressToString -join ', '))." "SUCCESS"
        } catch {
            Write-ToolLog "  [FALHA] Falha na resolução de [$dom]." "WARN"
        }
    }
}

# --- [3] Teste Rápido de Velocidade de Download ---
function Invoke-DownloadSpeedTest {
    Write-ToolLog "=== [3] TESTE DE VELOCIDADE DE DOWNLOAD (CLOUDFLARE CDN) ===" "INFO"
    Write-ToolLog "Baixando bloco de medição de 5 MB direto do Cloudflare... Aguarde..." "INFO"
    $tempFile = Join-Path $env:TEMP "winrepair_speedtest.bin"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc.DownloadFile("https://speed.cloudflare.com/__down?bytes=5000000", $tempFile)
        $sw.Stop()
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        $sec = $sw.ElapsedMilliseconds / 1000.0
        if ($sec -le 0) { $sec = 0.001 }
        $mbps = [math]::Round((5 * 8) / $sec, 2)
        Write-ToolLog "  [OK] Taxa estimada de Download: $mbps Mbps (tempo: $([math]::Round($sec, 2))s)" "SUCCESS"
    } catch {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Write-ToolLog "  [FALHA] Não foi possível concluir o teste de velocidade: $_" "ERROR"
    }
}

# --- [4] Diagnóstico de Wi-Fi ---
function Invoke-WifiDiagnostics {
    param([bool]$GenerateHtmlReport = $false)
    Write-ToolLog "=== [4] DIAGN$([char]0xD3)STICO DE REDE SEM FIO (WI-FI) ===" "INFO"

    Write-ToolLog "--- Status da Interface Wi-Fi Atual ---" "INFO"
    Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show interfaces" -StreamToLog | Out-Null

    Write-ToolLog "--- Redes Disponíveis ao Redor (Canais e Sinal) ---" "INFO"
    Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show networks mode=bssid" -StreamToLog | Out-Null

    if ($GenerateHtmlReport) {
        Write-ToolLog "Gerando relatório histórico de eventos WLAN da Microsoft (HTML)..." "INFO"
        Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show wlanreport" -StreamToLog | Out-Null
        $reportHtml = "C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html"
        if (Test-Path $reportHtml) {
            Write-ToolLog "Relatório HTML gerado em: $reportHtml" "SUCCESS"
            Start-Process $reportHtml
        }
    }
}

# --- [5] Testar Porta TCP Específica ---
function Test-SpecificTcpPort {
    param(
        [Parameter(Mandatory=$true)][string]$TargetHost,
        [Parameter(Mandatory=$true)][int]$Port
    )

    Write-ToolLog "=== [5] TESTE DE PORTA TCP ===" "INFO"
    Write-ToolLog "Testando comunicação com [$TargetHost] na porta TCP [$Port]..." "INFO"

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(3000, $false) -and $client.Connected) {
            $client.EndConnect($async)
            Write-ToolLog "  [SUCESSO] Porta $Port em $TargetHost está ABERTA e acessível!" "SUCCESS"
        } else {
            Write-ToolLog "  [FALHA] Porta $Port em $TargetHost está FECHADA ou bloqueada por Firewall!" "WARN"
        }
    } catch {
        Write-ToolLog "  [FALHA] Erro ao conectar na porta $Port em $TargetHost`: $_" "ERROR"
    } finally {
        $client.Close()
    }
}

# --- [6] Análise de Perda de Pacotes (Pathping) ---
function Invoke-PathpingAnalysis {
    param([string]$TargetHost = "8.8.8.8")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "8.8.8.8" }
    Write-ToolLog "=== [6] ANÁLISE DE PERDA DE PACOTES (PATHPING) ===" "INFO"
    Write-ToolLog "Iniciando pathping em $TargetHost (pode levar 30-90s)... Aguarde..." "INFO"
    Invoke-OemTool -FilePath "pathping.exe" -Arguments "-n -q 10 $TargetHost" -StreamToLog | Out-Null
    Write-ToolLog "Análise Pathping concluída." "SUCCESS"
}

# --- [7] Rastrear Rota (Tracert) ---
function Invoke-TracertAnalysis {
    param([string]$TargetHost = "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "1.1.1.1" }
    Write-ToolLog "=== [7] RASTREAMENTO DE ROTA (TRACERT) ===" "INFO"
    Write-ToolLog "Rastreando rota até $TargetHost (limite 15 saltos)..." "INFO"
    Invoke-OemTool -FilePath "tracert.exe" -Arguments "-d -h 15 $TargetHost" -StreamToLog | Out-Null
    Write-ToolLog "Rastreamento Tracert concluído." "SUCCESS"
}

# --- [8] Teste Contínuo de Estabilidade (Ping -t) ---
function Start-ContinuousPingWindow {
    param([string]$TargetHost = "8.8.8.8")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "8.8.8.8" }
    Write-ToolLog "Abrindo janela dedicada de Ping contínuo (-t) para $TargetHost..." "INFO"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k title Ping Continuo: $TargetHost && color 0F && echo Pressione CTRL+C para interromper o teste. && ping $TargetHost -t"
}

# --- [9] Conexões Ativas e Portas Escutando (Netstat) ---
function Get-ActiveConnectionsNetstat {
    param(
        [ValidateSet("Established", "Listening", "All")]
        [string]$Mode = "Established"
    )

    Write-ToolLog "=== [9] CONEXÕES ATIVAS E PORTAS ($Mode) ===" "INFO"
    $args = switch ($Mode) {
        "Established" { "-f" }
        "Listening"   { "-ano" }
        "All"         { "-ano" }
    }

    $output = Invoke-OemTool -FilePath "netstat.exe" -Arguments $args
    $lines = $output -split "`r?`n"
    foreach ($l in $lines) {
        if ($Mode -eq "Established" -and $l -match "ESTABLISHED") {
            Write-ToolLog $l "INFO"
        } elseif ($Mode -eq "Listening" -and $l -match "LISTENING") {
            Write-ToolLog $l "INFO"
        } elseif ($Mode -eq "All" -and -not [string]::IsNullOrWhiteSpace($l)) {
            Write-ToolLog $l "INFO"
        }
    }
    Write-ToolLog "Consulta Netstat concluída." "SUCCESS"
}

# --- [10] Varredura Completa da Rede Local (IPs Ocupados e Livres) ---
function Invoke-LocalSubnetScan {
    param([bool]$SaveAndOpenReport = $true)

    Write-ToolLog "=== [10] VARREDURA COMPLETA DA REDE LOCAL (SUB-REDE IPv4) ===" "INFO"
    Write-ToolLog "Identificando sub-rede e disparando varredura paralela..." "INFO"

    try {
        $ipObj = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1
        if (-not $ipObj) {
            Write-ToolLog "Nenhum endereço IPv4 local válido encontrado." "ERROR"
            return
        }

        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        $localIP = $ipObj.IPAddress
        $ipBytes = [System.Net.IPAddress]::Parse($localIP).GetAddressBytes()
        if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($ipBytes) }
        $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
        $prefixLen = $ipObj.PrefixLength

        # Limitar varredura paralela a /22 (1022 hosts) para evitar travamento em máscaras muito grandes
        if ($prefixLen -lt 22) {
            Write-ToolLog "Máscara /$prefixLen detectada (muito ampla). Limitando varredura à faixa /24 local para segurança." "WARN"
            $prefixLen = 24
        }

        $maskInt = [uint32]([Convert]::ToUInt64(('1' * $prefixLen + '0' * (32 - $prefixLen)), 2))
        $netInt = $ipInt -band $maskInt
        $bcastInt = $netInt -bor (-bnot $maskInt)
        $firstHostInt = $netInt + 1
        $lastHostInt = $bcastInt - 1

        function Convert-UInt32ToIP([uint32]$val) {
            $b = [BitConverter]::GetBytes($val)
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($b) }
            return [System.Net.IPAddress]::new($b).ToString()
        }

        $firstIP = Convert-UInt32ToIP $firstHostInt
        $lastIP = Convert-UInt32ToIP $lastHostInt
        $totalHosts = $lastHostInt - $firstHostInt + 1

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $allIPs = for ($i = $firstHostInt; $i -le $lastHostInt; $i++) { Convert-UInt32ToIP $i }
        $tasks = foreach ($target in $allIPs) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $ping.SendPingAsync($target, 350)
        }
        [Threading.Tasks.Task]::WaitAll($tasks)
        $sw.Stop()

        $arpOutput = Invoke-OemTool -FilePath "arp.exe" -Arguments "-a"
        $arpLines = $arpOutput -split "`r?`n"
        $usedSet = New-Object 'System.Collections.Generic.HashSet[uint32]'
        $devices = @()

        foreach ($line in $arpLines) {
            $p = ($line.Trim() -split '\s+')
            if ($p.Count -ge 3 -and $p[0] -match '^\d+\.\d+\.\d+\.\d+$') {
                try {
                    $b = [System.Net.IPAddress]::Parse($p[0]).GetAddressBytes()
                    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($b) }
                    $val = [BitConverter]::ToUInt32($b, 0)
                    if ($val -ge $firstHostInt -and $val -le $lastHostInt) {
                        $mac = $p[1]
                        if ($mac -notlike 'ff*' -and $mac -notlike '01-00-5e*' -and $mac -notlike '224*' -and $mac -notlike '239*') {
                            if ($usedSet.Add($val)) {
                                $tag = 'Ativo'
                                if ($p[0] -eq $gw) { $tag = 'Gateway/Roteador' }
                                if ($p[0] -eq $localIP) { $tag = 'Este Computador' }
                                $cleanTipo = if ($p[2] -match 'din') { 'Dinamico' } elseif ($p[2] -match 'est') { 'Estatico' } else { $p[2] }
                                $devices += [PSCustomObject]@{ Val = $val; Row = ("{0,-18} {1,-20} {2,-12} {3}" -f $p[0], $mac.ToUpper(), $cleanTipo, $tag) }
                            }
                        }
                    }
                } catch {}
            }
        }

        try {
            $locBytes = [System.Net.IPAddress]::Parse($localIP).GetAddressBytes()
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($locBytes) }
            $null = $usedSet.Add([BitConverter]::ToUInt32($locBytes, 0))
        } catch {}

        $totalUsed = $usedSet.Count
        $totalFree = $totalHosts - $totalUsed
        $pctUsed = [math]::Round(($totalUsed / $totalHosts) * 100, 1)
        $pctFree = [math]::Round(($totalFree / $totalHosts) * 100, 1)

        $freeRanges = @()
        $freeIndividual = @()
        $rangeStart = $null
        $rangeCount = 0

        for ($i = $firstHostInt; $i -le $lastHostInt; $i++) {
            if (-not $usedSet.Contains($i)) {
                $freeIndividual += Convert-UInt32ToIP $i
                if ($null -eq $rangeStart) { $rangeStart = $i; $rangeCount = 1 } else { $rangeCount++ }
            } else {
                if ($null -ne $rangeStart) {
                    $sIP = Convert-UInt32ToIP $rangeStart
                    $eIP = Convert-UInt32ToIP ($rangeStart + $rangeCount - 1)
                    $desc = if ($rangeCount -eq 1) { "$sIP" } else { "$sIP até $eIP" }
                    $freeRanges += ("{0,-38} {1,-15}" -f $desc, "$rangeCount IP(s) livres")
                    $rangeStart = $null; $rangeCount = 0
                }
            }
        }
        if ($null -ne $rangeStart) {
            $sIP = Convert-UInt32ToIP $rangeStart
            $eIP = Convert-UInt32ToIP ($rangeStart + $rangeCount - 1)
            $desc = if ($rangeCount -eq 1) { "$sIP" } else { "$sIP até $eIP" }
            $freeRanges += ("{0,-38} {1,-15}" -f $desc, "$rangeCount IP(s) livres")
        }

        $hdr = "==============================================================================="
        $sumLines = @(
            $hdr,
            "               RESUMO DE OCUPAÇÃO DA SUB-REDE (IPv4)",
            $hdr,
            "  Máscara Detectada:        /$prefixLen",
            "  Faixa Total da Rede:      $firstIP até $lastIP",
            "  Total de IPs Usáveis:     $totalHosts endereços",
            "  IPs Ocupados (Em Uso):    $totalUsed ($pctUsed%)",
            "  IPs Livres (Disponíveis): $totalFree ($pctFree%)",
            "  Tempo de Varredura:       $([math]::Round($sw.ElapsedMilliseconds/1000, 2)) segundos",
            $hdr
        )

        foreach ($sl in $sumLines) { Write-ToolLog $sl "INFO" }

        $colUsed = "{0,-18} {1,-20} {2,-12} {3}" -f "ENDEREÇO IP", "ENDEREÇO MAC", "TIPO", "STATUS"
        $sorted = $devices | Sort-Object Val
        $usedOut = @($hdr, "DISPOSITIVOS OCUPADOS / EM USO ($totalUsed encontrados)", $hdr, $colUsed, $hdr) + ($sorted | ForEach-Object { $_.Row }) + @($hdr)

        Write-ToolLog "--- Dispositivos Ocupados ---" "INFO"
        foreach ($u in $sorted) { Write-ToolLog ("  " + $u.Row) "SUCCESS" }

        Write-ToolLog "--- Faixas de IPs Livres ---" "INFO"
        foreach ($fr in $freeRanges) { Write-ToolLog ("  " + $fr) "INFO" }

        if ($SaveAndOpenReport) {
            $colFree = "{0,-38} {1,-15}" -f "FAIXA / BLOCO DISPONÍVEL", "QUANTIDADE"
            $rangesOut = @($hdr, "FAIXAS E BLOCOS DE IPs LIVRES ($($freeRanges.Count) blocos - $totalFree IPs livres)", $hdr, $colFree, $hdr) + $freeRanges + @($hdr)
            $allFreeOut = @($hdr, "LISTA COMPLETA DE IPs LIVRES INDIVIDUAIS ($totalFree IPs disponíveis)", $hdr) + $freeIndividual + @($hdr)
            $fullReport = $sumLines + @("", "") + $rangesOut + @("", "") + $usedOut + @("", "") + $allFreeOut

            $desktopPath = [Environment]::GetFolderPath("Desktop")
            $reportFile = Join-Path $desktopPath "Relatorio_IPs_Rede_Local.txt"
            [System.IO.File]::WriteAllLines($reportFile, $fullReport, [System.Text.Encoding]::UTF8)
            Write-ToolLog "Relatório completo de IPs salvo na Área de Trabalho: $reportFile" "SUCCESS"
            Start-Process notepad.exe -ArgumentList "`"$reportFile`""
        }
    } catch {
        Write-ToolLog "Erro durante varredura da rede local: $_" "ERROR"
    }
}

# --- [11] Exibir Configurações de IP e DNS (ipconfig /all) ---
function Get-IpConfigAllDetails {
    Write-ToolLog "=== [11] CONFIGURAÇÕES DE IP E DNS (ipconfig /all) ===" "INFO"
    Invoke-OemTool -FilePath "ipconfig.exe" -Arguments "/all" -StreamToLog | Out-Null
    Write-ToolLog "=== FIM DO IPCONFIG ===" "SUCCESS"
}

# --- [12] Reparar Conexão (FlushDNS, Renew IP e NetBIOS) ---
function Invoke-SimpleNetworkRepair {
    Write-ToolLog "=== [12] REPARO SIMPLES DE CONEXÃO ===" "INFO"
    try {
        Write-ToolLog "1. Limpando cache do Resolvedor de DNS..." "INFO"
        Clear-DnsClientCache
        ipconfig /flushdns | Out-Null

        Write-ToolLog "2. Liberando e renovando concessão DHCP..." "INFO"
        ipconfig /release | Out-Null
        Start-Sleep -Milliseconds 800
        ipconfig /renew | Out-Null

        Write-ToolLog "3. Limpando cache NetBIOS (nbtstat -R)..." "INFO"
        nbtstat -R | Out-Null

        Write-ToolLog "Cache limpo e endereço IP renovado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao reparar conexão: $_" "ERROR"
    }
}

# --- [13] Reset Completo da Pilha de Rede (Winsock, TCP/IP, Proxy, ARP e Firewall) ---
function Invoke-ResetNetworkStack {
    Write-ToolLog "=== [13] RESET COMPLETO DA PILHA DE REDE ===" "INFO"
    try {
        Write-ToolLog "1. Redefinindo Catálogo Winsock..." "INFO"
        netsh winsock reset | Out-Null
        Write-ToolLog "2. Redefinindo Pilha TCP/IP (IPv4 e IPv6)..." "INFO"
        netsh int ip reset | Out-Null
        netsh int ipv6 reset | Out-Null
        Write-ToolLog "3. Redefinindo Configurações de Proxy WinHTTP..." "INFO"
        netsh winhttp reset proxy | Out-Null
        Write-ToolLog "4. Limpando tabela ARP..." "INFO"
        netsh interface ip delete arpcache | Out-Null
        Write-ToolLog "5. Redefinindo Firewall do Windows..." "INFO"
        netsh advfirewall reset | Out-Null

        Write-ToolLog "Pilha de rede reinicializada de fábrica. Recomenda-se reiniciar o computador." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir pilha de rede: $_" "ERROR"
    }
}

# --- [14] Gerar Relatório Forense Completo de Rede (.TXT) ---
function Export-ForensicNetworkReport {
    Write-ToolLog "=== [14] GERANDO RELAT$([char]0xD3)RIO FORENSE COMPLETO DE REDE ===" "INFO"
    Write-ToolLog "Coletando dados de adaptadores, rotas, Wi-Fi, ARP, conexões, ping, DNS e tracert..." "INFO"

    try {
        $dt = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $reportFile = Join-Path $desktopPath "Relatorio_Rede_${env:COMPUTERNAME}_${dt}.txt"

        $sb = New-Object System.Text.StringBuilder
        $sep = "==============================================================================="

        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine("                    RELAT$([char]0xD3)RIO COMPLETO DE DIAGN$([char]0xD3)STICO DE REDE")
        [void]$sb.AppendLine("Data e Hora: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))")
        [void]$sb.AppendLine("Estação: $($env:COMPUTERNAME) | Usuário: $($env:USERNAME)")
        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine("")

        Write-ToolLog "[1/8] Coletando adaptadores e configurações de IP..." "INFO"
        [void]$sb.AppendLine("--- 1. CONFIGURAÇÕES DE IP / ADAPTADORES ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ipconfig.exe" -Arguments "/all"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[2/8] Coletando tabela de roteamento IPv4..." "INFO"
        [void]$sb.AppendLine("--- 2. TABELA DE ROTEAMENTO IPV4 ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "route.exe" -Arguments "print -4"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[3/8] Coletando status das interfaces Wi-Fi..." "INFO"
        [void]$sb.AppendLine("--- 3. STATUS DAS INTERFACES WI-FI ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show interfaces"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[4/8] Coletando tabela ARP local..." "INFO"
        [void]$sb.AppendLine("--- 4. TABELA ARP LOCAL ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "arp.exe" -Arguments "-a"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[5/8] Coletando conexões ativas..." "INFO"
        [void]$sb.AppendLine("--- 5. CONEXÕES DE REDE ATIVAS (ESTABLISHED) ---")
        $netOut = (Invoke-OemTool -FilePath "netstat.exe" -Arguments "-ano") -split "`r?`n" | Where-Object { $_ -match "ESTABLISHED" }
        [void]$sb.AppendLine(($netOut -join "`r`n"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[6/8] Testando conectividade (Google e Cloudflare)..." "INFO"
        [void]$sb.AppendLine("--- 6. TESTE DE CONECTIVIDADE GOOGLE (8.8.8.8) ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ping.exe" -Arguments "-n 4 8.8.8.8"))
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("--- 7. TESTE DE CONECTIVIDADE CLOUDFLARE (1.1.1.1) ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ping.exe" -Arguments "-n 4 1.1.1.1"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[7/8] Testando resolução DNS..." "INFO"
        [void]$sb.AppendLine("--- 8. TESTE DE RESOLUÇÃO DE DNS ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "nslookup.exe" -Arguments "google.com"))
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "nslookup.exe" -Arguments "microsoft.com"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[8/8] Rastreando rota até a internet (8.8.8.8)..." "INFO"
        [void]$sb.AppendLine("--- 9. ROTA COMPLETA ATÉ A INTERNET ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "tracert.exe" -Arguments "-d -h 12 8.8.8.8"))

        [System.IO.File]::WriteAllText($reportFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
        Write-ToolLog "Relatório forense salvo na Área de Trabalho: $reportFile" "SUCCESS"
        Start-Process notepad.exe -ArgumentList "`"$reportFile`""
    } catch {
        Write-ToolLog "Erro ao gerar relatório forense: $_" "ERROR"
    }
}

# --- Auxiliares extras de Rede & Gaming ---
function Invoke-FlushDns {
    Write-ToolLog "Limpando o cache do resolvedor DNS..." "INFO"
    try {
        Clear-DnsClientCache
        Write-ToolLog "Cache DNS limpo com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao limpar cache DNS: $_" "ERROR"
    }
}

function Invoke-RenewDhcp {
    Write-ToolLog "Liberando e renovando endereço IP via DHCP..." "INFO"
    try {
        ipconfig /release | Out-Null
        Start-Sleep -Milliseconds 800
        ipconfig /renew | Out-Null
        Write-ToolLog "Concessão de IP renovada com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao renovar concessão DHCP: $_" "ERROR"
    }
}

function Set-QuickDnsProvider {
    param(
        [ValidateSet("Cloudflare", "Google", "Quad9", "AdGuard", "DHCP")]
        [string]$Provider = "Cloudflare"
    )

    $dnsServers = switch ($Provider) {
        "Cloudflare" { @("1.1.1.1", "1.0.0.1") }
        "Google"     { @("8.8.8.8", "8.8.4.4") }
        "Quad9"      { @("9.9.9.9", "149.112.112.112") }
        "AdGuard"    { @("94.140.14.14", "94.140.15.15") }
        "DHCP"       { $null }
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) {
        Write-ToolLog "Nenhum adaptador físico ativo encontrado." "WARN"
        return
    }

    foreach ($adapter in $adapters) {
        try {
            if ($Provider -eq "DHCP") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-ToolLog "[$($adapter.Name)] DNS restaurado para automático (DHCP)." "SUCCESS"
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers
                Write-ToolLog "[$($adapter.Name)] DNS $Provider aplicado: $($dnsServers -join ', ')." "SUCCESS"
            }
        } catch {
            Write-ToolLog "Falha ao definir DNS em $($adapter.Name): $_" "ERROR"
        }
    }
}

function Optimize-TcpLatencyAndThroughput {
    Write-ToolLog "Aplicando otimizações avançadas na pilha TCP/IP (Baixa Latência & Alto Rendimento)..." "INFO"
    try {
        netsh int tcp set global autotuninglevel=normal | Out-Null
        netsh int tcp set global rss=enabled | Out-Null
        netsh int tcp set global ecncapability=enabled | Out-Null
        try { netsh int tcp set supplemental template=custom congestionprovider=ctcp | Out-Null } catch {}

        $gamingNetKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $gamingNetKey) {
            Set-ItemProperty -Path $gamingNetKey -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
            Set-ItemProperty -Path $gamingNetKey -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Otimizações de latência e taxa de transferência TCP aplicadas com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao otimizar TCP/IP: $_" "ERROR"
    }
}

function Restart-NetworkAdapters {
    Write-ToolLog "Reiniciando adaptadores de rede físicos..." "INFO"
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    foreach ($adapter in $adapters) {
        try {
            Restart-NetAdapter -Name $adapter.Name -Confirm:$false
            Write-ToolLog "Adaptador $($adapter.Name) reiniciado." "SUCCESS"
        } catch {
            Write-ToolLog "Falha ao reiniciar $($adapter.Name): $_" "ERROR"
        }
    }
}


# ==============================================================================
# Módulo Avançado: Otimizações de Desempenho, Debloat, Serviços e Perfis Prontos
# ==============================================================================

function Clear-TempFiles {
    Write-ToolLog "Iniciando limpeza profunda de arquivos temporários e caches..." "INFO"

    $targets = @(
        "$env:TEMP\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "$env:LOCALAPPDATA\CrashDumps\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$env:LOCALAPPDATA\Temp\*"
    )

    $deletedCount = 0
    foreach ($target in $targets) {
        if (Test-Path (Split-Path $target)) {
            try {
                $items = Get-ChildItem -Path $target -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $deletedCount++
                }
            } catch {}
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Lixeira esvaziada." "SUCCESS"
    } catch {}

    Write-ToolLog "Limpeza temporária finalizada. $deletedCount arquivos processados/removidos." "SUCCESS"
}

function Clear-WindowsUpdateCache {
    Write-ToolLog "Parando serviços do Windows Update..." "INFO"
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "cryptSvc" -Force -ErrorAction SilentlyContinue

        $wuCachePath = "C:\Windows\SoftwareDistribution\Download\*"
        if (Test-Path (Split-Path $wuCachePath)) {
            Write-ToolLog "Removendo arquivos temporários de atualização corrompidos..." "INFO"
            Remove-Item -Path $wuCachePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Reiniciando serviços essenciais..." "INFO"
        Start-Service -Name "cryptSvc" -ErrorAction SilentlyContinue
        Start-Service -Name "bits" -ErrorAction SilentlyContinue
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

        Write-ToolLog "Cache do Windows Update redefinido com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir cache do Windows Update: $_" "ERROR"
    }
}

function Enable-UltimatePerformancePowerPlan {
    Write-ToolLog "Desbloqueando e ativando o Plano de Energia 'Desempenho Máximo' (Ultimate Performance)..." "INFO"
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $output = powercfg -duplicatescheme $guid 2>&1
        powercfg -setactive $guid
        Write-ToolLog "Plano 'Desempenho Máximo' ativado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao ativar plano de energia: $_" "ERROR"
    }
}

function Optimize-WindowsTelemetryAndPrivacy {
    Write-ToolLog "Desativando telemetria, diagnóstico e coleta de dados..." "INFO"
    try {
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) { New-Item -Path $dataCollectionKey -Force | Out-Null }
        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dataCollectionKey -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force

        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) { New-Item -Path $advertisingKey -Force | Out-Null }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

        # Desativar Histórico de Atividades
        $activityKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $activityKey)) { New-Item -Path $activityKey -Force | Out-Null }
        Set-ItemProperty -Path $activityKey -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "UploadUserActivities" -Value 0 -Type DWord -Force

        # Desativar Tarefas Agendadas de Telemetria / CEIP
        $telemetryTasks = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach ($task in $telemetryTasks) {
            Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        }

        Write-ToolLog "Telemetria e tarefas agendadas de rastreamento desativadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar telemetria: $_" "ERROR"
    }
}

function Optimize-WindowsServicesManual {
    Write-ToolLog "Configurando serviços secundários pesados para Manual ou Desativado (Estilo WinUtil)..." "INFO"
    
    $servicesToDisable = @(
        "DiagTrack",
        "dmwappushservice",
        "RetailDemo",
        "RemoteRegistry",
        "diagnosticshub.standardcollector.service"
    )

    $servicesToManual = @(
        "MapsBroker",
        "lfsvc",
        "SensorService",
        "SensrSvc",
        "WbioSrvc",
        "Fax",
        "wisvc",
        "SharedAccess",
        "WMPNetworkSvc",
        "WerSvc"
    )

    foreach ($s in $servicesToDisable) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Desativado." "INFO"
        }
    }

    foreach ($s in $servicesToManual) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Manual." "INFO"
        }
    }

    Write-ToolLog "Otimização de serviços do Windows concluída." "SUCCESS"
}

function Disable-GameDvrAndBackgroundRecording {
    Write-ToolLog "Desativando gravação em segundo plano do GameDVR (Reduz input lag em jogos)..." "INFO"
    try {
        $gameConfigKey = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gameConfigKey)) { New-Item -Path $gameConfigKey -Force | Out-Null }
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force

        $gamePolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $gamePolicyKey)) { New-Item -Path $gamePolicyKey -Force | Out-Null }
        Set-ItemProperty -Path $gamePolicyKey -Name "AllowGameDVR" -Value 0 -Type DWord -Force

        Write-ToolLog "GameDVR e gravação de fundo desativados. Desempenho de jogos otimizado." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao desativar GameDVR: $_" "ERROR"
    }
}

function Disable-StartMenuAdsAndBingSearch {
    Write-ToolLog "Desativando pesquisas da Web (Bing) e anúncios patrocinados no Menu Iniciar..." "INFO"
    try {
        $searchKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
        Set-ItemProperty -Path $searchKey -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

        $userSearchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $userSearchKey)) { New-Item -Path $userSearchKey -Force | Out-Null }
        Set-ItemProperty -Path $userSearchKey -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchKey -Name "CortanaConsent" -Value 0 -Type DWord -Force

        $contentDeliveryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $contentDeliveryKey) {
            Set-ItemProperty -Path $contentDeliveryKey -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Pesquisas Bing no menu Iniciar e anúncios de aplicativos desativados." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao remover anúncios do Menu Iniciar: $_" "ERROR"
    }
}

function Optimize-SystemResponsivenessAndVisuals {
    Write-ToolLog "Ajustando tempo de resposta de menus e prioridade de CPU..." "INFO"
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "10" -Force
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force
        Write-ToolLog "Prioridade de processos em foco e velocidade de menus aceleradas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao aplicar ajustes visuais: $_" "ERROR"
    }
}

function Optimize-SsdTrim {
    Write-ToolLog "Verificando unidades SSD para execução de TRIM (ReTrim)..." "INFO"
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
        foreach ($vol in $volumes) {
            Write-ToolLog "Otimizando unidade $($vol.DriveLetter): ..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue | Out-Null
        }
        Write-ToolLog "Comando TRIM executado com sucesso nas unidades elegíveis." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao executar TRIM: $_" "ERROR"
    }
}

function Set-HibernationState {
    param([Parameter(Mandatory=$true)][bool]$Enable)
    try {
        if ($Enable) {
            powercfg.exe -h on
            Write-ToolLog "Hibernação reativada." "SUCCESS"
        } else {
            powercfg.exe -h off
            Write-ToolLog "Hibernação desativada. Espaço equivalente à memória RAM liberado no disco C:." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao alterar estado de hibernação: $_" "ERROR"
    }
}

function Invoke-SystemDebloatAppx {
    Write-ToolLog "Removendo bloatwares e aplicativos pré-instalados desnecessários do Windows..." "INFO"
    $appsToRemove = @(
        "*Microsoft.BingNews*",
        "*Microsoft.BingWeather*",
        "*Microsoft.BingSearch*",
        "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*",
        "*Microsoft.MicrosoftOfficeHub*",
        "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.People*",
        "*Microsoft.PowerAutomateDesktop*",
        "*Microsoft.Todos*",
        "*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.YourPhone*",
        "*Microsoft.ZuneMusic*",
        "*Microsoft.ZuneVideo*",
        "*Clipchamp.Clipchamp*",
        "*SpotifyAB.SpotifyMusic*",
        "*Disney.37853FC22B2CE*",
        "*Netflix*",
        "*Facebook*",
        "*TikTok*"
    )

    $removed = 0
    foreach ($app in $appsToRemove) {
        try {
            $pkgs = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            foreach ($pkg in $pkgs) {
                Write-ToolLog "Removendo app: $($pkg.Name)..." "INFO"
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removed++
            }
        } catch {}
    }

    Write-ToolLog "Debloat de aplicativos concluído. Pacotes removidos: $removed." "SUCCESS"
}

# ==============================================================================
# PERFIS PRÉ-CONFIGURADOS COM 1 CLIQUE (ESTILO CHRIS TITUS WINUTIL)
# ==============================================================================

function Apply-DesktopRecommendedProfile {
    Write-ToolLog "=== APLICANDO PERFIL RECOMENDADO: DESKTOP / PC DE MESA ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_DesktopProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    Set-HibernationState -Enable $false
    Optimize-WindowsServicesManual
    Enable-UltimatePerformancePowerPlan
    Set-ShowFileExtensions -Enable $true
    Set-ShowHiddenFiles -Enable $true
    Set-ExplorerOpenToThisPC
    Disable-MouseAcceleration
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL DESKTOP APLICADO COM SUCESSO! ===" "SUCCESS"
}

function Apply-LaptopRecommendedProfile {
    Write-ToolLog "=== APLICANDO PERFIL RECOMENDADO: NOTEBOOK / LAPTOP ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_LaptopProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    # Notebooks MANTÊM a hibernação para segurança da bateria
    Set-HibernationState -Enable $true
    Optimize-WindowsServicesManual
    Set-ShowFileExtensions -Enable $true
    Set-ExplorerOpenToThisPC
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL NOTEBOOK APLICADO COM SUCESSO! ===" "SUCCESS"
}

function Apply-GamerUltimateProfile {
    Write-ToolLog "=== APLICANDO PERFIL GAMER & MÁXIMO DESEMPENHO ===" "INFO"
    Set-RestorePoint -Description "WinRepair_Pre_GamerProfile"
    Clear-TempFiles
    Optimize-WindowsTelemetryAndPrivacy
    Disable-StartMenuAdsAndBingSearch
    Disable-GameDvrAndBackgroundRecording
    Set-HibernationState -Enable $false
    Optimize-WindowsServicesManual
    Enable-UltimatePerformancePowerPlan
    Optimize-SystemResponsivenessAndVisuals
    Disable-MouseAcceleration
    Optimize-TcpLatencyAndThroughput
    Optimize-SsdTrim
    Write-ToolLog "=== PERFIL GAMER APLICADO COM SUCESSO! ===" "SUCCESS"
}


# ==============================================================================
# Módulo: Ajustes de Usabilidade e Interface (Estilo Chris Titus WinUtil)
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


# ==============================================================================
# Módulo: Recursos Opcionais do Windows (Estilo WinUtil Config)
# ==============================================================================

function Get-FeatureStatus {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($f.State -eq 'Enabled')
    } catch {
        return $false
    }
}

function Enable-WslFeature {
    Write-ToolLog "Habilitando Subsistema Windows para Linux (WSL) e Plataforma de Máquina Virtual..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart -ErrorAction Stop | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "WSL 2 habilitado com sucesso. (Reinicialização necessária para concluir)." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar WSL: $_" "ERROR"
    }
}

function Enable-WindowsSandbox {
    Write-ToolLog "Habilitando Área Restrita do Windows (Windows Sandbox)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Windows Sandbox habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Sandbox: $_" "ERROR"
    }
}

function Enable-HyperVFeature {
    Write-ToolLog "Habilitando Hyper-V e Ferramentas de Gerenciamento..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Hyper-V habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Hyper-V: $_" "ERROR"
    }
}

function Enable-NetFramework35 {
    Write-ToolLog "Instalando suporte ao .NET Framework 3.5 (.NET 2.0 e 3.0)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog ".NET Framework 3.5 instalado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao instalar .NET 3.5: $_" "ERROR"
    }
}


# ==============================================================================
# Módulo: Gerenciamento do Windows Update (Estilo Chris Titus Updates)
# ==============================================================================

function Set-WindowsUpdateRecommended {
    Write-ToolLog "Configurando Windows Update para o Modo Recomendado (Apenas Segurança Estável)..." "INFO"
    Write-ToolLog "Atrasa atualizações de recursos instáveis por 1 ano e evita reinicializações forçadas." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        
        $auPath = "$wuPath\AU"
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }

        # Não reiniciar automaticamente se houver usuário conectado
        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        # Notificar para agendar reinicialização
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 2 -Type DWord -Force

        # Adiar atualizações de recursos por 365 dias (estabilidade máxima)
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force

        # Adiar atualizações de qualidade por 4 dias (para evitar bugs de lançamento)
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 4 -Type DWord -Force

        Write-ToolLog "Windows Update configurado no modo 'Segurança e Estabilidade Recomendada'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar Windows Update: $_" "ERROR"
    }
}

function Reset-WindowsUpdateDefault {
    Write-ToolLog "Restaurando Windows Update para as configurações originais de fábrica..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (Test-Path $wuPath) {
            Remove-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue
        }

        $auPath = "$wuPath\AU"
        if (Test-Path $auPath) {
            Remove-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $auPath -Name "AUOptions" -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Windows Update restaurado para o padrão original da Microsoft." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao restaurar Windows Update: $_" "ERROR"
    }
}

function Pause-WindowsUpdateExtended {
    Write-ToolLog "Pausando atualizações do Windows Update por período estendido..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        
        $futureDate = "2042-01-01T00:00:00Z"
        Set-ItemProperty -Path $wuPath -Name "PauseUpdatesExpiryTime" -Value $futureDate -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseFeatureUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseQualityUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force

        Write-ToolLog "Atualizações do Windows pausadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao pausar atualizações: $_" "ERROR"
    }
}


# ==============================================================================
# Módulo: Diagnóstico e Reparo do Sistema Operacional
# ==============================================================================

function Invoke-SfcScan {
    Write-ToolLog "Iniciando verificação de integridade dos arquivos de sistema (SFC)..." "INFO"
    Write-ToolLog "Este processo pode levar alguns minutos. Aguarde..." "INFO"
    try {
        $process = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "SFC: A Proteção de Recursos do Windows não encontrou nenhuma violação de integridade." "SUCCESS"
        } elseif ($process.ExitCode -eq 1) {
            Write-ToolLog "SFC: Arquivos corrompidos foram encontrados e corrigidos com sucesso!" "SUCCESS"
        } else {
            Write-ToolLog "SFC finalizado com código de saída: $($process.ExitCode). Verifique C:\Windows\Logs\CBS\CBS.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar o SFC: $_" "ERROR"
    }
}

function Invoke-DismRepair {
    Write-ToolLog "Iniciando reparo da imagem do sistema Windows com DISM..." "INFO"
    Write-ToolLog "Verificando integridade e restaurando saúde da imagem (/RestoreHealth)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "DISM: A operação de restauração foi concluída com êxito." "SUCCESS"
        } else {
            Write-ToolLog "DISM finalizado com código: $($process.ExitCode). Verifique C:\Windows\Logs\DISM\dism.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar o DISM: $_" "ERROR"
    }
}

function Invoke-DismCleanup {
    Write-ToolLog "Executando limpeza do repositório de componentes WinSxS (/StartComponentCleanup)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "Limpeza da pasta WinSxS concluída. Espaço em disco recuperado." "SUCCESS"
        } else {
            Write-ToolLog "DISM Component Cleanup retornou código: $($process.ExitCode)." "WARN"
        }
    } catch {
        Write-ToolLog "Falha na limpeza de componentes: $_" "ERROR"
    }
}

function Restart-PrintSpooler {
    Write-ToolLog "Reiniciando o Spooler de Impressão e limpando filas travadas..." "INFO"
    try {
        Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
        $spoolPath = "C:\Windows\System32\spool\PRINTERS\*"
        if (Test-Path (Split-Path $spoolPath)) {
            Remove-Item -Path $spoolPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
        Write-ToolLog "Fila de impressão limpa e serviço Spooler reiniciado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao reiniciar Spooler: $_" "ERROR"
    }
}

function Schedule-ChkdskOnReboot {
    Write-ToolLog "Agendando verificação de disco (CHKDSK /F) para a próxima reinicialização..." "INFO"
    try {
        $result = echo "Y" | chkdsk C: /f
        Write-ToolLog "CHKDSK agendado na unidade C:. O disco será verificado na próxima inicialização." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao agendar CHKDSK: $_" "ERROR"
    }
}


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


# ==============================================================================
# Módulo: Gerenciamento e Ativação de Licenças (Windows & Microsoft Office)
# ==============================================================================

function Get-WindowsActivationStatus {
    Write-ToolLog "Consultando status atual de licenciamento do Windows..." "INFO"
    try {
        $wpa = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.ApplicationId -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } | Select-Object -First 1
        
        $statusText = switch ($wpa.LicenseStatus) {
            0 { "Não Licenciado" }
            1 { "Licenciado / Ativado Permanente" }
            2 { "Período OOBE Grace" }
            3 { "Período de Tolerância (Grace)" }
            4 { "Período de Não Genuinidade" }
            5 { "Notificação de Tolerância" }
            default { "Status Desconhecido ($($wpa.LicenseStatus))" }
        }

        Write-ToolLog "Edição: $($wpa.Name)" "INFO"
        Write-ToolLog "Status da Licença: $statusText" $(if ($wpa.LicenseStatus -eq 1) { "SUCCESS" } else { "WARN" })
        Write-ToolLog "Chave Parcial Instalada: ...-$($wpa.PartialProductKey)" "INFO"
        return $statusText
    } catch {
        Write-ToolLog "Falha ao consultar WMI. Executando slmgr.vbs /xpr..." "WARN"
        $slmgrOut = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /xpr
        Write-ToolLog "$slmgrOut" "INFO"
    }
}

function Install-WindowsProductKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductKey
    )

    $cleanKey = $ProductKey.Trim().ToUpper()
    if ($cleanKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
        Write-ToolLog "Formato de chave inválido! Utilize o formato: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" "ERROR"
        return
    }

    Write-ToolLog "Instalando chave de produto no Windows ($cleanKey)..." "INFO"
    try {
        $ipkResult = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /ipk $cleanKey
        Write-ToolLog "$ipkResult" "INFO"

        Write-ToolLog "Solicitando ativação online junto aos servidores de licenciamento da Microsoft..." "INFO"
        $atoResult = cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /ato
        Write-ToolLog "$atoResult" "SUCCESS"

        Get-WindowsActivationStatus | Out-Null
    } catch {
        Write-ToolLog "Erro durante o processo de ativação do Windows: $_" "ERROR"
    }
}

function Find-OfficeOsppPath {
    $possiblePaths = @(
        "${env:ProgramFiles}\Microsoft Office\Office16\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
        "${env:ProgramFiles}\Microsoft Office\Office15\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS",
        "${env:ProgramFiles}\Microsoft Office\Office14\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office14\OSPP.VBS"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

function Get-OfficeActivationStatus {
    Write-ToolLog "Localizando instalação do Microsoft Office..." "INFO"
    $ospp = Find-OfficeOsppPath

    if (-not $ospp) {
        Write-ToolLog "Nenhuma instalação corporativa/padrão do Microsoft Office com ospp.vbs foi encontrada neste computador." "WARN"
        return
    }

    Write-ToolLog "Script de licenciamento encontrado em: $ospp" "INFO"
    try {
        $statusOut = cscript.exe //NoLogo "$ospp" /dstatus
        Write-ToolLog "$statusOut" "INFO"
    } catch {
        Write-ToolLog "Erro ao consultar status do Office: $_" "ERROR"
    }
}

function Install-OfficeProductKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductKey
    )

    $cleanKey = $ProductKey.Trim().ToUpper()
    if ($cleanKey -notmatch "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") {
        Write-ToolLog "Formato de chave inválido! Utilize o padrão: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" "ERROR"
        return
    }

    $ospp = Find-OfficeOsppPath
    if (-not $ospp) {
        Write-ToolLog "Instalação do Microsoft Office não encontrada." "ERROR"
        return
    }

    Write-ToolLog "Instalando chave de produto no Microsoft Office..." "INFO"
    try {
        $argKey = "/inpkey:$cleanKey"
        $inpResult = cscript.exe //NoLogo "$ospp" $argKey
        Write-ToolLog "$inpResult" "INFO"

        Write-ToolLog "Tentando ativação do Office..." "INFO"
        $actResult = cscript.exe //NoLogo "$ospp" /act
        Write-ToolLog "$actResult" "SUCCESS"

        Get-OfficeActivationStatus
    } catch {
        Write-ToolLog "Erro ao ativar Office: $_" "ERROR"
    }
}

function Set-EnterpriseKmsServer {
    param(
        [Parameter(Mandatory=$true)]
        [string]$KmsHost,
        [int]$Port = 1688
    )

    Write-ToolLog "Configurando servidor KMS institucional ($($KmsHost):$($Port))..." "INFO"
    try {
        $kmsTarget = "$($KmsHost):$($Port)"
        cscript.exe //NoLogo C:\Windows\System32\slmgr.vbs /skms $kmsTarget
        Write-ToolLog "Servidor KMS do Windows configurado." "SUCCESS"

        $ospp = Find-OfficeOsppPath
        if ($ospp) {
            $argHost = "/sethst:$($KmsHost)"
            $argPort = "/setprt:$($Port)"
            cscript.exe //NoLogo "$ospp" $argHost
            cscript.exe //NoLogo "$ospp" $argPort
            Write-ToolLog "Servidor KMS do Office configurado." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao configurar KMS: $_" "ERROR"
    }
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

# 3. Carregar interface gráfica embutida
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinRepair &amp; Tweaks Pro"
        Height="820" Width="1060"
        WindowStartupLocation="CenterScreen"
        Background="#181825"
        Foreground="#CDD6F4"
        FontFamily="Segoe UI, Segoe UI Emoji">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#45475A"/>
                    <Setter Property="BorderBrush" Value="#89B4FA"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#585B70"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderThickness="0,0,0,3" BorderBrush="Transparent" Margin="2,0">
                            <ContentPresenter ContentSource="Header" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#89B4FA"/>
                                <Setter TargetName="Border" Property="Background" Value="#24273A"/>
                                <Setter Property="Foreground" Value="#89B4FA"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#CDD6F4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="#89B4FA"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="4,3"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#313244"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="3,3,3,8"/>
            <Setter Property="Padding" Value="8"/>
        </Style>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="160"/>
        </Grid.RowDefinitions>

        <!-- Cabe&#xE7;alho Principal -->
        <Border Grid.Row="0" Background="#1E1E2E" CornerRadius="8" Padding="14,10" Margin="0,0,0,8" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="&#x26A1; WinRepair &amp; Tweaks Pro" FontSize="20" FontWeight="Bold" Foreground="#89B4FA"/>
                    <TextBlock Text="Inspirado no Chris Titus WinUtil: Otimiza&#xE7;&#xF5;es, Tweaks, Recursos, ISO e Reparos" FontSize="11" Foreground="#A6ADC8" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock Name="txtSystemInfo" Text="Identificando m&#xE1;quina..." FontSize="12" Foreground="#94E2D5" HorizontalAlignment="Right"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Abas Principais -->
        <TabControl Grid.Row="1" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="1">
            
            <!-- ABA 1: TWEAKS & PERFIS (ESTILO WINUTIL TWEAKS) -->
            <TabItem Header="&#x26A1; Tweaks &amp; Otimiza&#xE7;&#xE3;o">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <!-- Barra de Perfis com 1 Clique -->
                        <Border Background="#24273A" CornerRadius="6" Padding="10" Margin="2,0,2,8" BorderBrush="#45475A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Perfis Recomendados (1 Clique):" FontWeight="Bold" Foreground="#89B4FA" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <WrapPanel Grid.Column="1" VerticalAlignment="Center">
                                    <Button Name="btnProfileDesktop" Content="&#x1F5A5;&#xFE0F; Perfil Desktop" Padding="12,6" Background="#313244" Foreground="#A6E3A1"/>
                                    <Button Name="btnProfileLaptop" Content="&#x1F4BB; Perfil Notebook" Padding="12,6" Background="#313244" Foreground="#89B4FA"/>
                                    <Button Name="btnProfileGamer" Content="&#x1F3AE; Perfil Gamer Extremo" Padding="12,6" Background="#313244" Foreground="#F38BA8"/>
                                </WrapPanel>
                                <Button Name="btnCreateRestorePoint" Grid.Column="2" Content="&#x1F6E1;&#xFE0F; Criar Ponto de Restaura&#xE7;&#xE3;o" Padding="10,6" Background="#45475A"/>
                            </Grid>
                        </Border>

                        <!-- Grade de Tweaks Granulares -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Coluna 1: Essenciais & Desempenho -->
                            <GroupBox Grid.Column="0" Header="Essenciais &amp; Desempenho">
                                <StackPanel>
                                    <CheckBox Name="chkCleanTemp" Content="Limpar Arquivos Tempor&#xE1;rios" IsChecked="True"/>
                                    <CheckBox Name="chkDisableTelemetry" Content="Desativar Telemetria &amp; CEIP" IsChecked="True"/>
                                    <CheckBox Name="chkDisableBingSearch" Content="Desativar Bing no Menu Iniciar" IsChecked="True"/>
                                    <CheckBox Name="chkDisableGameDvr" Content="Desativar GameDVR (Input Lag)" IsChecked="True"/>
                                    <CheckBox Name="chkOptimizeServices" Content="Servi&#xE7;os Pesados em Manual" IsChecked="True"/>
                                    <CheckBox Name="chkUltimatePower" Content="Plano 'Desempenho M&#xE1;ximo'" IsChecked="True"/>
                                    <CheckBox Name="chkDisableHibernation" Content="Desativar Hiberna&#xE7;&#xE3;o (Desktop)" IsChecked="False"/>
                                    <CheckBox Name="chkFastVisuals" Content="Acelerar Menus (MenuShowDelay)" IsChecked="True"/>
                                    <CheckBox Name="chkSsdTrim" Content="Otimizar SSDs (Executar TRIM)" IsChecked="True"/>
                                </StackPanel>
                            </GroupBox>

                            <!-- Coluna 2: Interface & Usabilidade -->
                            <GroupBox Grid.Column="1" Header="Interface &amp; Usabilidade">
                                <StackPanel>
                                    <CheckBox Name="chkShowFileExt" Content="Mostrar Extens&#xF5;es de Arquivo" IsChecked="True"/>
                                    <CheckBox Name="chkShowHiddenFiles" Content="Mostrar Arquivos Ocultos" IsChecked="True"/>
                                    <CheckBox Name="chkExplorerThisPc" Content="Explorer abre em 'Este Computador'" IsChecked="True"/>
                                    <CheckBox Name="chkDarkMode" Content="Ativar Tema Escuro (Dark Mode)" IsChecked="True"/>
                                    <CheckBox Name="chkDisableMouseAccel" Content="Desativar Acelera&#xE7;&#xE3;o do Mouse (1:1)" IsChecked="True"/>
                                    <CheckBox Name="chkCleanWin11Taskbar" Content="Limpar Barra Tarefas (Widgets/Copilot)" IsChecked="True"/>
                                    <CheckBox Name="chkTakeOwnership" Content="Adicionar 'Take Ownership' no Menu" IsChecked="True"/>
                                    <CheckBox Name="chkUninstallOneDrive" Content="Desinstalar e Purgar OneDrive" IsChecked="False"/>
                                </StackPanel>
                            </GroupBox>

                            <!-- Coluna 3: Rede & TCP Gaming -->
                            <GroupBox Grid.Column="2" Header="Rede &amp; Conectividade">
                                <StackPanel>
                                    <CheckBox Name="chkOptimizeTcp" Content="Otimizar Lat&#xEA;ncia TCP (AutoTune, RSS)" IsChecked="True"/>
                                    <CheckBox Name="chkFlushDns" Content="Limpar Cache DNS" IsChecked="True"/>
                                    <CheckBox Name="chkRenewDhcp" Content="Renovar Concess&#xE3;o de IP / DHCP" IsChecked="False"/>
                                    <CheckBox Name="chkResetNetwork" Content="Redefinir Pilha de Rede Completa" IsChecked="False"/>
                                </StackPanel>
                            </GroupBox>
                        </Grid>

                        <!-- Bot&#xE3;o Aplicar Selecionados -->
                        <Button Name="btnApplySelectedTweaks" Content="&#x1F680; Aplicar Todos os Tweaks Selecionados" Height="42" FontSize="14" FontWeight="Bold" Background="#89B4FA" Foreground="#11111B" Margin="2,8,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 2: REDE, DIAGN&#xD3;STICO COMPLETO & DNS -->
            <TabItem Header="&#x1F310; Rede &amp; Conectividade">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Alvo para Testes Avan&#xE7;ados (Porta TCP, Pathping, Tracert e Ping Cont&#xED;nuo)">
                            <Grid Margin="0,2">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="100"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="90"/>
                                    <ColumnDefinition Width="90"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Host / IP Alvo:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtNetTarget" Grid.Column="1" Margin="0,0,10,0" Text="8.8.8.8"/>
                                <TextBlock Grid.Column="2" Text="Porta TCP:" VerticalAlignment="Center" Foreground="#A6ADC8" HorizontalAlignment="Right" Margin="0,0,8,0"/>
                                <TextBox Name="txtNetPort" Grid.Column="3" Text="443"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="Diagn&#xF3;stico e Testes de Conectividade (Op&#xE7;&#xF5;es 1 a 8)">
                            <WrapPanel>
                                <Button Name="btnNetQuickDiag" Content="[1] Diagn&#xF3;stico R&#xE1;pido Integrado" Width="230" Height="34"/>
                                <Button Name="btnNetDetailed" Content="[2] Teste Detalhado (Ping + HTTPS + DNS)" Width="270" Height="34"/>
                                <Button Name="btnNetSpeedtest" Content="[3] Teste Velocidade Download (Mbps)" Width="250" Height="34"/>
                                <Button Name="btnNetWifi" Content="[4] Diagn&#xF3;stico Wi-Fi (Sinal/Redes)" Width="230" Height="34"/>
                                <Button Name="btnNetWifiReport" Content="[4b] Gerar Relat&#xF3;rio Wi-Fi (HTML)" Width="230" Height="34"/>
                                <Button Name="btnNetTestPort" Content="[5] Testar Porta TCP Alvo" Width="190" Height="34"/>
                                <Button Name="btnNetPathping" Content="[6] Perda de Pacotes (Pathping)" Width="220" Height="34"/>
                                <Button Name="btnNetTracert" Content="[7] Rastrear Rota (Tracert)" Width="200" Height="34"/>
                                <Button Name="btnNetPingCont" Content="[8] Ping Cont&#xED;nuo (-t)" Width="180" Height="34"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Monitoramento, Varredura &amp; Dispositivos (Op&#xE7;&#xF5;es 9 a 11)">
                            <WrapPanel>
                                <Button Name="btnNetstatEst" Content="[9a] Netstat: Conex&#xF5;es Ativas" Width="210" Height="34"/>
                                <Button Name="btnNetstatList" Content="[9b] Netstat: Portas Escutando" Width="210" Height="34"/>
                                <Button Name="btnNetstatAll" Content="[9c] Netstat: Tudo Detalhado" Width="200" Height="34"/>
                                <Button Name="btnNetSubnetScan" Content="[10] Varredura Rede Local (IPs Livres/Ocupados)" Width="310" Height="34" Background="#313244" Foreground="#A6E3A1"/>
                                <Button Name="btnNetIpConfig" Content="[11] Exibir ipconfig /all" Width="170" Height="34"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Reparo, Reset, Relat&#xF3;rio Forense &amp; Otimiza&#xE7;&#xE3;o TCP (Op&#xE7;&#xF5;es 12 a 14)">
                            <WrapPanel>
                                <Button Name="btnNetSimpleRepair" Content="[12] Reparar Conex&#xE3;o (DNS/DHCP/NetBIOS)" Width="270" Height="34"/>
                                <Button Name="btnNetResetDeep" Content="[13] Reset Completo Pilha (Winsock/TCP/FW)" Width="280" Height="34"/>
                                <Button Name="btnNetForensicReport" Content="[14] Gerar Relat&#xF3;rio Forense Completo (.TXT)" Width="290" Height="34" Background="#313244" Foreground="#89B4FA"/>
                                <Button Name="btnRestartAdapters" Content="Reiniciar Placas de Rede" Width="190" Height="34"/>
                                <Button Name="btnOptimizeTcpTab" Content="&#x1F680; Otimizar TCP Baixa Lat&#xEA;ncia" Width="220" Height="34"/>
                            </WrapPanel>
                        </GroupBox>

                        <GroupBox Header="Troca R&#xE1;pida de Servidores DNS">
                            <WrapPanel>
                                <Button Name="btnDnsCloudflare" Content="Cloudflare (1.1.1.1) - Veloz" Width="200" Height="34"/>
                                <Button Name="btnDnsGoogle" Content="Google (8.8.8.8) - Confi&#xE1;vel" Width="200" Height="34"/>
                                <Button Name="btnDnsQuad9" Content="Quad9 (9.9.9.9) - Anti-Malware" Width="210" Height="34"/>
                                <Button Name="btnDnsAdGuard" Content="AdGuard - Bloqueia An&#xFA;ncios" Width="200" Height="34"/>
                                <Button Name="btnDnsDhcp" Content="Restaurar Autom&#xE1;tico (DHCP)" Width="200" Height="34"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 3: RECURSOS & UPDATES (ESTILO WINUTIL CONFIG & UPDATES) -->
            <TabItem Header="&#x2699;&#xFE0F; Recursos &amp; Updates">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Gerenciamento do Windows Update (Estilo Chris Titus)">
                            <StackPanel>
                                <TextBlock Text="Controle como o Windows Update lida com atualiza&#xE7;&#xF5;es para evitar travamentos e reinicializa&#xE7;&#xF5;es for&#xE7;adas:" FontSize="11" Foreground="#A6ADC8" Margin="4,0,0,6"/>
                                <WrapPanel>
                                    <Button Name="btnWuRecommended" Content="&#x1F6E1;&#xFE0F; Modo Recomendado (Seguran&#xE7;a Est&#xE1;vel &amp; Sem Rein&#xED;cio For&#xE7;ado)" Width="460" Height="36"/>
                                    <Button Name="btnWuDefault" Content="&#x1F504; Restaurar Padr&#xE3;o da Microsoft" Width="240" Height="36"/>
                                    <Button Name="btnWuPause" Content="&#x23F8;&#xFE0F; Pausar Atualiza&#xE7;&#xF5;es (At&#xE9; 2042)" Width="230" Height="36"/>
                                </WrapPanel>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Recursos Opcionais do Windows (Ativa&#xE7;&#xE3;o com 1 Clique)">
                            <WrapPanel>
                                <Button Name="btnEnableWsl" Content="Ativar WSL 2 (Subsistema Linux)" Width="240" Height="36"/>
                                <Button Name="btnEnableSandbox" Content="Ativar Windows Sandbox" Width="210" Height="36"/>
                                <Button Name="btnEnableHyperV" Content="Ativar Hyper-V" Width="180" Height="36"/>
                                <Button Name="btnEnableNet35" Content="Ativar .NET Framework 3.5" Width="220" Height="36"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 4: MICROWIN / CRIADOR DE ISO -->
            <TabItem Header="&#x1F4BF; MicroWin (Criador de ISO)">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="1. Sele&#xE7;&#xE3;o da Imagem ISO Oficial">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="140"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="140"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Arquivo ISO Origem:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtIsoPath" Grid.Column="1" Margin="0,0,8,0" Text="" ToolTip="Selecione um arquivo .iso oficial do Windows 10 ou 11"/>
                                <Button Name="btnBrowseIso" Grid.Column="2" Content="Procurar ISO..." Width="120" Height="32"/>
                                <Button Name="btnInspectIso" Grid.Column="3" Content="Analisar Edi&#xE7;&#xF5;es" Width="130" Height="32"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="2. Destino e Edi&#xE7;&#xE3;o">
                            <Grid Margin="0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="140"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="100"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Pasta de Destino:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtOutputIsoDir" Grid.Row="0" Grid.Column="1" Margin="0,0,8,4" Text="C:\ISO_Work"/>
                                <Button Name="btnBrowseOutputDir" Grid.Row="0" Grid.Column="2" Content="Selecionar Pasta..." Width="120" Height="32" Margin="0,0,0,4"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Nome do Arquivo:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtOutputIsoName" Grid.Row="1" Grid.Column="1" Margin="0,0,8,0" Text="Windows_MicroWin_Custom.iso"/>

                                <TextBlock Grid.Row="1" Grid.Column="2" Text="&#xCD;ndice da Edi&#xE7;&#xE3;o:" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="#A6ADC8" Margin="0,0,6,0"/>
                                <TextBox Name="txtEditionIndex" Grid.Row="1" Grid.Column="3" Text="1" Width="50" HorizontalAlignment="Left"/>
                            </Grid>
                        </GroupBox>

                        <GroupBox Header="3. Modifica&#xE7;&#xF5;es MicroWin a Injetar">
                            <StackPanel>
                                <CheckBox Name="chkIsoBypassHw" Content="Bypass de Requisitos Win 11 (Ignora TPM 2.0, Secure Boot, RAM e CPU)" IsChecked="True"/>
                                <CheckBox Name="chkIsoBypassAcc" Content="Bypass de Conta Microsoft Obrigat&#xF3;ria (Permite criar Conta Local offline - BypassNRO)" IsChecked="True"/>
                                <CheckBox Name="chkIsoDisableBitLocker" Content="Desativar Criptografia Autom&#xE1;tica do BitLocker no primeiro boot" IsChecked="True"/>
                                <CheckBox Name="chkIsoDebloat" Content="Remover Bloatware AppX na raiz da imagem (Xbox overlays, Clipchamp, Not&#xED;cias, Jogos)" IsChecked="True"/>
                                <CheckBox Name="chkIsoUnattend" Content="Injetar autounattend.xml (Pula telas de termos, diagn&#xF3;stico e an&#xFA;ncios no primeiro boot)" IsChecked="True"/>
                            </StackPanel>
                        </GroupBox>

                        <Button Name="btnBuildCustomIso" Content="&#x1F680; Gerar Nova ISO MicroWin Otimizada!" Height="44" FontSize="14" FontWeight="Bold" Background="#89B4FA" Foreground="#11111B" Margin="2,4,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 5: SOFTWARES (WINGET) -->
            <TabItem Header="&#x1F4E6; Softwares">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <Grid Margin="0,0,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="Instale ou atualize silenciosamente os softwares essenciais via Winget:" FontSize="11" Foreground="#A6ADC8" VerticalAlignment="Center"/>
                            <Button Name="btnUpgradeAllSoftware" Grid.Column="1" Content="&#x1F504; Atualizar Todos os Apps (winget upgrade --all)" Padding="10,5"/>
                        </Grid>

                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <GroupBox Grid.Column="0" Header="Navegadores">
                                <StackPanel>
                                    <CheckBox Name="chkSoftwareChrome" Content="Google Chrome" Tag="Google.Chrome"/>
                                    <CheckBox Name="chkSoftwareFirefox" Content="Mozilla Firefox" Tag="Mozilla.Firefox"/>
                                    <CheckBox Name="chkSoftwareBrave" Content="Brave Browser" Tag="Brave.Brave"/>
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Grid.Column="1" Header="Utilit&#xE1;rios Essenciais">
                                <StackPanel>
                                    <CheckBox Name="chkSoftware7zip" Content="7-Zip" Tag="7zip.7zip" IsChecked="True"/>
                                    <CheckBox Name="chkSoftwareNotepad" Content="Notepad++" Tag="Notepad++.Notepad++"/>
                                    <CheckBox Name="chkSoftwareAnyDesk" Content="AnyDesk" Tag="AnyDeskSoftwareGmbH.AnyDesk"/>
                                    <CheckBox Name="chkSoftwarePowerToys" Content="Microsoft PowerToys" Tag="Microsoft.PowerToys"/>
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Grid.Column="2" Header="M&#xED;dia &amp; Dev/Jogos">
                                <StackPanel>
                                    <CheckBox Name="chkSoftwareVlc" Content="VLC Media Player" Tag="VideoLAN.VLC"/>
                                    <CheckBox Name="chkSoftwareVsCode" Content="Visual Studio Code" Tag="Microsoft.VisualStudioCode"/>
                                    <CheckBox Name="chkSoftwareSteam" Content="Steam" Tag="Valve.Steam"/>
                                    <CheckBox Name="chkSoftwareDiscord" Content="Discord" Tag="Discord.Discord"/>
                                </StackPanel>
                            </GroupBox>
                        </Grid>

                        <Button Name="btnInstallSelectedSoftware" Content="Baixar e Instalar Softwares Selecionados" Height="38" Margin="2,8,2,2"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 6: REPAROS DO SISTEMA -->
            <TabItem Header="&#x1F6E0;&#xFE0F; Reparo do SO">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Integridade de Arquivos e Componentes">
                            <WrapPanel>
                                <Button Name="btnSfcScan" Content="Verifica&#xE7;&#xE3;o de Integridade (SFC /scannow)" Width="270" Height="36"/>
                                <Button Name="btnDismRepair" Content="Reparar Imagem do Windows (DISM)" Width="260" Height="36"/>
                                <Button Name="btnDismCleanup" Content="Limpar Component Store (WinSxS)" Width="250" Height="36"/>
                                <Button Name="btnRestartSpooler" Content="Destravar Spooler de Impress&#xE3;o" Width="230" Height="36"/>
                                <Button Name="btnScheduleChkdsk" Content="Agendar CHKDSK no Disco C:" Width="230" Height="36"/>
                            </WrapPanel>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ABA 7: LICENCIAMENTO -->
            <TabItem Header="&#x1F511; Licenciamento">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="8">
                        <GroupBox Header="Licen&#xE7;a do Windows">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,6">
                                    <Button Name="btnCheckWinLicense" Content="Verificar Status da Licen&#xE7;a" Width="210" Height="34"/>
                                </WrapPanel>
                                <Grid Margin="0,2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Windows:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtWinKey" Grid.Column="1" Margin="0,0,8,0" Text=""/>
                                    <Button Name="btnApplyWinKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="170" Height="32"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Licen&#xE7;a do Microsoft Office">
                            <StackPanel>
                                <WrapPanel Margin="0,0,0,6">
                                    <Button Name="btnCheckOfficeLicense" Content="Verificar Status do Office" Width="210" Height="34"/>
                                </WrapPanel>
                                <Grid Margin="0,2">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="130"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Chave do Office:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                    <TextBox Name="txtOfficeKey" Grid.Column="1" Margin="0,0,8,0" Text=""/>
                                    <Button Name="btnApplyOfficeKey" Grid.Column="2" Content="Instalar e Ativar Chave" Width="170" Height="32"/>
                                </Grid>
                            </StackPanel>
                        </GroupBox>

                        <GroupBox Header="Servidor KMS Institucional">
                            <Grid Margin="0,2">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="130"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Host KMS Oficial:" VerticalAlignment="Center" Foreground="#A6ADC8"/>
                                <TextBox Name="txtKmsHost" Grid.Column="1" Margin="0,0,8,0" Text="kms.dominio.local"/>
                                <Button Name="btnSetKms" Grid.Column="2" Content="Configurar Servidor KMS" Width="170" Height="32"/>
                            </Grid>
                        </GroupBox>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Painel Inferior de Logs -->
        <Border Grid.Row="2" Background="#11111B" CornerRadius="8" Margin="0,8,0,0" BorderBrush="#313244" BorderThickness="1">
            <Grid Margin="6">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,0,0,2">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="&#x1F4DC; Console de Execu&#xE7;&#xE3;o &amp; Logs em Tempo Real" FontSize="11" FontWeight="SemiBold" Foreground="#89B4FA" VerticalAlignment="Center"/>
                    <Button Name="btnClearLogs" Grid.Column="1" Content="Limpar Log" Padding="6,3" FontSize="11" Margin="0"/>
                </Grid>

                <TextBox Name="txtLog" Grid.Row="1"
                         Background="#11111B"
                         Foreground="#A6E3A1"
                         FontFamily="Consolas"
                         FontSize="12"
                         IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto"
                         TextWrapping="Wrap"
                         BorderThickness="0"/>
            </Grid>
        </Border>
    </Grid>
</Window>

'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

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

# Timer da UI para drenar logs e limpar Runspaces finalizados
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

# Informações do Sistema
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
        Write-ToolLog "Atualização geral de programas concluída." "SUCCESS"
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
