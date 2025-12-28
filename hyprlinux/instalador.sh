#!/bin/bash

# Define cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(pwd)"

separator() {
    echo -e "\n${YELLOW}------------------------------------------------------${NC}"
}

confirmar_proxima_etapa() {
    local proxima_acao="$1"
    local status_anterior=$2
    if [ "$status_anterior" -ne 0 ]; then
        echo -e "\n${YELLOW}A etapa anterior falhou. Deseja ignorar e continuar para ${proxima_acao}? (s/N)${NC}"
        read -p "> " resposta
        [[ "$resposta" =~ ^[Ss]$ ]] || exit 1
    fi
    return 0
}

# --- 0. Preparação e Headers ---
separator
echo -e "${GREEN}--- 0. Sincronizando e Reconstruindo Kernel ---${NC}"
sudo pacman -Syy --needed git base-devel linux-headers power-profiles-daemon && sudo pacman -Syu
sudo mkinitcpio -P 
confirmar_proxima_etapa "verificação de usuário" $?

# --- 1. Verificação de Usuário ---
USUARIO=$(whoami)
HOME_DESTINO="$HOME"
CONFIG_ORIGEM="$SCRIPT_DIR/.config" 

# --- 2. Instalando o 'yay' (AUR Helper) ---
separator
echo -e "${GREEN}--- 2. Instalando o 'yay' ---${NC}"
if ! command -v yay &> /dev/null; then
    cd /tmp/ && rm -rf yay
    git clone https://aur.archlinux.org/yay && cd yay && makepkg -si --noconfirm
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}Yay já está instalado. Pulando...${NC}"
fi
confirmar_proxima_etapa "pacotes principais" $?

# --- 3. Instalação de Pacotes via Pacman ---
separator
echo -e "${GREEN}--- 3. Instalando Pacotes Base (Pacman) ---${NC}"

# LOTE 1 - Interface e Core
BATCH1=( hyprland sddm hyprlock hypridle hyprcursor hyprpaper hyprpicker waybar kitty rofi-wayland dunst cliphist xdg-desktop-portal-hyprland xdg-desktop-portal-gtk nano xdg-user-dirs archlinux-xdg-menu )

# LOTE 2 - Temas e Utilidades
BATCH2=( ttf-font-awesome ttf-jetbrains-mono-nerd ttf-opensans ttf-dejavu noto-fonts ttf-roboto breeze breeze5 breeze-gtk papirus-icon-theme kde-cli-tools kate gparted gamescope gamemode networkmanager network-manager-applet )

# LOTE 3 - ÁUDIO, ARQUIVOS E BLUETOOTH (Blueman adicionado aqui)
BATCH3=( pipewire pipewire-pulse pipewire-jack pipewire-alsa wireplumber gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly ffmpeg mpv pavucontrol blueman dolphin dolphin-plugins ark kio-admin polkit-kde-agent qt5-wayland qt6-wayland )

sudo pacman -S --needed "${BATCH1[@]}" "${BATCH2[@]}" "${BATCH3[@]}" --noconfirm

# --- 4. Drivers NVIDIA (DKMS) ---
separator
echo -e "${GREEN}--- 4. Instalando NVIDIA (DKMS) ---${NC}"
if lspci | grep -Ei 'vga|3d|display' | grep -i nvidia > /dev/null; then
    sudo pacman -S --needed nvidia-dkms nvidia-utils nvidia-settings lib32-nvidia-utils egl-wayland libva-nvidia-driver --noconfirm
    
    echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P 

    if [ -f /etc/default/grub ]; then
        if ! grep -q "nvidia_drm.modeset=1" /etc/default/grub; then
            sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/ s/"/ nvidia_drm.modeset=1"/' /etc/default/grub
            sudo grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi
fi

# --- 5. Pacotes AUR (Yay) ---
separator
echo -e "${GREEN}--- 5. Instalando Pacotes do AUR ---${NC}"
# Blueberry removido daqui
YAY_PKGS=( hyprshot wlogout qview visual-studio-code-bin nwg-look qt5ct-kde qt6ct-kde heroic-games-launcher sddm-astronaut-theme-git )
yay -S --needed "${YAY_PKGS[@]}" --noconfirm

# Configurando o tema do SDDM
sudo mkdir -p /etc/sddm.conf.d/
echo -e "[Theme]\nCurrent=sddm-astronaut-theme" | sudo tee /etc/sddm.conf.d/theme.conf

# --- 6. Finalização e Configurações ---
separator
echo -e "${GREEN}--- 6. Aplicando Configurações de Usuário ---${NC}"
xdg-user-dirs-update --force

if [ -d "$CONFIG_ORIGEM" ]; then
    echo -e "${YELLOW}Copiando arquivos de configuração para ~/.config...${NC}"
    mkdir -p "$HOME_DESTINO/.config"
    \cp -rf "$CONFIG_ORIGEM"/. "$HOME_DESTINO/.config/"
else
    echo -e "${RED}Aviso: Pasta $CONFIG_ORIGEM não encontrada. Pulando cópia de dotfiles.${NC}"
fi

# Variáveis Electron para Hyprland
echo "env = ELECTRON_OZONE_PLATFORM_HINT,auto" >> "$HOME_DESTINO/.config/hypr/hyprland.conf"
echo "env = NVD_BACKEND,direct" >> "$HOME_DESTINO/.config/hypr/hyprland.conf"

chown -R "$USUARIO:$USUARIO" "$HOME_DESTINO/.config"
sudo localectl set-x11-keymap br abnt2

# --- 7. Serviços ---
separator
echo -e "${GREEN}--- 7. Habilitando Serviços ---${NC}"
sudo systemctl enable --now sddm
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now power-profiles-daemon
systemctl --user enable --now wireplumber

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✔️ INSTALAÇÃO CONCLUÍDA!${NC}"
echo -e "${YELLOW}Blueman (Bluetooth) instalado via repositório oficial.${NC}"
echo -e "${GREEN}======================================================${NC}"
