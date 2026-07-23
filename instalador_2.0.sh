#!/bin/bash

# Define cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 0. Verificação Inicial de Segurança ---
USUARIO=$(whoami)
if [ "$USUARIO" == "root" ]; then
    echo -e "${RED}ERRO: Por favor, execute este script como seu usuário normal, não como root.${NC}"
    exit 1
fi

# Arquivo único de log para pacotes
LOG_PACOTES="$HOME/status_pacotes.txt"

# Diretório original de onde o script foi chamado
SCRIPT_DIR="$(pwd)"

# Limpar log anterior e escrever cabeçalho
{
    echo "=========================================="
    echo " RELATÓRIO DE PACOTES HYPRLAND"
    echo " Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')"
    echo " Usuário: $USUARIO"
    echo "=========================================="
    echo ""
} > "$LOG_PACOTES"

# Função auxiliar para exibir na tela
log_tela() {
    echo -e "$1"
}

# Arrays para rastrear pacotes
declare -a PACOTES_JA_INSTALADOS
declare -a PACOTES_INSTALADOS_AGORA
declare -a PACOTES_FALHOS

# Função para exibir uma linha de separação
separator() {
    log_tela "\n${YELLOW}------------------------------------------------------${NC}"
}

# --- FUNÇÃO: Verificar se pacote está instalado ---
is_installed() {
    local pkg="$1"
    pacman -Qi "$pkg" &> /dev/null
}

# --- FUNÇÃO: Pausa para confirmação em caso de erro grave ---
confirmar_proxima_etapa() {
    local proxima_acao="$1"
    local status_anterior=$2

    if [ "$status_anterior" -ne 0 ]; then
        log_tela "${RED}Etapa anterior falhou (status $status_anterior).${NC}"
        while true; do
            read -p "Deseja ignorar este erro e continuar para a ${proxima_acao}? (s/N): " resposta
            resposta=${resposta:-N}
            case $resposta in
                [Ss]* ) log_tela "${YELLOW}Continuando...${NC}"; return 0;;
                [Nn]* ) log_tela "${RED}Operação abortada pelo usuário.${NC}"; exit 1;;
                * ) echo "Resposta inválida. Digite 's' ou 'N'.";;
            esac
        done
    fi
    return 0
}

# --- FUNÇÃO: instala pacotes pacman um a um ---
instalar_pacman_individualmente() {
    local pacotes=("$@")
    for pkg in "${pacotes[@]}"; do
        log_tela "   Tentando instalar individualmente: $pkg"
        sudo pacman -S --needed --noconfirm "$pkg" &> /dev/null
        if [ $? -eq 0 ] && is_installed "$pkg"; then
            PACOTES_INSTALADOS_AGORA+=("$pkg")
            log_tela "   ${GREEN}✓ $pkg instalado${NC}"
        else
            PACOTES_FALHOS+=("$pkg (Pacman)")
            log_tela "   ${RED}✗ $pkg falhou${NC}"
        fi
    done
}

# --- 1. Preparação e Atualização do Sistema ---
separator
log_tela "${GREEN}--- 1. Preparando o Sistema e Atualizando ---${NC}"
log_tela "Será solicitada sua senha para instalar pacotes essenciais e atualizar o sistema."

if ! grep -qi "arch" /etc/os-release; then
    log_tela "${RED}ERRO: Este script foi feito para Arch Linux!${NC}"
    exit 1
fi

sudo pacman -S --needed git base-devel --noconfirm &> /dev/null
if [ $? -ne 0 ]; then
    log_tela "${RED}ERRO: Falha ao instalar git e base-devel${NC}"
    exit 1
fi

sudo pacman -Syu --noconfirm &> /dev/null
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
    log_tela "${RED}ERRO: Falha ao atualizar o sistema.${NC}"
    exit 1
fi
confirmar_proxima_etapa "instalação do AUR Helper (yay)" $INSTALL_STATUS

# --- 2. Instalação do 'yay' (AUR helper) ---
separator
log_tela "${GREEN}--- 2. Instalando o 'yay' (AUR Helper) ---${NC}"

if command -v yay &> /dev/null; then
    log_tela "${GREEN}yay já está instalado. Pulando...${NC}"
    INSTALL_STATUS=0
else
    cd /tmp/ || exit 1
    rm -rf yay

    if git clone https://aur.archlinux.org/yay &> /dev/null; then
        cd yay || { cd "$SCRIPT_DIR"; exit 1; }
        log_tela "Compilando e instalando o yay..."
        makepkg -si --noconfirm &> /dev/null
        INSTALL_STATUS=$?
        if [ $INSTALL_STATUS -eq 0 ]; then
            log_tela "${GREEN}yay instalado com sucesso!${NC}"
            cd /tmp && rm -rf yay
        else
            log_tela "${RED}ERRO: Falha ao compilar/instalar o yay.${NC}"
        fi
    else
        log_tela "${RED}ERRO: Falha ao clonar o repositório do yay.${NC}"
        INSTALL_STATUS=1
    fi
    cd "$SCRIPT_DIR" || cd "$HOME"
fi
confirmar_proxima_etapa "instalação de pacotes" $INSTALL_STATUS

# --- 3. Instalação de Pacotes ---
separator
log_tela "${GREEN}--- 3. Instalação de Pacotes ---${NC}"

PACOTES_PACMAN=(
    archlinux-xdg-menu
    ark
    blueman
    bluez
    bluez-utils
    breeze
    breeze-gtk
    brightnessctl
    cliphist
    dolphin
    dolphin-plugins
    dunst
    gst-plugins-bad
    gst-plugins-base
    gst-plugins-good
    gst-plugins-ugly
    hyprcursor
    hypridle
    hyprland
    hyprlock
    hyprpaper
    hyprpicker
    hyprshot
    kate
    kde-cli-tools
    kio-admin
    kitty
    mission-center
    mpv
    networkmanager
    noto-fonts
    nwg-look
    papirus-icon-theme
    pavucontrol
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    polkit-kde-agent
    qt5-wayland
    qt5ct
    qt6-wayland
    qt6ct
    rofi-wayland
    ttf-dejavu
    ttf-font-awesome
    ttf-jetbrains-mono-nerd
    ttf-opensans
    ttf-roboto
    waybar
    wireplumber
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-user-dirs
)

PACOTES_AUR=(
    auto-cpufreq
    qview
    visual-studio-code-bin
    wlogout
)

log_tela "${YELLOW}Verificando pacotes já instalados...${NC}"
PACOTES_PARA_INSTALAR_PACMAN=()
PACOTES_PARA_INSTALAR_AUR=()

for pkg in "${PACOTES_PACMAN[@]}"; do
    if is_installed "$pkg"; then
        PACOTES_JA_INSTALADOS+=("$pkg")
        log_tela "${GREEN}✓ $pkg (já instalado)${NC}"
    else
        PACOTES_PARA_INSTALAR_PACMAN+=("$pkg")
    fi
done

for pkg in "${PACOTES_AUR[@]}"; do
    if is_installed "$pkg"; then
        PACOTES_JA_INSTALADOS+=("$pkg (AUR)")
        log_tela "${GREEN}✓ $pkg (já instalado - AUR)${NC}"
    else
        PACOTES_PARA_INSTALAR_AUR+=("$pkg")
    fi
done

# Instalar pacotes pacman
if [ ${#PACOTES_PARA_INSTALAR_PACMAN[@]} -gt 0 ]; then
    log_tela "\n${YELLOW}Instalando pacotes do pacman (${#PACOTES_PARA_INSTALAR_PACMAN[@]} pacotes)...${NC}"

    sudo pacman -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_PACMAN[@]}" &> /dev/null
    INSTALL_STATUS=$?

    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_PACMAN[@]}"; do
            PACOTES_INSTALADOS_AGORA+=("$pkg")
        done
        log_tela "${GREEN}Pacotes pacman instalados com sucesso!${NC}"
    else
        log_tela "${YELLOW}Falha em lote. Tentando instalar um a um...${NC}"
        instalar_pacman_individualmente "${PACOTES_PARA_INSTALAR_PACMAN[@]}"
    fi
else
    log_tela "${GREEN}Todos os pacotes pacman já estão instalados!${NC}"
fi

# Instalar pacotes AUR
if [ ${#PACOTES_PARA_INSTALAR_AUR[@]} -gt 0 ]; then
    log_tela "\n${YELLOW}Instalando pacotes do AUR (${#PACOTES_PARA_INSTALAR_AUR[@]} pacotes)...${NC}"

    yay -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_AUR[@]}" &> /dev/null
    INSTALL_STATUS=$?

    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            PACOTES_INSTALADOS_AGORA+=("$pkg (AUR)")
        done
        log_tela "${GREEN}Pacotes AUR instalados com sucesso!${NC}"
    else
        log_tela "${YELLOW}Tentando instalar pacotes AUR um a um...${NC}"
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            log_tela "   Tentando instalar individualmente (AUR): $pkg"
            yay -S --needed --noconfirm "$pkg" &> /dev/null
            if [ $? -eq 0 ] && is_installed "$pkg"; then
                PACOTES_INSTALADOS_AGORA+=("$pkg (AUR)")
                log_tela "   ${GREEN}✓ $pkg instalado${NC}"
            else
                PACOTES_FALHOS+=("$pkg (AUR)")
                log_tela "   ${RED}✗ $pkg falhou${NC}"
            fi
        done
    fi
else
    log_tela "${GREEN}Todos os pacotes AUR já estão instalados!${NC}"
fi

# --- 4. Configuração de Diretórios XDG ---
separator
log_tela "${GREEN}--- 4. Configuração de Diretórios XDG ---${NC}"

mkdir -p "$HOME/.local/bin"

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
~/.local/bin/fix-xdg-dirs.sh

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rcfile" ] && ! grep -q "fix-xdg-dirs.sh" "$rcfile"; then
        echo -e "\n# Correção XDG para Dolphin\n[ -f ~/.local/bin/fix-xdg-dirs.sh ] && ~/.local/bin/fix-xdg-dirs.sh &> /dev/null &" >> "$rcfile"
    fi
done

# --- 5. Ativação de Serviços ---
separator
log_tela "${GREEN}--- 5. Ativando Serviços Necessários ---${NC}"

command -v NetworkManager &> /dev/null && sudo systemctl enable --now NetworkManager &> /dev/null
is_installed bluez && sudo systemctl enable --now bluetooth &> /dev/null
is_installed auto-cpufreq && sudo systemctl enable --now auto-cpufreq &> /dev/null

for servico in pipewire pipewire-pulse wireplumber; do
    systemctl --user enable --now "$servico" &> /dev/null
done

# --- 6. GERAÇÃO DO LOG ÚNICO E RELATÓRIO FINAL ---
{
    echo "--- 1. PACOTES JÁ INSTALADOS ANTES (${#PACOTES_JA_INSTALADOS[@]}) ---"
    if [ ${#PACOTES_JA_INSTALADOS[@]} -gt 0 ]; then
        printf '%s\n' "${PACOTES_JA_INSTALADOS[@]}" | sort | sed 's/^/  • /'
    else
        echo "  Nenhum."
    fi
    echo ""

    echo "--- 2. PACOTES INSTALADOS AGORA (${#PACOTES_INSTALADOS_AGORA[@]}) ---"
    if [ ${#PACOTES_INSTALADOS_AGORA[@]} -gt 0 ]; then
        printf '%s\n' "${PACOTES_INSTALADOS_AGORA[@]}" | sort | sed 's/^/  • /'
    else
        echo "  Nenhum."
    fi
    echo ""

    echo "--- 3. PACOTES QUE NÃO FORAM INSTALADOS / FALHARAM (${#PACOTES_FALHOS[@]}) ---"
    if [ ${#PACOTES_FALHOS[@]} -gt 0 ]; then
        printf '%s\n' "${PACOTES_FALHOS[@]}" | sort | sed 's/^/  • /'
    else
        echo "  Nenhuma falha registrada! Todos os pacotes foram instalados com sucesso."
    fi
} >> "$LOG_PACOTES"

separator
log_tela "\n${GREEN}======================================================${NC}"
log_tela "${GREEN}✔️ Instalação e Configuração Concluídas!${NC}"
log_tela "${GREEN}======================================================${NC}"

log_tela "\n${BLUE}📦 RESUMO DE PACOTES:${NC}"
log_tela "   Já instalados antes:   ${#PACOTES_JA_INSTALADOS[@]}"
log_tela "   Instalados agora:      ${#PACOTES_INSTALADOS_AGORA[@]}"
log_tela "   Não instalados/Falhas: ${#PACOTES_FALHOS[@]}"

log_tela "\n${BLUE}📝 LOG DE PACOTES GERADO:${NC}"
log_tela "   • Arquivo: ${GREEN}$LOG_PACOTES${NC}"

log_tela "\n${GREEN}✅ Script finalizado!${NC}\n"
