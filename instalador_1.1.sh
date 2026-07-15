#!/bin/bash

# Define cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arquivos de log (TXT, fáceis de abrir em qualquer editor)
LOG_FILE="$HOME/hyprland_install.txt"
ERROR_LOG="$HOME/hyprland_install_erros.txt"

# Diretório original de onde o script foi chamado (usado para voltar após operações em /tmp)
SCRIPT_DIR="$(pwd)"

# Limpar logs anteriores e escrever cabeçalho legível
{
    echo "=========================================="
    echo " INSTALAÇÃO HYPRLAND - LOG DE EXECUÇÃO"
    echo " Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')"
    echo " Usuário: $(whoami)"
    echo "=========================================="
    echo ""
} > "$LOG_FILE"

{
    echo "=========================================="
    echo " INSTALAÇÃO HYPRLAND - LOG DE ERROS"
    echo " Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')"
    echo "=========================================="
    echo ""
} > "$ERROR_LOG"

# Função para logging (sem códigos de cor no arquivo, só no terminal)
log() {
    echo -e "$1"
    echo -e "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE"
}

error_log() {
    echo -e "$1"
    echo -e "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$ERROR_LOG"
}

# Arrays para rastrear pacotes
declare -A PACOTES_JA_INSTALADOS
declare -A PACOTES_NECESSARIOS
declare -A PACOTES_INSTALADOS
declare -a PACOTES_FALHOS_PACMAN
declare -a PACOTES_FALHOS_AUR
declare -a PACOTES_NAO_ENCONTRADOS

# Função para exibir uma linha de separação
separator() {
    log "\n${YELLOW}------------------------------------------------------${NC}"
}

# --- FUNÇÃO: Verificar se pacote está instalado (pacman) ---
is_pacman_installed() {
    local pkg="$1"
    if pacman -Qi "$pkg" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# --- FUNÇÃO: Verificar se pacote AUR está instalado ---
is_aur_installed() {
    local pkg="$1"
    if command -v yay &> /dev/null && yay -Qi "$pkg" &> /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# --- FUNÇÃO: Pausa para confirmação do usuário com tratamento de erro ---
confirmar_proxima_etapa() {
    local proxima_acao="$1"
    local status_anterior=$2

    if [ "$status_anterior" -ne 0 ]; then
        error_log "\n${YELLOW}A etapa anterior encontrou um erro. Status: $status_anterior${NC}"
        while true; do
            read -p "Deseja ignorar este erro e continuar para a ${proxima_acao}? (s/N): " resposta
            resposta=${resposta:-N}
            case $resposta in
                [Ss]* ) log "${YELLOW}Continuando, mas o sistema pode ficar em um estado inconsistente.${NC}"; return 0;;
                [Nn]* ) error_log "\n${RED}Operação abortada pelo usuário devido a erro anterior.${NC}"; exit 1;;
                * ) echo "Resposta inválida. Por favor, digite 's' para sim ou 'N' para não.";;
            esac
        done
    fi

    log "\n${GREEN}Etapa anterior concluída com êxito.${NC}"

    while true; do
        read -p "Deseja prosseguir para a ${proxima_acao}? (S/n): " resposta
        resposta=${resposta:-S}
        case $resposta in
            [Ss]* ) return 0;;
            [Nn]* ) log "\n${RED}Operação abortada pelo usuário.${NC}"; exit 0;;
            * ) echo "Resposta inválida. Por favor, digite 'S' para sim ou 'n' para não.";;
        esac
    done
}

# --- FUNÇÃO: instala pacotes pacman um a um (fallback quando o lote falha) ---
instalar_pacman_individualmente() {
    local pacotes=("$@")
    for pkg in "${pacotes[@]}"; do
        log "   Tentando instalar individualmente: $pkg"
        sudo pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>> "$ERROR_LOG"
        if [ $? -eq 0 ] && is_pacman_installed "$pkg"; then
            PACOTES_INSTALADOS["$pkg"]=1
            log "   ${GREEN}✓ $pkg instalado${NC}"
        else
            PACOTES_FALHOS_PACMAN+=("$pkg")
            error_log "   ${RED}✗ $pkg falhou${NC}"
            if ! pacman -Sp "$pkg" &> /dev/null; then
                error_log "     └─ Motivo: pacote não encontrado no repositório"
                PACOTES_NAO_ENCONTRADOS+=("$pkg")
            else
                error_log "     └─ Motivo: erro de dependência ou conflito"
            fi
        fi
    done
}

# --- 0. Preparação e Atualização do Sistema ---
separator
log "${GREEN}--- 0. Preparando o Sistema e Atualizando ---${NC}"
log "Será solicitada sua senha para instalar pacotes essenciais e atualizar o sistema."

# Verificar se é Arch Linux
if ! grep -qi "arch" /etc/os-release; then
    error_log "${RED}ERRO: Este script foi feito para Arch Linux!${NC}"
    exit 1
fi

sudo pacman -S --needed git base-devel --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    error_log "${RED}ERRO: Falha ao instalar git e base-devel${NC}"
    exit 1
fi

sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG"
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
    error_log "\n${RED}--- ERRO CRÍTICO ---${NC}"
    error_log "${RED}Falha ao atualizar o sistema.${NC}"
    error_log "${YELLOW}Verifique os erros acima no log${NC}"
    exit 1
fi
confirmar_proxima_etapa "verificação de usuário" $INSTALL_STATUS

# --- 1. Determinar o usuário atual ---
separator
log "${GREEN}--- 1. Verificação de Usuário e Diretórios ---${NC}"
USUARIO=$(whoami)
if [ "$USUARIO" == "root" ]; then
    error_log "${RED}ERRO: Por favor, execute este script como seu usuário normal, não como root.${NC}"
    exit 1
fi
log "${GREEN}Usuário detectado: $USUARIO${NC}"

# --- 2. Instalação do 'yay' (AUR helper) ---
separator
log "${GREEN}--- 2. Instalando o 'yay' (AUR Helper) ---${NC}"

if command -v yay &> /dev/null; then
    log "${GREEN}yay já está instalado. Pulando...${NC}"
    INSTALL_STATUS=0
else
    cd /tmp/ || { error_log "${RED}Erro: Não foi possível mudar para /tmp/${NC}"; exit 1; }
    rm -rf yay

    if git clone https://aur.archlinux.org/yay >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        cd yay || { error_log "${RED}Erro: Não foi possível mudar para /tmp/yay/${NC}"; cd "$SCRIPT_DIR"; exit 1; }
        log "Compilando e instalando o yay..."
        makepkg -si --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG"
        INSTALL_STATUS=$?
        if [ $INSTALL_STATUS -eq 0 ]; then
            log "${GREEN}yay instalado com sucesso!${NC}"
            cd /tmp && rm -rf yay
        else
            error_log "\n${RED}--- ERRO NA INSTALAÇÃO ---${NC}"
            error_log "${RED}Falha ao compilar/instalar o yay${NC}"
        fi
    else
        error_log "\n${RED}--- ERRO DE DOWNLOAD ---${NC}"
        error_log "${RED}Falha ao clonar o repositório do yay${NC}"
        error_log "${YELLOW}Verifique sua conexão com a internet${NC}"
        INSTALL_STATUS=1
    fi
    # Sempre volta para o diretório original do script
    cd "$SCRIPT_DIR" || cd "$HOME"
fi
confirmar_proxima_etapa "instalação de pacotes" $INSTALL_STATUS

# --- 3. Instalação de Pacotes (pacman e AUR) com verificação de já instalados ---
separator
log "${GREEN}--- 3. Instalação de Pacotes (Otimizada) ---${NC}"

# Lista completa de pacotes
PACOTES_PACMAN=(
    hyprland
    hyprpaper
    hyprlock
    hypridle
    hyprcursor
    hyprpicker
    waybar
    kitty
    rofi-wayland
    dunst
    cliphist
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    xdg-user-dirs
    dolphin
    dolphin-plugins
    ark
    kio-admin
    polkit-kde-agent
    kate
    kde-cli-tools
    breeze
    breeze-gtk
    papirus-icon-theme
    qt5-wayland
    qt6-wayland
    qt5ct
    qt6ct
    ttf-font-awesome
    ttf-jetbrains-mono-nerd
    ttf-opensans
    ttf-dejavu
    noto-fonts
    ttf-roboto
    pipewire
    pipewire-pulse
    pipewire-jack
    pipewire-alsa
    wireplumber
    pavucontrol
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    ffmpeg
    mpv
    nano
    archlinux-xdg-menu
    hyprshot
    blueman
    bluez
    bluez-utils
    networkmanager
    brightnessctl
)

PACOTES_AUR=(
    nwg-look
    visual-studio-code-bin
    qview
    wlogout
)

# Verificar pacotes já instalados
log "${YELLOW}Verificando pacotes já instalados...${NC}"
PACOTES_PARA_INSTALAR_PACMAN=()
PACOTES_PARA_INSTALAR_AUR=()

for pkg in "${PACOTES_PACMAN[@]}"; do
    if is_pacman_installed "$pkg"; then
        PACOTES_JA_INSTALADOS["$pkg"]=1
        log "${GREEN}✓ $pkg (já instalado)${NC}"
    else
        PACOTES_PARA_INSTALAR_PACMAN+=("$pkg")
        PACOTES_NECESSARIOS["$pkg"]=1
    fi
done

for pkg in "${PACOTES_AUR[@]}"; do
    if is_aur_installed "$pkg"; then
        PACOTES_JA_INSTALADOS["$pkg"]=1
        log "${GREEN}✓ $pkg (já instalado - AUR)${NC}"
    else
        PACOTES_PARA_INSTALAR_AUR+=("$pkg")
        PACOTES_NECESSARIOS["$pkg"]=1
    fi
done

# Instalar pacotes faltantes do pacman
if [ ${#PACOTES_PARA_INSTALAR_PACMAN[@]} -gt 0 ]; then
    log "\n${YELLOW}Instalando pacotes do pacman (${#PACOTES_PARA_INSTALAR_PACMAN[@]} pacotes)...${NC}"

    sudo pacman -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_PACMAN[@]}" >> "$LOG_FILE" 2>> "$ERROR_LOG"
    INSTALL_STATUS=$?

    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_PACMAN[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes pacman instalados com sucesso!${NC}"
    else
        error_log "\n${RED}--- ERRO NA INSTALAÇÃO EM LOTE (PACMAN) ---${NC}"
        error_log "${YELLOW}O pacman aborta o lote inteiro se um pacote falhar. Tentando instalar um a um...${NC}"
        instalar_pacman_individualmente "${PACOTES_PARA_INSTALAR_PACMAN[@]}"
    fi
else
    log "${GREEN}Todos os pacotes pacman já estão instalados!${NC}"
fi

# Instalar pacotes faltantes do AUR
if [ ${#PACOTES_PARA_INSTALAR_AUR[@]} -gt 0 ]; then
    log "\n${YELLOW}Instalando pacotes do AUR (${#PACOTES_PARA_INSTALAR_AUR[@]} pacotes)...${NC}"

    yay -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_AUR[@]}" >> "$LOG_FILE" 2>> "$ERROR_LOG"
    INSTALL_STATUS=$?

    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes AUR instalados com sucesso!${NC}"
    else
        error_log "\n${RED}--- ERRO NA INSTALAÇÃO DE PACOTES AUR ---${NC}"
        error_log "${YELLOW}Tentando instalar pacotes AUR um a um...${NC}"
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            log "   Tentando instalar individualmente (AUR): $pkg"
            yay -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>> "$ERROR_LOG"
            if [ $? -eq 0 ] && is_aur_installed "$pkg"; then
                PACOTES_INSTALADOS["$pkg"]=1
                log "   ${GREEN}✓ $pkg instalado${NC}"
            else
                PACOTES_FALHOS_AUR+=("$pkg")
                error_log "   ${RED}✗ $pkg falhou (compilação ou dependências)${NC}"
            fi
        done
    fi
else
    log "${GREEN}Todos os pacotes AUR já estão instalados!${NC}"
fi

# --- 4. Configuração de Diretórios XDG ---
separator
log "${GREEN}--- 4. Configuração de Diretórios XDG ---${NC}"

mkdir -p "$HOME/.local/bin"

# Script de correção XDG: não força mais nomes de pasta em português.
# xdg-user-dirs-update --force já usa os nomes corretos do locale do sistema.
cat > "$HOME/.local/bin/fix-xdg-dirs.sh" << 'EOF'
#!/bin/bash
xdg-user-dirs-update --force 2>/dev/null
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    sed -i '/XDG_TEMPLATES_DIR/d' "$HOME/.config/user-dirs.dirs"
    sed -i '/XDG_PUBLICSHARE_DIR/d' "$HOME/.config/user-dirs.dirs"
fi
if command -v kbuildsycoca6 &> /dev/null; then
    XDG_MENU_PREFIX=arch- kbuildsycoca6 2>/dev/null || kbuildsycoca6 2>/dev/null
fi
EOF

chmod +x "$HOME/.local/bin/fix-xdg-dirs.sh"
log "${GREEN}✓ Script de correção XDG criado (usa nomes de pasta do locale do sistema)${NC}"

log "Executando correção XDG..."
~/.local/bin/fix-xdg-dirs.sh

if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "fix-xdg-dirs.sh" "$HOME/.bashrc"; then
        echo -e "\n# Correção XDG para Dolphin\n[ -f ~/.local/bin/fix-xdg-dirs.sh ] && ~/.local/bin/fix-xdg-dirs.sh &> /dev/null &" >> "$HOME/.bashrc"
        log "${GREEN}✓ Adicionado ao .bashrc${NC}"
    fi
fi

if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q "fix-xdg-dirs.sh" "$HOME/.zshrc"; then
        echo -e "\n# Correção XDG para Dolphin\n[ -f ~/.local/bin/fix-xdg-dirs.sh ] && ~/.local/bin/fix-xdg-dirs.sh &> /dev/null &" >> "$HOME/.zshrc"
        log "${GREEN}✓ Adicionado ao .zshrc${NC}"
    fi
fi

# --- 5. Ativação de Serviços ---
separator
log "${GREEN}--- 5. Ativando Serviços Necessários ---${NC}"

declare -A SERVICOS_ATIVADOS
declare -A SERVICOS_FALHOS

# NetworkManager (serviço de sistema)
if command -v NetworkManager &> /dev/null || is_pacman_installed networkmanager; then
    log "Ativando NetworkManager (sistema)..."
    if sudo systemctl enable --now NetworkManager >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        SERVICOS_ATIVADOS["NetworkManager"]=1
        log "${GREEN}✓ NetworkManager ativado e iniciado${NC}"
    else
        SERVICOS_FALHOS["NetworkManager"]=1
        error_log "${RED}✗ Falha ao ativar NetworkManager${NC}"
    fi
fi

# Bluetooth (serviço de sistema)
if is_pacman_installed bluez; then
    log "Ativando serviço Bluetooth (sistema)..."
    if sudo systemctl enable --now bluetooth >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        SERVICOS_ATIVADOS["bluetooth"]=1
        log "${GREEN}✓ Bluetooth ativado e iniciado${NC}"
    else
        SERVICOS_FALHOS["bluetooth"]=1
        error_log "${RED}✗ Falha ao ativar Bluetooth${NC}"
    fi
fi

# Serviços de usuário (Pipewire/Wireplumber - áudio)
log "Ativando serviços de áudio (usuário: pipewire, pipewire-pulse, wireplumber)..."
for servico in pipewire pipewire-pulse wireplumber; do
    if systemctl --user enable --now "$servico" >> "$LOG_FILE" 2>> "$ERROR_LOG"; then
        SERVICOS_ATIVADOS["$servico"]=1
        log "${GREEN}✓ $servico ativado (usuário)${NC}"
    else
        SERVICOS_FALHOS["$servico"]=1
        error_log "${RED}✗ Falha ao ativar $servico${NC}"
    fi
done

# Polkit agent (necessário para diálogos de permissão no Hyprland)
if is_pacman_installed polkit-kde-agent; then
    log "${YELLOW}ℹ polkit-kde-agent instalado. Adicione 'exec-once = /usr/lib/polkit-kde-authentication-agent-1' ao seu hyprland.conf para que ele inicie com a sessão.${NC}"
fi

# --- 6. Relatório Final ---
separator
log "\n${GREEN}======================================================${NC}"
log "${GREEN}✔️ Instalação e Configuração Concluídas!${NC}"
log "${GREEN}======================================================${NC}"

log "\n${BLUE}📦 RESUMO DE PACOTES:${NC}"
log "   Já instalados antes:   ${#PACOTES_JA_INSTALADOS[@]}"
log "   Instalados agora:      ${#PACOTES_INSTALADOS[@]}"
log "   Total necessário:      ${#PACOTES_NECESSARIOS[@]}"
log "   Falharam:              $((${#PACOTES_FALHOS_PACMAN[@]} + ${#PACOTES_FALHOS_AUR[@]}))"

log "\n${BLUE}🔧 RESUMO DE SERVIÇOS:${NC}"
log "   Ativados com sucesso:  ${#SERVICOS_ATIVADOS[@]}"
log "   Falharam:              ${#SERVICOS_FALHOS[@]}"

# Listar pacotes já instalados (ordenados corretamente também no arquivo)
if [ ${#PACOTES_JA_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}✅ Pacotes que já estavam instalados:${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${!PACOTES_JA_INSTALADOS[@]}" | sort)
    while IFS= read -r pkg; do
        log "   • $pkg"
    done <<< "$LISTA_ORDENADA"
fi

# Listar pacotes instalados agora
if [ ${#PACOTES_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}📥 Pacotes instalados agora:${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${!PACOTES_INSTALADOS[@]}" | sort)
    while IFS= read -r pkg; do
        log "   • $pkg"
    done <<< "$LISTA_ORDENADA"
fi

# Listar serviços ativados
if [ ${#SERVICOS_ATIVADOS[@]} -gt 0 ]; then
    log "\n${GREEN}🟢 Serviços ativados:${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${!SERVICOS_ATIVADOS[@]}" | sort)
    while IFS= read -r srv; do
        log "   • $srv"
    done <<< "$LISTA_ORDENADA"
fi

# Listar serviços que falharam
if [ ${#SERVICOS_FALHOS[@]} -gt 0 ]; then
    log "\n${RED}🔴 Serviços que falharam:${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${!SERVICOS_FALHOS[@]}" | sort)
    while IFS= read -r srv; do
        log "   • $srv"
    done <<< "$LISTA_ORDENADA"
fi

# Listar pacotes que falharam (PACMAN)
if [ ${#PACOTES_FALHOS_PACMAN[@]} -gt 0 ]; then
    log "\n${RED}❌ Pacotes que falharam (pacman):${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${PACOTES_FALHOS_PACMAN[@]}" | sort)
    while IFS= read -r pkg; do
        log "   • $pkg"
    done <<< "$LISTA_ORDENADA"
fi

# Listar pacotes que falharam (AUR)
if [ ${#PACOTES_FALHOS_AUR[@]} -gt 0 ]; then
    log "\n${RED}❌ Pacotes que falharam (AUR):${NC}"
    LISTA_ORDENADA=$(printf '%s\n' "${PACOTES_FALHOS_AUR[@]}" | sort)
    while IFS= read -r pkg; do
        log "   • $pkg"
    done <<< "$LISTA_ORDENADA"
fi

# Mostrar local do log de erro detalhado
if [ -s "$ERROR_LOG" ]; then
    log "\n${YELLOW}⚠️  Erros detectados durante a execução!${NC}"
    log "${YELLOW}   Log detalhado de erros: $ERROR_LOG${NC}"
fi

log "\n${BLUE}🎯 PRÓXIMOS PASSOS:${NC}"
log "1. ${RED}REINICIE SEU SISTEMA${NC}"
log "2. Configure o Hyprland em ~/.config/hypr/hyprland.conf"
log "3. Configure temas com nwg-look (GTK) e qt5ct/qt6ct (QT)"
log "4. Se usar polkit-kde-agent, adicione a linha exec-once indicada acima ao hyprland.conf"

log "\n${BLUE}🔧 CORREÇÃO DE PASTAS XDG:${NC}"
log "   • Para executar manualmente: ${GREEN}~/.local/bin/fix-xdg-dirs.sh${NC}"
log "   • A correção roda automaticamente no login (via .bashrc/.zshrc)"

log "\n${BLUE}📝 ARQUIVOS DE LOG (TXT):${NC}"
log "   • Log completo: ${GREEN}$LOG_FILE${NC}"
log "   • Log de erros: ${GREEN}$ERROR_LOG${NC}"

log "\n${GREEN}✅ Script finalizado!${NC}\n"
