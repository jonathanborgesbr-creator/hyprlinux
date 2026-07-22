#!/bin/bash

Segurança básica

set -u

=========================

CORES

=========================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

=========================

LOGS

=========================

LOG_FILE="$HOME/hyprland_install.txt"
ERROR_LOG="$HOME/hyprland_install_erros.txt"

SCRIPT_DIR="$(pwd)"

Inicializar logs

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

log() {
echo -e "$1"
echo -e "$1" | sed -E 's/\x1B[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE"
}

error_log() {
echo -e "$1"
echo -e "$1" | sed -E 's/\x1B[[0-9;]*[a-zA-Z]//g' >> "$ERROR_LOG"
}

separator() {
log "\n${YELLOW}------------------------------------------------------${NC}"
}

=========================

FUNÇÕES

=========================

is_pacman_installed() {
pacman -Qi "$1" &> /dev/null
}

is_aur_installed() {
pacman -Qm "$1" &> /dev/null
}

confirmar_proxima_etapa() {
local acao="$1"
local status="$2"

if [ "$status" -ne 0 ]; then
    error_log "Erro antes de: $acao"
    while true; do
        read -p "Continuar mesmo assim? (s/N): " r
        r=${r:-N}
        case $r in
            [Ss]*) return 0 ;;
            [Nn]*) exit 1 ;;
            *) echo "Digite s ou N" ;;
        esac
    done
fi

log "${GREEN}OK → $acao${NC}"

}

check_internet() {
ping -c 1 archlinux.org &> /dev/null || {
error_log "Sem internet!"
exit 1
}
}

=========================

SISTEMA

=========================

separator
log "${GREEN}--- Preparando sistema ---${NC}"

source /etc/os-release
if [[ "$ID" != "arch" ]]; then
error_log "Este script é apenas para Arch Linux"
exit 1
fi

check_internet

sudo pacman -S --needed git base-devel --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG" || exit 1
sudo pacman -Syu --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG" || exit 1

confirmar_proxima_etapa "usuário" $?

=========================

USUÁRIO

=========================

separator
USUARIO=$(whoami)

if [ "$USUARIO" == "root" ]; then
error_log "Não execute como root"
exit 1
fi

=========================

YAY

=========================

separator
log "${GREEN}--- Instalando yay ---${NC}"

if ! command -v yay &> /dev/null; then
cd /tmp || exit 1
rm -rf yay

git clone https://aur.archlinux.org/yay >> "$LOG_FILE" 2>> "$ERROR_LOG" || exit 1
cd yay || exit 1

makepkg -si --noconfirm >> "$LOG_FILE" 2>> "$ERROR_LOG"
INSTALL_STATUS=$?

cd "$SCRIPT_DIR" || cd "$HOME"

confirmar_proxima_etapa "pacotes" $INSTALL_STATUS

fi

=========================

PACOTES

=========================

separator
log "${GREEN}--- Instalando pacotes ---${NC}"

PACOTES_PACMAN=(
archlinux-xdg-menu
ark
breeze
breeze5
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
mpv
networkmanager
noto-fonts
papirus-icon-theme
pavucontrol
polkit-kde-agent
qt5-wayland
qt6-wayland
rofi-wayland
ttf-dejavu
ttf-font-awesome
ttf-jetbrains-mono-nerd
ttf-opensans
ttf-roboto
waybar
xdg-desktop-portal-gtk
xdg-desktop-portal-hyprland
xdg-user-dirs
)

PACOTES_AUR=(
visual-studio-code-bin
qview
wlogout
qt5ct-kde
qt6ct-kde
)

PACOTES_PARA_INSTALAR_PACMAN=()
PACOTES_PARA_INSTALAR_AUR=()

for pkg in "${PACOTES_PACMAN[@]}"; do
is_pacman_installed "$pkg" || PACOTES_PARA_INSTALAR_PACMAN+=("$pkg")
done

for pkg in "${PACOTES_AUR[@]}"; do
is_aur_installed "$pkg" || PACOTES_PARA_INSTALAR_AUR+=("$pkg")
done

PACMAN

if [ ${#PACOTES_PARA_INSTALAR_PACMAN[@]} -gt 0 ]; then
sudo pacman -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_PACMAN[@]}" 
>> "$LOG_FILE" 2>> "$ERROR_LOG"
fi

AUR

if [ ${#PACOTES_PARA_INSTALAR_AUR[@]} -gt 0 ]; then
yay -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_AUR[@]}" 
>> "$LOG_FILE" 2>> "$ERROR_LOG"
fi

=========================

XDG

=========================

separator
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/fix-xdg-dirs.sh" << 'EOF'
#!/bin/bash
xdg-user-dirs-update --force
EOF

chmod +x "$HOME/.local/bin/fix-xdg-dirs.sh"

~/.local/bin/fix-xdg-dirs.sh

=========================

SERVIÇOS

=========================

separator

sudo systemctl enable --now NetworkManager >> "$LOG_FILE" 2>> "$ERROR_LOG"

if pacman -Qi bluez &> /dev/null; then
sudo systemctl enable --now bluetooth >> "$LOG_FILE" 2>> "$ERROR_LOG"
fi

for s in pipewire pipewire-pulse wireplumber; do
systemctl --user enable --now "$s" >> "$LOG_FILE" 2>> "$ERROR_LOG"
done

=========================

FINAL

=========================

separator

log "${GREEN}✔ INSTALAÇÃO FINALIZADA${NC}"
log "Reinicie o sistema!"
