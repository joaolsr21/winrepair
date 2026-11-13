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
