#!/bin/bash

# Define cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arquivo de log
LOG_FILE="$HOME/hyprland_install.log"
ERROR_LOG="$HOME/hyprland_install_error.log"

# Limpar logs anteriores
> "$LOG_FILE"
> "$ERROR_LOG"

# Função para logging
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "$1" | tee -a "$ERROR_LOG"
}

# Arrays para rastrear pacotes
declare -A PACOTES_JA_INSTALADOS
declare -A PACOTES_NECESSARIOS
declare -A PACOTES_INSTALADOS
declare -a PACOTES_FALHOS_PACMAN
declare -a PACOTES_FALHOS_AUR
declare -a PACOTES_NAO_ENCONTRADOS

# Salva o diretório de trabalho original do script
SCRIPT_DIR="$(pwd)"

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

# --- 0. Preparação e Atualização do Sistema ---
separator
log "${GREEN}--- 0. Preparando o Sistema e Atualizando ---${NC}"
log "Será solicitada sua senha para instalar pacotes essenciais e atualizar o sistema."

# Verificar se é Arch Linux
if ! grep -qi "arch" /etc/os-release; then
    error_log "${RED}ERRO: Este script foi feito para Arch Linux!${NC}"
    exit 1
fi

sudo pacman -S --needed git base-devel --noconfirm 2>> "$ERROR_LOG"
if [ $? -ne 0 ]; then
    error_log "${RED}ERRO: Falha ao instalar git e base-devel${NC}"
    exit 1
fi

sudo pacman -Syu --noconfirm 2>> "$ERROR_LOG"
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
    error_log "\n${RED}--- ERRO CRÍTICO ---${NC}"
    error_log "${RED}Falha ao atualizar o sistema.${NC}"
    error_log "${YELLOW}Verifique os erros acima no log${NC}"
    exit 1
fi
confirmar_proxima_etapa "verificação de usuário" $INSTALL_STATUS

# --- 1. Determinar o usuário atual e Variáveis de Diretório ---
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

    if git clone https://aur.archlinux.org/yay 2>> "$ERROR_LOG"; then
        cd yay || { error_log "${RED}Erro: Não foi possível mudar para /tmp/yay/${NC}"; exit 1; }
        log "Compilando e instalando o yay..."
        makepkg -si --noconfirm 2>> "$ERROR_LOG"
        INSTALL_STATUS=$?
        if [ $INSTALL_STATUS -eq 0 ]; then
            log "${GREEN}yay instalado com sucesso!${NC}"
            cd .. && rm -rf yay
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
    wlogout
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
    qview
    nano
    archlinux-xdg-menu
    hyprshot
)

PACOTES_AUR=(
    nwg-look
    visual-studio-code-bin
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
    
    # Tentativa de instalação
    sudo pacman -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_PACMAN[@]}" 2>> "$ERROR_LOG"
    INSTALL_STATUS=$?
    
    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_PACMAN[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes pacman instalados com sucesso!${NC}"
    else
        error_log "\n${RED}--- ERRO NA INSTALAÇÃO DE PACOTES PACMAN ---${NC}"
        error_log "${RED}Falha ao instalar alguns pacotes. Status: $INSTALL_STATUS${NC}"
        
        # Identificar quais pacotes falharam
        error_log "\n${YELLOW}Verificando pacotes que falharam...${NC}"
        for pkg in "${PACOTES_PARA_INSTALAR_PACMAN[@]}"; do
            if ! is_pacman_installed "$pkg"; then
                PACOTES_FALHOS_PACMAN+=("$pkg")
                error_log "${RED}✗ $pkg - NÃO INSTALADO${NC}"
                
                # Tentar identificar o motivo
                if ! pacman -Sp "$pkg" &> /dev/null; then
                    error_log "  └─ Motivo: Pacote não encontrado no repositório"
                    PACOTES_NAO_ENCONTRADOS+=("$pkg")
                else
                    error_log "  └─ Motivo: Erro de dependência ou conflito"
                fi
            fi
        done
    fi
else
    log "${GREEN}Todos os pacotes pacman já estão instalados!${NC}"
fi

# Instalar pacotes faltantes do AUR
if [ ${#PACOTES_PARA_INSTALAR_AUR[@]} -gt 0 ]; then
    log "\n${YELLOW}Instalando pacotes do AUR (${#PACOTES_PARA_INSTALAR_AUR[@]} pacotes)...${NC}"
    
    yay -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_AUR[@]}" 2>> "$ERROR_LOG"
    INSTALL_STATUS=$?
    
    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes AUR instalados com sucesso!${NC}"
    else
        error_log "\n${RED}--- ERRO NA INSTALAÇÃO DE PACOTES AUR ---${NC}"
        error_log "${RED}Falha ao instalar alguns pacotes AUR. Status: $INSTALL_STATUS${NC}"
        
        # Identificar quais pacotes AUR falharam
        error_log "\n${YELLOW}Verificando pacotes AUR que falharam...${NC}"
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            if ! is_aur_installed "$pkg"; then
                PACOTES_FALHOS_AUR+=("$pkg")
                error_log "${RED}✗ $pkg - NÃO INSTALADO (AUR)${NC}"
                error_log "  └─ Motivo: Falha na compilação ou dependências"
            fi
        done
    fi
else
    log "${GREEN}Todos os pacotes AUR já estão instalados!${NC}"
fi

# --- 4. Configuração de Diretórios XDG ---
separator
log "${GREEN}--- 4. Configuração de Diretórios XDG ---${NC}"

# Criar script de correção XDG (sem systemd para evitar travamento)
log "${YELLOW}Criando script de correção XDG...${NC}"

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/fix-xdg-dirs.sh" << 'EOF'
#!/bin/bash
xdg-user-dirs-update --force 2>/dev/null
xdg-user-dirs-update --set DESKTOP "$HOME/Área de Trabalho" 2>/dev/null
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    sed -i '/XDG_TEMPLATES_DIR/d' "$HOME/.config/user-dirs.dirs"
    sed -i '/XDG_PUBLICSHARE_DIR/d' "$HOME/.config/user-dirs.dirs"
fi
for pasta in "Área de Trabalho" "Documentos" "Downloads" "Música" "Imagens" "Vídeos"; do
    [ ! -d "$HOME/$pasta" ] && mkdir -p "$HOME/$pasta"
done
if command -v kbuildsycoca6 &> /dev/null; then
    XDG_MENU_PREFIX=arch- kbuildsycoca6 2>/dev/null || kbuildsycoca6 2>/dev/null
fi
EOF

chmod +x "$HOME/.local/bin/fix-xdg-dirs.sh"
log "${GREEN}✓ Script de correção XDG criado${NC}"

# Executar correção imediatamente
log "Executando correção XDG..."
~/.local/bin/fix-xdg-dirs.sh

# Adicionar ao .bashrc ou .zshrc
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

# --- 5. Relatório Final ---
separator
log "\n${GREEN}======================================================${NC}"
log "${GREEN}✔️ Instalação e Configuração Concluídas!${NC}"
log "${GREEN}======================================================${NC}"

# Mostrar estatísticas de pacotes
log "\n${BLUE}📦 RELATÓRIO DE PACOTES:${NC}"
log "   ✓ Pacotes já instalados: ${#PACOTES_JA_INSTALADOS[@]}"
log "   ✓ Pacotes instalados agora: ${#PACOTES_INSTALADOS[@]}"
log "   ✓ Total de pacotes úteis: ${#PACOTES_NECESSARIOS[@]}"
log "   ✗ Pacotes com falha: $((${#PACOTES_FALHOS_PACMAN[@]} + ${#PACOTES_FALHOS_AUR[@]}))"

# Listar pacotes já instalados
if [ ${#PACOTES_JA_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}✅ Pacotes que já estavam instalados:${NC}"
    for pkg in "${!PACOTES_JA_INSTALADOS[@]}"; do
        log "   • $pkg"
    done | sort
fi

# Listar pacotes instalados agora
if [ ${#PACOTES_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}📥 Pacotes instalados agora:${NC}"
    for pkg in "${!PACOTES_INSTALADOS[@]}"; do
        log "   • $pkg"
    done | sort
fi

# Listar pacotes que falharam (PACMAN)
if [ ${#PACOTES_FALHOS_PACMAN[@]} -gt 0 ]; then
    log "\n${RED}❌ PACOTES QUE FALHARAM (PACMAN):${NC}"
    for pkg in "${PACOTES_FALHOS_PACMAN[@]}"; do
        log "   • $pkg"
    done | sort
fi

# Listar pacotes que falharam (AUR)
if [ ${#PACOTES_FALHOS_AUR[@]} -gt 0 ]; then
    log "\n${RED}❌ PACOTES QUE FALHARAM (AUR):${NC}"
    for pkg in "${PACOTES_FALHOS_AUR[@]}"; do
        log "   • $pkg"
    done | sort
fi

# Mostrar local do log de erro detalhado
if [ -s "$ERROR_LOG" ]; then
    log "\n${YELLOW}⚠️  Erros detectados durante a execução!${NC}"
    log "${YELLOW}   Log detalhado de erros: $ERROR_LOG${NC}"
    log "\n${BLUE}--- ÚLTIMOS ERROS REGISTRADOS ---${NC}"
    tail -20 "$ERROR_LOG" | while read line; do
        log "   $line"
    done
fi

log "\n${BLUE}🎯 PRÓXIMOS PASSOS:${NC}"
log "1. ${RED}REINICIE SEU SISTEMA${NC}"
log "2. Configure o Hyprland em ~/.config/hypr/hyprland.conf"
log "3. Configure temas com nwg-look (GTK) e qt5ct/qt6ct (QT)"

log "\n${BLUE}🔧 CORREÇÃO DE PASTAS XDG:${NC}"
log "   • Para executar manualmente: ${GREEN}~/.local/bin/fix-xdg-dirs.sh${NC}"
log "   • A correção roda automaticamente no login (via .bashrc/.zshrc)"

log "\n${BLUE}📝 COMANDOS PARA DIAGNÓSTICO:${NC}"
log "   • Ver log de erros: ${GREEN}cat $ERROR_LOG${NC}"
log "   • Ver log completo: ${GREEN}cat $LOG_FILE${NC}"
log "   • Instalar pacotes falhos manualmente: ${GREEN}yay -S <pacote>${NC}"

log "\n${GREEN}✅ Script finalizado! Logs salvos em:${NC}"
log "   • $LOG_FILE"
log "   • $ERROR_LOG\n"