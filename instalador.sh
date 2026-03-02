#!/bin/bash

# Define cores para o terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Impede rodar como root diretamente para não quebrar permissões da Home
if [ "$EUID" -eq 0 ]; then 
  echo -e "${RED}Por favor, não rode este script como root/sudo diretamente.${NC}"
  echo "O script solicitará senha de administrador quando necessário."
  exit 1
fi

SCRIPT_DIR="$(pwd)"
USUARIO=$(whoami)
HOME_DESTINO="$HOME"
# Caminho da pasta .config dentro da pasta hyprlinux do seu repositório
CONFIG_ORIGEM="$SCRIPT_DIR/hyprlinux/.config" 

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

# --- 0. Preparação Inicial ---
separator
echo -e "${GREEN}--- 0. Atualizando Repositórios e Base ---${NC}"
sudo pacman -Syy --needed git base-devel linux-headers power-profiles-daemon --noconfirm
sudo pacman -Syu --noconfirm

# --- 1. AUR Helper (Yay) ---
separator
echo -e "${GREEN}--- 1. Instalando o 'yay' ---${NC}"
if ! command -v yay &> /dev/null; then
    cd /tmp/ && rm -rf yay
    git clone https://aur.archlinux.org/yay && cd yay && makepkg -si --noconfirm
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}Yay já está instalado.${NC}"
fi

# --- 2. Instalação de Pacotes via Pacman ---
separator
echo -e "${GREEN}--- 2. Instalando Pacotes do Sistema ---${NC}"

# Interface, Fontes, Áudio e Dolphin
PKGS=(
    hyprland hyprlock hypridle hyprcursor hyprpaper hyprpicker waybar kitty 
    rofi-wayland dunst cliphist xdg-desktop-portal-hyprland xdg-desktop-portal-gtk 
    nano xdg-user-dirs archlinux-xdg-menu ttf-font-awesome ttf-jetbrains-mono-nerd 
    ttf-opensans ttf-dejavu noto-fonts ttf-roboto breeze breeze5 breeze-gtk 
    papirus-icon-theme kde-cli-tools kate pipewire pipewire-pulse pipewire-jack 
    pipewire-alsa wireplumber gstreamer gst-plugins-base gst-plugins-good 
    gst-plugins-bad gst-plugins-ugly ffmpeg mpv pavucontrol dolphin 
    dolphin-plugins ark kio-admin polkit-kde-agent qt5-wayland qt6-wayland
)

sudo pacman -S --needed "${PKGS[@]}" --noconfirm

# --- 3. Drivers NVIDIA (Ordem Técnica Corrigida) ---
separator
echo -e "${GREEN}--- 3. Configurando NVIDIA (Early KMS) ---${NC}"
if lspci | grep -Ei 'vga|3d|display' | grep -i nvidia > /dev/null; then
    # 1. Instala pacotes
    sudo pacman -S --needed nvidia-dkms nvidia-utils nvidia-settings lib32-nvidia-utils --noconfirm
    
    # 2. Configura Modprobe
    echo "options nvidia_drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf
    
    # 3. Adiciona módulos ao Initramfs (necessário para o Hyprland carregar na NVIDIA sem erros)
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    
    # 4. Parâmetros de Kernel no GRUB
    if [ -f /etc/default/grub ]; then
        if ! grep -q "nvidia_drm.modeset=1" /etc/default/grub; then
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1 nvidia_drm.fbdev=1 /' /etc/default/grub
            sudo grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi

    # 5. Reconstroi o Kernel (Agora com todas as configs acima inclusas)
    echo -e "${YELLOW}Gerando nova imagem do Kernel...${NC}"
    sudo mkinitcpio -P 
fi

# --- 4. Pacotes AUR ---
separator
echo -e "${GREEN}--- 4. Instalando Pacotes AUR ---${NC}"
YAY_PKGS=( hyprshot wlogout qview visual-studio-code-bin nwg-look qt5ct-kde qt6ct-kde ) 
yay -S --needed "${YAY_PKGS[@]}" --noconfirm

# --- 5. Dolphin e Dotfiles ---
separator
echo -e "${GREEN}--- 5. Configurando Diretórios e Dotfiles ---${NC}"

# Cria pastas padrão (Downloads, Documentos, etc) no Dolphin
xdg-user-dirs-update --force

# Cópia da pasta .config do seu repositório
if [ -d "$CONFIG_ORIGEM" ]; then
    echo -e "${YELLOW}Copiando configs de $CONFIG_ORIGEM para ~/.config...${NC}"
    mkdir -p "$HOME_DESTINO/.config"
    cp -r "$CONFIG_ORIGEM"/* "$HOME_DESTINO/.config/"
else
    echo -e "${RED}Erro: Pasta $CONFIG_ORIGEM não encontrada no repositório.${NC}"
fi

# Variáveis de Ambiente para NVIDIA no Hyprland
HYPR_CONF="$HOME_DESTINO/.config/hypr/hyprland.conf"
if [ -f "$HYPR_CONF" ]; then
    if ! grep -q "ELECTRON_OZONE_PLATFORM_HINT" "$HYPR_CONF"; then
        echo -e "\n# Fix para NVIDIA e Electron" >> "$HYPR_CONF"
        echo "env = ELECTRON_OZONE_PLATFORM_HINT,auto" >> "$HYPR_CONF"
        echo "env = NVD_BACKEND,direct" >> "$HYPR_CONF"
        echo "env = WLR_NO_HARDWARE_CURSORS,1" >> "$HYPR_CONF"
    fi
fi

# --- 6. Auto-start Hyprland (TTY1) ---
separator
echo -e "${GREEN}--- 6. Configurando Login Automático no TTY1 ---${NC}"
BASH_PROFILE="$HOME_DESTINO/.bash_profile"

if [ ! -f "$BASH_PROFILE" ]; then touch "$BASH_PROFILE"; fi

if ! grep -q "exec Hyprland" "$BASH_PROFILE"; then
    cat <<EOF >> "$BASH_PROFILE"

# Iniciar Hyprland automaticamente no login do TTY1
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    exec Hyprland
fi
EOF
    echo -e "${YELLOW}Auto-start configurado no .bash_profile.${NC}"
fi

# --- 7. Ajustes Finais ---
separator
echo -e "${GREEN}--- 7. Finalizando ---${NC}"
sudo localectl set-x11-keymap br abnt2
systemctl --user enable --now wireplumber
chown -R "$USUARIO:$USUARIO" "$HOME_DESTINO"

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✔️ INSTALAÇÃO COMPLETA!${NC}"
echo -e "${YELLOW}Reinicie o sistema e faça login no terminal para entrar no Hyprland.${NC}"
echo -e "${GREEN}======================================================${NC}"