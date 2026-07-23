#!/bin/bash

# Define cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arquivo único de log (Gera um relatório completo do início ao fim)
LOG_FILE="$HOME/hyprland_install_report.txt"
SCRIPT_DIR="$(pwd)"

# Limpar log anterior e escrever cabeçalho
{
    echo "=========================================="
    echo " INSTALAÇÃO HYPRLAND - RELATÓRIO ÚNICO"
    echo " Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')"
    echo " Usuário: $(whoami)"
    echo "=========================================="
    echo ""
} > "$LOG_FILE"

# Função para logging (Exibe colorido na tela, salva a saída técnica no arquivo)
log() {
    echo -e "$1"
    echo -e "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE"
}

# Arrays para rastrear pacotes e serviços
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

# --- 0. Preparação e Atualização do Sistema ---
separator
log "${GREEN}--- 0. Preparando o Sistema e Atualizando ---${NC}"

if ! grep -qi "arch" /etc/os-release; then
    log "${RED}ERRO: Este script foi feito para Arch Linux!${NC}"
    exit 1
fi

USUARIO=$(whoami)
if [ "$USUARIO" == "root" ]; then
    log "${RED}ERRO: Execute este script como seu usuário normal, não como root.${NC}"
    exit 1
fi

# Redirecionamento 2>&1 garante que erros cruciais do pacman fiquem registrados no arquivo de log único
sudo pacman -S --needed git base-devel --noconfirm >> "$LOG_FILE" 2>&1
sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>&1
INSTALL_STATUS=$?
confirmar_proxima_etapa "Instalação do AUR Helper" $INSTALL_STATUS

# --- 1. Instalação do 'yay' ---
separator
log "${GREEN}--- 1. Instalando o 'yay' (AUR Helper) ---${NC}"

if command -v yay &> /dev/null; then
    log "${GREEN}yay já está instalado. Pulando...${NC}"
    INSTALL_STATUS=0
else
    cd /tmp/ || exit 1
    rm -rf yay
    if git clone https://aur.archlinux.org/yay &>> "$LOG_FILE"; then
        cd yay || exit 1
        makepkg -si --noconfirm >> "$LOG_FILE" 2>&1
        INSTALL_STATUS=$?
        cd /tmp && rm -rf yay
    else
        INSTALL_STATUS=1
    fi
    cd "$SCRIPT_DIR" || cd "$HOME"
fi
confirmar_proxima_etapa "Instalação de Pacotes" $INSTALL_STATUS

# --- 2. Instalação de Pacotes ---
separator
log "${GREEN}--- 2. Instalação de Pacotes ---${NC}"

PACOTES_PACMAN=(
    archlinux-xdg-menu ark breeze breeze5 breeze-gtk blueman brightnessctl bluez bluez-utils
    cliphist dolphin dolphin-plugins dunst gst-plugins-bad gst-plugins-base gst-plugins-good
    gst-plugins-ugly hyprcursor hypridle hyprland hyprlock hyprpaper hyprpicker hyprshot
    kate kde-cli-tools kio-admin kitty mpv networkmanager noto-fonts papirus-icon-theme
    pavucontrol qt5-wayland qt6-wayland rofi-wayland ttf-dejavu
    ttf-font-awesome ttf-jetbrains-mono-nerd ttf-opensans ttf-roboto waybar
    xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-user-dirs
)

# Adicionado hyprpolkitagent no AUR substituindo o polkit-kde antigo
PACOTES_AUR=(
    visual-studio-code-bin qview wlogout qt5ct-kde qt6ct-kde auto-cpufreq hyprpolkitagent
)

# Processando Repositórios Oficiais (Pacman)
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

# Processando AUR (Yay)
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

# Atualizar os daemons do Systemd para reconhecer novos serviços (como o auto-cpufreq)
sudo systemctl daemon-reload

# --- 3. Configuração de Diretórios XDG ---
separator
log "${GREEN}--- 3. Configuração de Diretórios XDG ---${NC}"
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

# --- 4. Ativação de Serviços e Inicializações Necessárias ---
separator
log "${GREEN}--- 4. Ativando Serviços e Configurando Inicializações (Lua) ---${NC}"

# Systemd (Serviços a Nível de Sistema - Adicionado auto-cpufreq)
for srv in NetworkManager bluetooth auto-cpufreq; do
    log "Ativando serviço de sistema: $srv..."
    if sudo systemctl enable --now "$srv" >> "$LOG_FILE" 2>&1; then
        SERVICOS_ATIVADOS+=("$srv")
    else
        SERVICOS_FALHOS+=("$srv")
    fi
done

# Systemd (Serviços a Nível de Usuário - Áudio)
for srv in pipewire pipewire-pulse wireplumber; do
    log "Ativando serviço de usuário: $srv..."
    if systemctl --user enable --now "$srv" >> "$LOG_FILE" 2>&1; then
        SERVICOS_ATIVADOS+=("$srv (user)")
    else
        SERVICOS_FALHOS+=("$srv (user)")
    fi
done

# --- Configuração do Arquivo de Inicialização do Hyprland (Transição para LUA) ---
HYPR_DIR="$HOME/.config/hypr"
HYPR_LUA="$HYPR_DIR/hyprland.lua"
mkdir -p "$HYPR_DIR"

log "Configurando inicializações automáticas no seu hyprland.lua..."

if [ ! -f "$HYPR_LUA" ]; then
    # Se o arquivo não existir, cria um arquivo básico estruturado na sintaxe Lua correta
    cat > "$HYPR_LUA" << 'EOF'
-- Configuração do Hyprland em Lua
local hl = require("hyprland")

-- Inicializações automáticas executadas uma vez (exec-once)
hl.exec_once({
    "systemctl --user start hyprpolkitagent",
    "blueman-applet"
})
EOF
    log "${GREEN}✓ Arquivo hyprland.lua criado com as inicializações ativadas.${NC}"
else
    # Se o arquivo já existe, limpa traços da chamada antiga em texto/conf antigo se houver
    sed -i '/polkit-kde-authentication-agent-1/d' "$HYPR_LUA"

    # Injeta a chamada segura respeitando a API do Lua do Hyprland
    if ! grep -q "hyprpolkitagent" "$HYPR_LUA"; then
        echo -e "\n-- Injetado automaticamente pelo script de instalação\nif require(\"hyprland\").exec_once then\n    require(\"hyprland\").exec_once({\"systemctl --user start hyprpolkitagent\", \"blueman-applet\"})\nend" >> "$HYPR_LUA"
        log "${GREEN}✓ Inicializações automáticas injetadas em sintaxe Lua no final do hyprland.lua.${NC}"
    else
        log "${YELLOW}ℹ Inicializações automáticas já mapeadas no seu hyprland.lua.${NC}"
    fi
fi

# --- 5. Relatório Final Único ---
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

log "\n${BLUE}📝 RELATÓRIO TÉCNICO COMPLETO (Logs e outputs internos de erro):${NC}"
log "   • Caminho: ${GREEN}$LOG_FILE${NC}\n"
