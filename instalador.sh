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

# Função para logging
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "$1" | tee -a "$ERROR_LOG"
}

# Salva o diretório de trabalho original do script
SCRIPT_DIR="$(pwd)"

# Arrays para rastrear pacotes
declare -A PACOTES_JA_INSTALADOS
declare -A PACOTES_NECESSARIOS
declare -A PACOTES_INSTALADOS

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
    if yay -Qi "$pkg" &> /dev/null 2>&1; then
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

sudo pacman -S --needed git base-devel && sudo pacman -Syu
INSTALL_STATUS=$?
if [ $INSTALL_STATUS -ne 0 ]; then
    error_log "\n${RED}--- ERRO CRÍTICO ---${NC}"
    error_log "${RED}Não foi possível instalar pacotes básicos ou atualizar o sistema.${NC}"
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

    if git clone https://aur.archlinux.org/yay; then
        cd yay || { error_log "${RED}Erro: Não foi possível mudar para /tmp/yay/${NC}"; exit 1; }
        log "Compilando e instalando o yay..."
        makepkg -si --noconfirm
        INSTALL_STATUS=$?
        if [ $INSTALL_STATUS -eq 0 ]; then
            log "${GREEN}yay instalado com sucesso!${NC}"
            cd .. && rm -rf yay
        else
            error_log "\n${RED}--- ERRO NA INSTALAÇÃO ---${NC}"
        fi
    else
        error_log "\n${RED}--- ERRO DE DOWNLOAD ---${NC}"
        INSTALL_STATUS=1
    fi
fi
confirmar_proxima_etapa "instalação de pacotes" $INSTALL_STATUS

# --- 3. Instalação de Pacotes (pacman e AUR) com verificação de já instalados ---
separator
log "${GREEN}--- 3. Instalação de Pacotes (Otimizada) ---${NC}"

# Lista completa de pacotes
PACOTES_PACMAN=(
    # Core Hyprland
    hyprland
    hyprpaper
    hyprlock
    hypridle
    hyprcursor
    hyprpicker
    
    # Utilitários Wayland
    waybar
    kitty
    rofi-wayland
    dunst
    cliphist
    wlogout
    
    # Portais e integração
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    xdg-user-dirs
    
    # KDE/QT (sem Modelos e Público)
    dolphin
    dolphin-plugins
    ark
    kio-admin
    polkit-kde-agent
    kate
    kde-cli-tools
    
    # Temas e ícones
    breeze
    breeze-gtk
    papirus-icon-theme
    qt5-wayland
    qt6-wayland
    qt5ct
    qt6ct
    
    # Fontes
    ttf-font-awesome
    ttf-jetbrains-mono-nerd
    ttf-opensans
    ttf-roboto
    
    # Áudio
    pipewire
    pavucontrol
    
    # Multimídia
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    
    # Ferramentas
    nano
    archlinux-xdg-menu
    hyprshot
)

PACOTES_AUR=(
    nwg-look
    visual-studio-code-bin
    mpv
    qview
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
    sudo pacman -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_PACMAN[@]}"
    INSTALL_STATUS=$?
    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_PACMAN[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes pacman instalados com sucesso!${NC}"
    else
        error_log "${RED}Erro na instalação de alguns pacotes pacman${NC}"
    fi
else
    log "${GREEN}Todos os pacotes pacman já estão instalados!${NC}"
fi

# Instalar pacotes faltantes do AUR
if [ ${#PACOTES_PARA_INSTALAR_AUR[@]} -gt 0 ]; then
    log "\n${YELLOW}Instalando pacotes do AUR (${#PACOTES_PARA_INSTALAR_AUR[@]} pacotes)...${NC}"
    yay -S --needed --noconfirm "${PACOTES_PARA_INSTALAR_AUR[@]}"
    INSTALL_STATUS=$?
    if [ $INSTALL_STATUS -eq 0 ]; then
        for pkg in "${PACOTES_PARA_INSTALAR_AUR[@]}"; do
            PACOTES_INSTALADOS["$pkg"]=1
        done
        log "${GREEN}Pacotes AUR instalados com sucesso!${NC}"
    else
        error_log "${RED}Erro na instalação de alguns pacotes AUR${NC}"
    fi
else
    log "${GREEN}Todos os pacotes AUR já estão instalados!${NC}"
fi

confirmar_proxima_etapa "configuração de diretórios XDG" 0

# --- 4. Configuração de Diretórios XDG (com Área de Trabalho, sem Modelos/Público) ---
separator
log "${GREEN}--- 4. Configuração de Diretórios XDG ---${NC}"
log "Garantindo que as pastas de usuário existam..."

# Força a criação/atualização dos diretórios XDG
xdg-user-dirs-update --force

# Configurar diretórios específicos
log "${YELLOW}Configurando diretórios personalizados...${NC}"

# Define Área de Trabalho em vez de Desktop
xdg-user-dirs-update --set DESKTOP "$HOME/Área de Trabalho"

# Define outros diretórios (sem Modelos e Público)
xdg-user-dirs-update --set DOWNLOAD "$HOME/Downloads"
xdg-user-dirs-update --set DOCUMENTS "$HOME/Documentos"
xdg-user-dirs-update --set MUSIC "$HOME/Música"
xdg-user-dirs-update --set PICTURES "$HOME/Imagens"
xdg-user-dirs-update --set VIDEOS "$HOME/Vídeos"

# Remove Modelos e Público se existirem
rm -rf "$HOME/Modelos" "$HOME/Público" 2>/dev/null

# Edita o arquivo de configuração para remover as entradas de Modelos e Público
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    sed -i '/XDG_TEMPLATES_DIR/d' "$HOME/.config/user-dirs.dirs"
    sed -i '/XDG_PUBLICSHARE_DIR/d' "$HOME/.config/user-dirs.dirs"
    log "${GREEN}✓ Entradas de Modelos e Público removidas do user-dirs.dirs${NC}"
fi

# Criar diretórios físicos se não existirem
for pasta in "Área de Trabalho" "Documentos" "Downloads" "Música" "Imagens" "Vídeos"; do
    if [ ! -d "$HOME/$pasta" ]; then
        mkdir -p "$HOME/$pasta"
        log "${GREEN}✓ Pasta $pasta criada${NC}"
    fi
done

# Criar script de correção XDG autônomo (será executado pelo systemd ou manualmente)
log "${YELLOW}Criando script de correção XDG autônomo...${NC}"

cat > "$HOME/.local/bin/fix-xdg-dirs.sh" << 'EOF'
#!/bin/bash
# Script autônomo para corrigir pastas XDG
# Pode ser executado manualmente ou agendado no systemd

# Atualiza os diretórios XDG
xdg-user-dirs-update --force

# Configura Área de Trabalho
xdg-user-dirs-update --set DESKTOP "$HOME/Área de Trabalho"

# Remove entradas indesejadas do arquivo de configuração
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    sed -i '/XDG_TEMPLATES_DIR/d' "$HOME/.config/user-dirs.dirs"
    sed -i '/XDG_PUBLICSHARE_DIR/d' "$HOME/.config/user-dirs.dirs"
fi

# Garante que as pastas físicas existam
for pasta in "Área de Trabalho" "Documentos" "Downloads" "Música" "Imagens" "Vídeos"; do
    [ ! -d "$HOME/$pasta" ] && mkdir -p "$HOME/$pasta"
done

# Reconstrói cache do KDE se disponível
if command -v kbuildsycoca6 &> /dev/null; then
    XDG_MENU_PREFIX=arch- kbuildsycoca6 2>/dev/null || kbuildsycoca6 2>/dev/null
fi

echo "Correção XDG concluída!"
EOF

chmod +x "$HOME/.local/bin/fix-xdg-dirs.sh"
log "${GREEN}✓ Script de correção XDG criado em ~/.local/bin/fix-xdg-dirs.sh${NC}"

# Criar serviço user systemd para executar a correção automaticamente
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/fix-xdg-dirs.service" << 'EOF'
[Unit]
Description=Corrigir diretórios XDG após login
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/fix-xdg-dirs.sh

[Install]
WantedBy=graphical-session.target
EOF

log "${GREEN}✓ Serviço systemd criado para corrigir XDG automaticamente${NC}"

# Habilitar o serviço
systemctl --user enable fix-xdg-dirs.service
systemctl --user start fix-xdg-dirs.service
log "${GREEN}✓ Serviço systemd habilitado e iniciado${NC}"

log "${GREEN}Configuração XDG concluída!${NC}"
confirmar_proxima_etapa "configuração final" 0

# --- 5. Configurações Finais do KDE/Dolphin ---
separator
log "${GREEN}--- 5. Configurações Finais do KDE/Dolphin ---${NC}"

# Executar correção XDG imediatamente
log "Executando correção XDG imediatamente..."
~/.local/bin/fix-xdg-dirs.sh

# Reconstruir cache do KDE novamente para garantir
if command -v kbuildsycoca6 &> /dev/null; then
    log "Reconstruindo cache do KDE..."
    XDG_MENU_PREFIX=arch- kbuildsycoca6 2>/dev/null || kbuildsycoca6 2>/dev/null
    log "${GREEN}✓ Cache do KDE reconstruído${NC}"
fi

# --- 6. Relatório Final ---
separator
log "\n${GREEN}======================================================${NC}"
log "${GREEN}✔️ Instalação e Configuração Concluídas!${NC}"
log "${GREEN}======================================================${NC}"

# Mostrar estatísticas de pacotes
log "\n${BLUE}📦 RELATÓRIO DE PACOTES:${NC}"
log "   ✓ Pacotes já instalados: ${#PACOTES_JA_INSTALADOS[@]}"
log "   ✓ Pacotes instalados agora: ${#PACOTES_INSTALADOS[@]}"
log "   ✓ Total de pacotes úteis: ${#PACOTES_NECESSARIOS[@]}"

# Listar pacotes já instalados
if [ ${#PACOTES_JA_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}✅ Pacotes que já estavam instalados (não precisaram ser reinstalados):${NC}"
    for pkg in "${!PACOTES_JA_INSTALADOS[@]}"; do
        log "   • $pkg"
    done | sort
fi

# Listar pacotes instalados
if [ ${#PACOTES_INSTALADOS[@]} -gt 0 ]; then
    log "\n${GREEN}📥 Pacotes que foram instalados agora:${NC}"
    for pkg in "${!PACOTES_INSTALADOS[@]}"; do
        log "   • $pkg"
    done | sort
fi

log "\n${BLUE}🎯 PRÓXIMOS PASSOS:${NC}"
log "1. ${RED}REINICIE SEU SISTEMA${NC}"
log "2. Faça login e inicie o Hyprland"
log "3. Configure temas com nwg-look (GTK) e qt5ct/qt6ct (QT)"
log "4. Personalize o waybar em ~/.config/waybar/"
log "5. Configure suas teclas e atalhos no Hyprland"

log "\n${BLUE}🔧 CORREÇÃO DE PASTAS XDG:${NC}"
log "   • As pastas XDG já foram configuradas automaticamente"
log "   • Um serviço systemd foi criado para corrigir a cada login"
log "   • Para executar manualmente: ${GREEN}~/.local/bin/fix-xdg-dirs.sh${NC}"
log "   • Para verificar o serviço: ${GREEN}systemctl --user status fix-xdg-dirs${NC}"

log "\n${BLUE}📚 DOCUMENTAÇÃO ÚTIL:${NC}"
log "   • Hyprland: https://wiki.hyprland.com"
log "   • Arch Wiki Hyprland: https://wiki.archlinux.org/title/Hyprland"
log "   • XDG User Directories: https://wiki.archlinux.org/title/XDG_user_directories"

log "\n${GREEN}✅ Script finalizado com sucesso! Log salvo em: $LOG_FILE${NC}\n"
```

📋 Principais alterações realizadas:

1. Removida completamente a seção sobre hyprland.conf ✓

· Não há mais criação de hyprland.conf
· O script não interfere na configuração do Hyprland

2. Correção do XDG movida para fora do hyprland.conf ✓

· Criado script autônomo: ~/.local/bin/fix-xdg-dirs.sh
· Criado serviço systemd user: ~/.config/systemd/user/fix-xdg-dirs.service
· Serviço executado automaticamente no graphical-session.target
· Correção executada imediatamente durante o script
· Serviço habilitado para rodar em todo login futuro

3. Removidas sugestões de pacotes opcionais ✓

· Não há mais lista de pacotes como Firefox, Discord, etc.

4. Benefícios da nova abordagem:

· Independente do Hyprland: A correção funciona com qualquer WM/DE
· Persistente: O serviço systemd garante correção em todo login
· Manual também: Pode executar ~/.local/bin/fix-xdg-dirs.sh quando quiser
· Leve: O serviço roda uma vez após o login gráfico
· Sem poluição: Não adiciona nada ao hyprland.conf

5. Como o serviço systemd funciona:

· Executa automaticamente após o ambiente gráfico iniciar
· Garante que as pastas estejam corretas em toda sessão
· Pode ser verificado com systemctl --user status fix-xdg-dirs

A correção XDG agora é completamente independente e muito mais robusta!