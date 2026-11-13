# ⚡ WinRepair & Tweaks Pro

Utilitário all-in-one para Windows 10 e 11, **inspirado e baseado diretamente na arquitetura e nas configurações do Chris Titus Tech (WinUtil)**, trazendo recursos avançados de otimização, perfis com 1 clique, gerenciamento de atualizações, diagnóstico de rede, instalador em lote e o criador de ISO **MicroWin**.

Projetado para execução direta em qualquer máquina através de uma única linha no PowerShell (`irm | iex`).

---

## 🚀 Como Executar

Abra o **PowerShell como Administrador** e cole:

```powershell
irm https://raw.githubusercontent.com/joaolsr21/winrepair/main/dist/winrepair.ps1 | iex
```

---

## 🏆 Comparativo e Funcionalidades (Estilo Chris Titus WinUtil)

### ⚡ 1. Tweaks & Perfis Recomendados (O Coração da Ferramenta)
Assim como no WinUtil do Chris Titus, você pode aplicar tudo com **1 clique através de perfis pré-configurados** ou marcar individualmente os tweaks que desejar:

* **Perfis com 1 Clique:**
  * 🖥️ **Perfil Desktop (PC de Mesa)**: Cria Ponto de Restauração, limpa temporários, desativa telemetria e Bing, desativa GameDVR, desativa hibernação (liberando gigabytes do disco C:), coloca serviços secundários em manual, ativa o plano de energia *Desempenho Máximo*, exibe extensões de arquivo e abre o Explorer em *Este Computador*.
  * 💻 **Perfil Notebook / Laptop**: Aplica os mesmos ganhos de desempenho do desktop, porém **mantém a hibernação ativa** para garantir a segurança da bateria ao fechar a tampa.
  * 🎮 **Perfil Gamer Extremo**: Otimizações adicionais de baixa latência TCP, desativação de aceleração de mouse (mira 1:1), prioridade máxima de CPU para jogos e latência de multimídia zerada (`SystemResponsiveness = 0`).
  * 🛡️ **Ponto de Restauração**: Criação automática de ponto de restauração antes de modificar o sistema.

* **Tweaks Granulares Selecionáveis:**
  * **Essenciais & Desempenho**: Limpeza de temporários, Telemetria & CEIP desativados, Bing Search desativado, GameDVR desativado, Serviços pesados em manual, Desempenho Máximo, Hibernação ligada/desligada, MenuShowDelay (10ms), TRIM em SSDs.
  * **Interface & Usabilidade**: Extensões de arquivos visíveis, Arquivos ocultos visíveis, Explorer abre em *Este Computador*, Tema Escuro global (Dark Mode), Aceleração do mouse desativada, Remoção de Widgets/Copilot/Chat da barra de tarefas do Win11, Adicionar "Take Ownership" ao botão direito, Desinstalação completa e purga do OneDrive.
  * **Rede & TCP Gaming**: TCP Window Auto-Tuning, RSS (Receive Side Scaling), ECN, Flush DNS, Renovação DHCP e Reset total da pilha.

---

### ⚙️ 2. Configurações & Windows Update (Aba "Recursos & Updates")
Diretamente baseado nas abas *Config* e *Updates* do Chris Titus:
* **Gerenciamento do Windows Update**:
  * 🛡️ **Modo Recomendado (Segurança Estável)**: Atrasa atualizações instáveis de recursos por 1 ano (365 dias), recebe atualizações de segurança cumulativas com 4 dias de tolerância e **bloqueia reinicializações forçadas** enquanto o computador estiver em uso.
  * 🔄 **Restaurar Padrão da Microsoft**: Reverte as políticas de atualização para o padrão de fábrica.
  * ⏸️ **Pausar Atualizações (Até 2042)**: Congela temporariamente as atualizações automáticas.
* **Recursos Opcionais do Windows com 1 Clique**:
  * Ativar **WSL 2** (Windows Subsystem for Linux + Virtual Machine Platform).
  * Ativar **Windows Sandbox** (Área Restrita do Windows).
  * Ativar **Hyper-V** (Virtualização nativa da Microsoft).
  * Ativar **.NET Framework 3.5** (necessário para programas e jogos legados).

---

### 💿 3. MicroWin (Criador de ISO Modificada Win 10/11)
Inspirado na funcionalidade *MicroWin* do Chris Titus para gerar ISOs ultraleves e despoluídas:
* Seleção visual da ISO oficial via botão nativo *"Procurar ISO..."*.
* Identificação automática das edições contidas no `install.wim` ou `install.esd`.
* **Modificações Injetadas na ISO**:
  * ✅ **Bypass Hardware Win 11**: Remove checagem de TPM 2.0, Secure Boot, memória RAM e CPUs não suportadas.
  * ✅ **Bypass Conta Microsoft (BypassNRO)**: Permite instalar o Windows e criar uma conta local sem conexão à internet.
  * ✅ **Desativar BitLocker Automático**: Impede o bloqueio e criptografia involuntária do drive.
  * ✅ **Debloat na Raiz**: Elimina bloatwares da Microsoft Store antes mesmo da primeira inicialização.
  * ✅ **Injetar autounattend.xml**: Instalação desacompanhada sem telas de termos, diagnóstico e publicidade.

---

### 📦 4. Instalador de Softwares em Lote (Winget)
Assim como na aba *Install* do WinUtil:
* Seleção por caixas dos softwares mais populares (Chrome, Firefox, Brave, 7-Zip, Notepad++, AnyDesk, PowerToys, VLC, VS Code, Steam, Discord).
* Botão **"Atualizar Todos os Apps (`winget upgrade --all`)"** para manter o computador 100% atualizado com 1 clique.

---

### 🌐 5. Rede, Conectividade & Diagnóstico (14 Ferramentas Integradas)
* **Diagnósticos & Testes**: Diagnóstico Rápido Integrado (`ping`, gateway, DNS, WAN), Teste Detalhado de Internet, Teste de Velocidade de Download (CDN Cloudflare 5MB), Diagnóstico Wi-Fi (`netsh wlan`) e Relatório HTML Completo (`wlanreport`).
* **Monitoramento & Análise**: Teste de Porta TCP específica, Análise de Rota (`pathping` / `tracert`), Ping Contínuo em janela separada (`ping -t`), Monitor de Conexões Ativas (`netstat` Established / Listening / All) e Varredura de IPs na Rede Local (`/24` paralela + blocos de IPs livres + `arp -a`) com relatório no Desktop.
* **Reparo, TCP/IP & DNS**: `ipconfig /all`, Reparo Simples (Flush DNS, Release/Renew DHCP, `nbtstat -R`), Reset Profundo (Winsock, IPv4/IPv6, Proxy, ARP e Firewall), Otimização TCP/IP Gaming (RSS, Chimney/AutoTuning), troca instantânea de DNS (**Cloudflare**, **Google**, **Quad9**, **AdGuard**, **DHCP**) e **Relatório Forense Completo** salvo na Área de Trabalho.

---

### 🛠️ 6. Reparos do Sistema & Licenciamento
* Reparo de integridade com `sfc /scannow` e `DISM /RestoreHealth`.
* Limpeza profunda do WinSxS (`/StartComponentCleanup /ResetBase`).
* Destravamento do Spooler de impressão e agendamento de `CHKDSK`.
* Ativação e gestão oficial de chaves para Windows, Office e apontamento de servidores KMS corporativos.

---

## 📁 Estrutura do Repositório

```text
├── src/
│   ├── core/
│   │   ├── elevation.ps1           # Elevação segura sem disparar falso positivo
│   │   └── logger.ps1              # Logger console + UI WPF
│   ├── modules/
│   │   ├── network.ps1             # Diagnóstico de rede, TCP gaming tweaks e DNS
│   │   ├── optimizer.ps1           # Perfis 1-Clique (Desktop/Laptop/Gamer), Debloat e Serviços
│   │   ├── tweaks_system.ps1       # Usabilidade (Extensões, Dark Mode, Mouse 1:1, Tarefas, OneDrive)
│   │   ├── windows_features.ps1    # Recursos opcionais (WSL 2, Sandbox, Hyper-V, .NET 3.5)
│   │   ├── windows_update.ps1      # Modo Recomendado, Padrão e Pausa até 2042
│   │   ├── system_repair.ps1       # SFC, DISM, WinSxS e Spooler
│   │   ├── iso_builder.ps1         # Pipeline MicroWin completo
│   │   ├── software_installer.ps1  # Instalador Winget e atualização geral
│   │   └── licensing.ps1           # Ativação oficial Windows e Office
│   ├── ui/
│   │   └── app.xaml                # Interface WPF moderna (Catppuccin Dark)
│   └── main.ps1                    # Ponto de entrada modular
├── dist/
│   └── winrepair.ps1               # Pacote único compilado (UTF-8 com BOM)
├── build.ps1                       # Compilador automatizado
└── README.md
```
