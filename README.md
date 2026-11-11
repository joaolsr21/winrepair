# ⚡ WinRepair & Tweaks Utility

Ferramenta multifuncional de reparos rápidos, otimizações, diagnóstico e customização de imagens do Windows, projetada para execução direta via PowerShell (`irm | iex`) sem necessidade de instalação manual prévia.

Inspirado na arquitetura do utilitário *WinUtil* do Chris Titus, porém focado em suporte técnico rápido, diagnóstico de rede, limpeza, integridade do sistema e gerenciamento de imagens e licenças.

---

## 🚀 Como Executar

Abra o **PowerShell como Administrador** e execute o comando de uma linha:

```powershell
irm https://raw.githubusercontent.com/joaolsr21/winrepair/main/dist/winrepair.ps1 | iex
```

*(Substitua `SEU_USUARIO/SEU_REPOSITORIO` pelo seu repositório do GitHub após publicá-lo).*

---

## 🛠️ Funcionalidades

### 🌐 1. Rede e Conectividade
* **Limpar Cache DNS**: Esvazia o cache local do resolvedor de nomes DNS.
* **Redefinir Pilha de Rede**: Restaura a pilha TCP/IP e o Winsock aos padrões de fábrica (`netsh winsock reset` e `netsh int ip reset`).
* **Renovar Concessão de IP / DHCP**: Libera e renova o endereço IP com o roteador/DHCP.
* **Reiniciar Adaptadores de Rede**: Desativa e reativa adaptadores físicos para destravar conexões instáveis.
* **Seleção de DNS Rápido**: Configura DNS de alto desempenho (Cloudflare `1.1.1.1` ou Google `8.8.8.8`) ou restaura para o DHCP automático.

### ⚡ 2. Otimizações do Computador
* **Limpeza Profunda de Temporários**: Limpa pastas temporárias de usuários e sistema (`%TEMP%`, `C:\Windows\Temp`, `Prefetch`, crash dumps e esvazia a lixeira).
* **Reset de Cache do Windows Update**: Interrompe serviços e limpa arquivos corrompidos de download (`SoftwareDistribution\Download`).
* **Otimização de SSD (TRIM)**: Envia o comando `ReTrim` para todos os volumes SSDs fixos.
* **Redução de Telemetria**: Desativa serviços de telemetria desnecessários (`DiagTrack`, `dmwappushservice`) e aplica políticas de redução de coleta de dados.
* **Gerenciamento de Hibernação**: Ativa ou desativa o arquivo `hiberfil.sys` para recuperar gigabytes equivalentes à memória RAM em discos compactos.

### 🛠️ 3. Reparos do Sistema Operacional
* **Verificação de Integridade (SFC /scannow)**: Varre e repara arquivos corrompidos do Windows protegidos pelo sistema.
* **Reparo da Imagem do Windows (DISM /RestoreHealth)**: Repara o repositório de componentes do Windows usando fontes locais ou o Windows Update.
* **Limpeza do WinSxS (/StartComponentCleanup)**: Limpa versões anteriores de atualizações e componentes obsoletos para liberar espaço.
* **Destravar Spooler de Impressão**: Interrompe o serviço, limpa filas de impressão travadas em disco e reinicia o serviço.
* **Agendamento de CHKDSK**: Programa uma checagem de integridade e reparo de setores no disco `C:` para a próxima reinicialização.

### 💿 4. Criador e Customizador de ISO (DISM)
* **Informações do WIM**: Lista índices e edições disponíveis em um arquivo `install.wim` ou `install.esd`.
* **Montagem de Imagem**: Monta a imagem WIM em diretório de trabalho de forma segura.
* **Remoção de Bloatware (AppX)**: Remove pacotes pré-instalados desnecessários da imagem do Windows (Xbox overlays, Clipchamp, Solitaire, News, Weather, etc.).
* **Bypass de Requisitos de Hardware**: Injeta no registro offline da imagem os parâmetros para ignorar verificações de TPM 2.0, SecureBoot, RAM e permite a criação de conta local no Windows 11 (BypassNRO).
* **Salvar / Descartar Alterações**: Desmonta salvando as modificações prontas para geração da ISO final.

### 🔑 5. Gerenciamento de Licenças (Windows e Office)
* **Status da Licença do Windows**: Consulta status de ativação genuína via WMI (`SoftwareLicensingProduct`) e `slmgr.vbs /xpr`.
* **Instalação de Chave do Windows**: Aplica chave de produto legítima e executa ativação online oficial (`slmgr.vbs /ipk` e `/ato`).
* **Status do Microsoft Office**: Detecta instalações do Office (Office16/15) e consulta status via `ospp.vbs /dstatus`.
* **Instalação de Chave do Office**: Aplica chave de produto válida no Office (`ospp.vbs /inpkey` e `/act`).
* **Configuração de Servidor KMS**: Permite que organizações e empresas apontem o servidor KMS oficial interno para ativação em volume.

---

## 📁 Estrutura do Projeto

```text
├── src/
│   ├── core/
│   │   ├── elevation.ps1       # Verificação e elevação para Administrador
│   │   └── logger.ps1          # Sistema de log para console e interface gráfica
│   ├── modules/
│   │   ├── network.ps1         # Funções de rede e DNS
│   │   ├── optimizer.ps1       # Funções de limpeza e performance
│   │   ├── system_repair.ps1   # SFC, DISM e reparos do SO
│   │   ├── iso_builder.ps1     # Montagem, debloat e bypass de imagem WIM
│   │   └── licensing.ps1       # Gestão oficial de chaves Windows e Office
│   ├── ui/
│   │   └── app.xaml            # Interface gráfica moderna em WPF / Dark Theme
│   └── main.ps1                # Ponto de entrada modular para desenvolvimento
├── dist/
│   └── winrepair.ps1           # Script único compilado pronto para 'irm | iex'
├── build.ps1                   # Compilador que gera o dist/winrepair.ps1
└── README.md
```

---

## ⚙️ Como Compilar Alterações

Se fizer qualquer alteração nos módulos dentro de `src/`, execute o script de compilação:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

O arquivo `dist/winrepair.ps1` será automaticamente atualizado agregando todos os scripts e a interface XAML.

---

## 📦 Licença e Uso

Este utilitário foi desenvolvido para técnicos de TI, administradores de sistemas e usuários avançados para agilizar procedimentos de manutenção e suporte. Use sempre em conformidade com as políticas e diretrizes da sua organização.
