#!/bin/bash

# Define cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="$HOME/hyprland_install_report.txt"
SCRIPT_DIR="$(pwd)"

{
    echo "=========================================="
    echo " INSTALAÇÃO HYPRLAND (OTIMIZADA) - RELATÓRIO"
    echo " Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')"
    echo " Usuário: $(whoami)"
    echo "=========================================="
    echo ""
} > "$LOG_FILE"

log() {
    echo -e "$1"
    echo -e "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE"
}

declare -a PACOTES_JA_INSTALADOS
declare -a PACOTES_INSTALADOS
declare -a PACOTES_NAO_INSTALADOS
declare -a SERVICOS_ATIVADOS
declare -a SERVICOS_FALHOS

separator() {
    log "\n${YELLOW}------------------------------------------------------${NC}"
}

is_pacman_installed() {
    pacman -Qi "$1" &> /dev/null
}

is_aur_installed() {
    pacman -Qm "$1" &> /dev/null
}

confirmar_proxima_etapa() {
    local proxima_acao="$1"
    local status_anterior=$2

    if [ "$status_anterior" -ne 0 ]; then
        log "${RED}Etapa anterior falhou (status $status_anterior) antes de: ${proxima_acao}.${NC}"
        while true; do
            read -p "Deseja ignorar este erro e continuar para a ${proxima_acao}? (s/N): " resposta
            resposta=${resposta:-N}
            case $resposta in
                [Ss]* ) log "${YELLOW}Continuando por decisão do usuário.${NC}"; return 0;;
                [Nn]* ) log "${RED}Operação abortada.${NC}"; exit 1;;
                * ) echo "Resposta inválida. Digite 's' ou 'N'.";;
            esac
        done
    fi
    log "${GREEN}Etapa anterior concluída com êxito. Prosseguindo para: ${proxima_acao}${NC}"
    return 0
}

# --- 0. Validação de Ambiente ---
separator
log "${GREEN}--- 0. Validando Ambiente (Arch Linux) ---${NC}"

if ! grep -qi "arch" /etc/os-release; then
    log "${RED}ERRO: Este script foi feito para Arch Linux!${NC}"
    exit 1
fi

if [ "$(whoami)" == "root" ]; then
    log "${RED}ERRO: Execute este script como seu usuário normal, não como root.${NC}"
    exit 1
fi

# --- 1. Atualização e Ferramentas Base ---
separator
log "${GREEN}--- 1. Atualizando Sistema e Instalando Ferramentas Base ---${NC}"

sudo pacman -S --needed git base-devel pciutils flatpak --noconfirm >> "$LOG_FILE" 2>&1
sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1
INSTALL_STATUS=$?
confirmar_proxima_etapa "Verificação de Hardware Gráfico" $INSTALL_STATUS

# --- 2. Verificação de Hardware Gráfico (NVIDIA) ---
separator
log "${GREEN}--- 2. Verificando Hardware Gráfico (NVIDIA) ---${NC}"

TEM_NVIDIA=false
if lspci | grep -i nvidia &> /dev/null; then
    TEM_NVIDIA=true
    log "${GREEN}✓ GPU NVIDIA detectada! Instalando drivers otimizados.${NC}"
else
    log "${YELLOW}ℹ Nenhuma GPU NVIDIA detectada neste dispositivo. Pulando drivers gráficos.${NC}"
fi

if [ "$TEM_NVIDIA" = true ]; then
    if ! grep -q "\[multilib\]" /etc/pacman.conf; then
        log "Habilitando repositório multilib..."
        echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >> "$LOG_FILE" 2>&1
        sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1
    fi

    PACOTES_NVIDIA=(nvidia nvidia-utils lib32-nvidia-utils nvidia-settings)
    for pkg in "${PACOTES_NVIDIA[@]}"; do
        if is_pacman_installed "$pkg"; then
            PACOTES_JA_INSTALADOS+=("$pkg")
        else
            log "Instalando driver NVIDIA: $pkg..."
            if sudo pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1; then
                PACOTES_INSTALADOS+=("$pkg")
            else
                PACOTES_NAO_INSTALADOS+=("$pkg (Pacman)")
            fi
        fi
    done
fi

# --- 3. Configuração do AUR Helper (yay-bin) ---
separator
log "${GREEN}--- 3. Configurando AUR Helper (yay-bin) ---${NC}"

if command -v yay &> /dev/null; then
    log "${GREEN}yay já está instalado. Pulando...${NC}"
    INSTALL_STATUS=0
else
    cd /tmp/ || exit 1
    rm -rf yay-bin
    if git clone https://aur.archlinux.org/yay-bin.git &>> "$LOG_FILE"; then
        cd yay-bin || exit 1
        makepkg -si --noconfirm >> "$LOG_FILE" 2>&1
        INSTALL_STATUS=$?
        cd /tmp && rm -rf yay-bin
    else
        INSTALL_STATUS=1
    fi
    cd "$SCRIPT_DIR" || cd "$HOME"
fi
confirmar_proxima_etapa "Instalação de Pacotes Oficiais" $INSTALL_STATUS

# --- 4. Instalação de Pacotes Oficiais (Pacman) ---
separator
log "${GREEN}--- 4. Instalando Pacotes do Repositório Oficial ---${NC}"

PACOTES_PACMAN=(
    archlinux-xdg-menu ark breeze breeze5 breeze-gtk blueman brightnessctl bluez bluez-utils
    cliphist dolphin dolphin-plugins dunst gst-plugins-bad gst-plugins-base gst-plugins-good
    gst-plugins-ugly hyprcursor hypridle hyprland hyprlock hyprpaper hyprpicker hyprshot
    kate kde-cli-tools kio-admin kitty mpv networkmanager noto-fonts papirus-icon-theme
    pavucontrol qt5-wayland qt6-wayland rofi-wayland ttf-dejavu
    ttf-font-awesome ttf-jetbrains-mono-nerd ttf-opensans ttf-roboto waybar
    xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-user-dirs
)

for pkg in "${PACOTES_PACMAN[@]}"; do
    if is_pacman_installed "$pkg"; then
        PACOTES_JA_INSTALADOS+=("$pkg")
    else
        log "Instalando: $pkg..."
        if sudo pacman -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1; then
            PACOTES_INSTALADOS+=("$pkg")
        else
            PACOTES_NAO_INSTALADOS+=("$pkg (Pacman)")
        fi
    fi
done

# --- 5. Instalação de Pacotes do AUR ---
separator
log "${GREEN}--- 5. Instalando Pacotes do AUR ---${NC}"

PACOTES_AUR=(
    qview wlogout qt5ct-kde qt6ct-kde auto-cpufreq hyprpolkitagent
)

for pkg in "${PACOTES_AUR[@]}"; do
    if is_aur_installed "$pkg"; then
        PACOTES_JA_INSTALADOS+=("$pkg")
    else
        log "Instalando via AUR: $pkg..."
        if yay -S --needed --noconfirm "$pkg" >> "$LOG_FILE" 2>&1; then
            PACOTES_INSTALADOS+=("$pkg")
        else
            PACOTES_NAO_INSTALADOS+=("$pkg (AUR)")
        fi
    fi
done

# --- 6. Aplicativos via Flatpak (VS Code) ---
separator
log "${GREEN}--- 6. Configurando Flathub e Instalando VS Code ---${NC}"

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOG_FILE" 2>&1
if flatpak info com.visualstudio.code &> /dev/null; then
    PACOTES_JA_INSTALADOS+=("visual-studio-code (Flatpak)")
else
    log "Instalando Visual Studio Code via Flatpak..."
    if flatpak install flathub com.visualstudio.code -y >> "$LOG_FILE" 2>&1; then
        PACOTES_INSTALADOS+=("visual-studio-code (Flatpak)")
    else
        PACOTES_NAO_INSTALADOS+=("visual-studio-code (Flatpak)")
    fi
fi

sudo systemctl daemon-reload

# --- 7. Configuração de Diretórios XDG ---
separator
log "${GREEN}--- 7. Configurando Diretórios XDG ---${NC}"
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/fix-xdg-dirs.sh" << 'EOF'
#!/bin/bash
xdg-user-dirs-update --force 2>/dev/null
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    sed -i '/XDG_TEMPLATES_DIR/d' "$HOME/.config/user-dirs.dirs"
    sed -i '/XDG_PUBLICSHARE_DIR/d' "$HOME/.config/user-dirs.dirs"
fi
EOF
chmod +x "$HOME/.local/bin/fix-xdg-dirs.sh"
~/.local/bin/fix-xdg-dirs.sh

# --- 8. Ativação de Serviços do Systemd ---
separator
log "${GREEN}--- 8. Ativando Serviços do Systemd ---${NC}"

for srv in NetworkManager bluetooth auto-cpufreq; do
    log "Ativando serviço de sistema: $srv..."
    if sudo systemctl enable --now "$srv" >> "$LOG_FILE" 2>&1; then
        SERVICOS_ATIVADOS+=("$srv")
    else
        SERVICOS_FALHOS+=("$srv")
    fi
done

for srv in pipewire pipewire-pulse wireplumber; do
    log "Ativando serviço de usuário: $srv..."
    if systemctl --user enable --now "$srv" >> "$LOG_FILE" 2>&1; then
        SERVICOS_ATIVADOS+=("$srv (user)")
    else
        SERVICOS_FALHOS+=("$srv (user)")
    fi
done

# --- 9. Configuração do Hyprland (Lua) ---
separator
log "${GREEN}--- 9. Configurando Ambiente Hyprland (Lua) ---${NC}"
HYPR_DIR="$HOME/.config/hypr"
HYPR_LUA="$HYPR_DIR/hyprland.lua"
mkdir -p "$HYPR_DIR"

if [ ! -f "$HYPR_LUA" ]; then
    cat > "$HYPR_LUA" << 'EOF'
local hl = require("hyprland")
hl.exec_once({
    "systemctl --user start hyprpolkitagent",
    "blueman-applet"
})
EOF
    log "${GREEN}✓ hyprland.lua criado com sucesso.${NC}"
else
    sed -i '/polkit-kde-authentication-agent-1/d' "$HYPR_LUA"
    if ! grep -q "hyprpolkitagent" "$HYPR_LUA"; then
        echo -e "\nif require(\"hyprland\").exec_once then\n    require(\"hyprland\").exec_once({\"systemctl --user start hyprpolkitagent\", \"blueman-applet\"})\nend" >> "$HYPR_LUA"
        log "${GREEN}✓ Inicializações injetadas no hyprland.lua.${NC}"
    else
        log "${YELLOW}ℹ Inicializações já mapeadas no hyprland.lua.${NC}"
    fi
fi

# --- 10. Relatório Final Único ---
separator
log "\n${GREEN}======================================================${NC}"
log "${GREEN}✔️ INSTALAÇÃO CONCLUÍDA! RELATÓRIO DE PACOTES:${NC}"
log "${GREEN}======================================================${NC}"

log "\n${GREEN}📥 PACOTES INSTALADOS NESTA SESSÃO:${NC}"
if [ ${#PACOTES_INSTALADOS[@]} -eq 0 ]; then log "   (Nenhum)"; else
    for pkg in "${PACOTES_INSTALADOS[@]}"; do log "   • $pkg"; done
fi

log "\n${BLUE}✅ PACOTES QUE JÁ ESTAVAM INSTALADOS:${NC}"
if [ ${#PACOTES_JA_INSTALADOS[@]} -eq 0 ]; then log "   (Nenhum)"; else
    for pkg in "${PACOTES_JA_INSTALADOS[@]}"; do log "   • $pkg"; done
fi

log "\n${RED}❌ PACOTES NÃO INSTALADOS / FALHOU:${NC}"
if [ ${#PACOTES_NAO_INSTALADOS[@]} -eq 0 ]; then log "   (Nenhum)"; else
    for pkg in "${PACOTES_NAO_INSTALADOS[@]}"; do log "   • $pkg"; done
fi

log "\n${GREEN}🟢 SERVIÇOS DO SYSTEMD ATIVADOS COM SUCESSO:${NC}"
if [ ${#SERVICOS_ATIVADOS[@]} -eq 0 ]; then log "   (Nenhum)"; else
    for srv in "${SERVICOS_ATIVADOS[@]}"; do log "   • $srv"; done
fi

log "\n${RED}🔴 SERVIÇOS DO SYSTEMD QUE FALHARAM:${NC}"
if [ ${#SERVICOS_FALHOS[@]} -eq 0 ]; then log "   (Nenhum)"; else
    for srv in "${SERVICOS_FALHOS[@]}"; do log "   • $srv"; done
fi

log "\n${BLUE}📝 RELATÓRIO TÉCNICO COMPLETO:${NC}"
log "   • Caminho: ${GREEN}$LOG_FILE${NC}\n"
