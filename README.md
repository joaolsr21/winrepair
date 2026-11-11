# ⚡ WinRepair & Tweaks Pro

Utilitário profissional e avançado para manutenção, diagnóstico de rede, reparos do sistema, debloat profundo, instalador de softwares e **criador de ISOs personalizadas e otimizadas do Windows 10 e 11**.

Projetado para execução direta em qualquer computador via PowerShell (`irm | iex`).

---

## 🚀 Como Executar em Qualquer PC

Abra o **PowerShell como Administrador** e execute:

```powershell
irm https://raw.githubusercontent.com/joaolsr21/winrepair/main/dist/winrepair.ps1 | iex
```

---

## 🛠️ O que há de novo nesta versão Pro

### 🌐 1. Rede, Conectividade & Gaming
* **Diagnóstico de Qualidade de Rede**: Medição de latência média (ping), perda de pacotes e descoberta de IP público.
* **Otimizações TCP/IP de Baixa Latência**:
  * TCP Window Auto-Tuning Normal.
  * Habilitação de RSS (Receive Side Scaling) para distribuir pacotes de rede entre os núcleos do processador.
  * Habilitação de ECN (Explicit Congestion Notification).
  * Remoção do índice de limitação de rede (`NetworkThrottlingIndex = 0xFFFFFFFF`) e redução da latência multimídia (`SystemResponsiveness = 0`).
* **Seleção de DNS de Alta Performance com 1 Clique**:
  * **Cloudflare** (`1.1.1.1` / `1.0.0.1`) - Foco em velocidade pura.
  * **Google** (`8.8.8.8` / `8.8.4.4`) - Confiabilidade global.
  * **Quad9** (`9.9.9.9`) - Proteção integrada contra phishing e malware.
  * **AdGuard DNS** (`94.140.14.14`) - Bloqueio de anúncios e rastreadores diretamente na rede.
  * **Restaurar DHCP** - Retorna ao modo automático do roteador.
* **Reparos de Rede**: Flush DNS, Renovação de concessão DHCP, Reinício de placas de rede e Reset total da pilha (Winsock, IPv4, IPv6 e Firewall).

---

### ⚡ 2. Otimizações, Desempenho & Debloat
* **Desempenho Extremo**:
  * Desbloqueio e ativação do plano oculto da Microsoft **"Desempenho Máximo" (Ultimate Performance)**.
  * Desativação de gravação em segundo plano do **GameDVR** (elimina quedas de FPS e atraso de entrada em jogos).
  * Redução do tempo de resposta de menus suspensos (`MenuShowDelay = 10ms`) e otimização do escalonador de prioridade de CPU para programas em primeiro plano.
* **Debloat Profundo e Privacidade**:
  * Remoção em lote de bloatwares e aplicativos inúteis pré-instalados pela Microsoft (News, Weather, Solitaire, Clipchamp, Xbox gaming overlays, apps patrocinados).
  * Desativação de serviços e tarefas agendadas de telemetria e diagnóstico (`DiagTrack`, `dmwappushservice`, CEIP).
  * Desativação de pesquisas da Web com o Bing no Menu Iniciar e bloqueio de sugestões/anúncios de aplicativos no sistema.
* **Armazenamento**:
  * Limpeza profunda de temporários de sistema e usuário, logs de travamento, caches de miniaturas e esvaziamento da lixeira.
  * Reset limpo do cache corrompido do Windows Update (`SoftwareDistribution`).
  * Envio de comando TRIM para todos os SSDs.
  * Ativação e desativação de hibernação para liberar espaço no disco C: equivalente à quantidade de memória RAM instalada.

---

### 🛠️ 3. Reparos do Sistema Operacional
* **SFC (/scannow)**: Verificação e restauração de arquivos essenciais do sistema corrompidos.
* **DISM (/RestoreHealth)**: Reparo avançado da imagem do Windows utilizando fontes oficiais.
* **Limpeza do WinSxS (/StartComponentCleanup /ResetBase)**: Eliminação de versões obsoletas de atualizações para recuperar espaço em disco.
* **Destravar Spooler de Impressão**: Limpa a fila de arquivos travados em disco e reinicia o serviço.
* **Agendamento de CHKDSK**: Programa varredura e correção de setores na inicialização.

---

### 💿 4. Criador Interativo de ISO Otimizada (Win 10/11)
Não precisa digitar caminhos complicados:
1. **Interface Visual**: Botão *"Procurar ISO..."* para selecionar sua ISO oficial do Windows 10 ou 11.
2. **Análise de Edições**: Detecta e lista as edições disponíveis na imagem (`install.wim` ou `install.esd`).
3. **Checkboxes de Otimização Direta na ISO**:
   * ✅ **Bypass Requisitos Win 11**: Contorna verificações de TPM 2.0, Secure Boot, memória RAM e processadores não suportados.
   * ✅ **Bypass Conta Microsoft (BypassNRO)**: Permite a criação de conta de usuário local e offline logo no primeiro boot (OOBE).
   * ✅ **Desativar BitLocker Automático**: Impede que o instalador criptografe o disco silenciosamente sem o seu consentimento.
   * ✅ **Debloat na Raiz**: Remove pacotes AppX inúteis direto na imagem para que a instalação já nasça limpa.
   * ✅ **Injetar autounattend.xml**: Pula telas de diagnóstico, aceitação de termos repetitivos e telemetria no primeiro boot.
4. **Geração Automatizada**: Pipeline completo em segundo plano com logs ao vivo de cada etapa!

---

### 📦 5. Instalador de Softwares em Lote (Winget)
Instalação 100% silenciosa dos principais programas essenciais para formatar e entregar o PC pronto:
* **Navegadores**: Google Chrome, Mozilla Firefox, Brave.
* **Utilitários**: 7-Zip, Notepad++, AnyDesk, Microsoft PowerToys.
* **Mídia & Dev/Jogos**: VLC Media Player, Visual Studio Code, Steam, Discord.

---

### 🔑 6. Gestão de Licenciamento (Windows e Office)
* Consulta ao vivo do status de ativação genuína via WMI e `slmgr.vbs`.
* Instalação e validação de chaves oficiais para Windows e pacotes do Microsoft Office.
* Apontamento de servidores KMS corporativos/institucionais oficiais.

---

## 📁 Estrutura do Código

```text
├── src/
│   ├── core/
│   │   ├── elevation.ps1           # Elevação segura sem disparar falso positivo
│   │   └── logger.ps1              # Logger com saída no console e GUI WPF
│   ├── modules/
│   │   ├── network.ps1             # Diagnóstico de rede, TCP gaming tweaks e DNS
│   │   ├── optimizer.ps1           # Debloat, Ultimate Performance, temporários e TRIM
│   │   ├── system_repair.ps1       # SFC, DISM, WinSxS e Spooler
│   │   ├── iso_builder.ps1         # Pipeline completo de customização de ISO
│   │   ├── software_installer.ps1  # Instalador silencioso via Winget
│   │   └── licensing.ps1           # Ativação oficial Windows e Office
│   ├── ui/
│   │   └── app.xaml                # Interface moderna rica em WPF com suporte a emoji
│   └── main.ps1                    # Ponto de entrada modular
├── dist/
│   └── winrepair.ps1               # Pacote único compilado UTF-8 com BOM
├── build.ps1                       # Compilador automatizado
└── README.md
```
