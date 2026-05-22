#!/bin/bash
# ==============================================================================
# SCRIPT DE REMOÇÃO COMPLETA — GATEWAY PROXY DEBIAN 13
# Remove todos os pacotes, arquivos, usuários e configurações instalados
# pelo script gateway-v*.sh (versões 20 a 27)
# ==============================================================================
# USO:
#   chmod +x gateway-uninstall.sh
#   sudo bash gateway-uninstall.sh
#
# ATENÇÃO: este script remove IRREVERSIVELMENTE todas as configurações.
#          Faça backup das listas de IPs se quiser reaproveitá-las.
# ==============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
step() { echo -e "\n${CYAN}── $1 ──────────────────────────────────────────────${NC}"; }

[ "$EUID" -ne 0 ] && { echo -e "${RED}[ERRO]${NC} Execute como root: sudo bash gateway-uninstall.sh"; exit 1; }

echo -e "${RED}"
echo "=============================================================================="
echo "  REMOÇÃO COMPLETA DO GATEWAY — DEBIAN 13"
echo "  Todos os pacotes, arquivos e configurações serão removidos."
echo "=============================================================================="
echo -e "${NC}"

# ─── Backup opcional das listas de IPs ────────────────────────────────────────
echo -e "${CYAN}Deseja fazer backup das listas de IPs antes de remover?${NC}"
echo -e "  As listas contêm seus IPs cadastrados (totais, parciais, bloqueados, etc.)"
read -rp "$(echo -e "${YELLOW}[?]${NC} Fazer backup em /root/gateway-backup-$(date +%Y%m%d)/ ? [S/n]: ")" DO_BACKUP
DO_BACKUP="${DO_BACKUP:-S}"
if [[ "$DO_BACKUP" =~ ^[SsYy]$ ]]; then
    BACKUP_DIR="/root/gateway-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -v /etc/squid/ips_totais.txt          "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/squid/ips_parciais.txt        "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/squid/ips_bloqueados.txt      "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/squid/ips_excecao_horario.txt "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/squid/sites_liberados.txt     "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/squid/sites_bloqueados.txt    "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/nftables/nat_1to1.txt         "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/nftables/ips_rede_wan.txt     "$BACKUP_DIR/" 2>/dev/null || true
    cp -v /etc/gateway-panel.env             "$BACKUP_DIR/" 2>/dev/null || true
    ok "Backup salvo em $BACKUP_DIR"
fi

echo ""
read -rp "$(echo -e "${RED}[!]${NC} CONFIRMA remoção completa do gateway? [s/N]: ")" CONFIRM
[[ ! "${CONFIRM:-N}" =~ ^[SsYy]$ ]] && { warn "Cancelado."; exit 0; }

# ==============================================================================
step "1. PARANDO E DESABILITANDO SERVIÇOS"
# ==============================================================================
for SVC in gateway-panel squid squid6 squid-openssl bind9 named chrony chronyd nginx nginx-light nftables; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        log "Parando $SVC..."
        systemctl stop    "$SVC" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$SVC" 2>/dev/null; then
        systemctl disable "$SVC" 2>/dev/null || true
    fi
done
ok "Serviços parados."

# ==============================================================================
step "2. REMOVENDO PACOTES"
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive
log "Removendo squid, bind9, chrony, nginx, nftables..."

apt-get remove --purge -y \
    squid squid6 squid-openssl squid-common \
    bind9 bind9utils bind9-host \
    chrony \
    nginx nginx-light nginx-common \
    nftables \
    2>/dev/null || true

# Pacotes auxiliares instalados pelo script
apt-get remove --purge -y \
    ifupdown ifupdown2 \
    conntrack \
    logrotate \
    2>/dev/null || true

apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean 2>/dev/null || true
ok "Pacotes removidos."

# ==============================================================================
step "3. REMOVENDO ARQUIVOS DE CONFIGURAÇÃO E DADOS"
# ==============================================================================

# Squid
log "Removendo arquivos do Squid..."
rm -rf /etc/squid/
rm -rf /var/spool/squid/
rm -rf /var/log/squid/
rm -rf /var/lib/squid/
rm -rf /run/squid/
rm -f  /etc/tmpfiles.d/squid.conf
rm -f  /etc/logrotate.d/squid-gateway
rm -f  /usr/local/share/ca-certificates/gateway-ca.crt
update-ca-certificates --fresh -q 2>/dev/null || true
ok "Squid removido."

# BIND9
log "Removendo arquivos do BIND9..."
rm -rf /etc/bind/zones/
rm -f  /etc/bind/named.conf.options
rm -f  /etc/bind/named.conf.local
rm -f  /var/cache/bind/*
ok "BIND9 removido."

# Chrony
log "Removendo configuração do Chrony..."
rm -f /etc/chrony/chrony.conf
rm -f /var/lib/chrony/drift
ok "Chrony removido."

# nftables
log "Removendo configuração do nftables..."
# Limpar regras ativas antes de remover
nft flush ruleset 2>/dev/null || true
rm -f /etc/nftables.conf
rm -rf /etc/nftables/
ok "nftables removido."

# Nginx / WPAD
log "Removendo nginx e WPAD..."
rm -rf /var/www/gateway-wpad/
rm -f  /etc/nginx/sites-available/gateway-wpad
rm -f  /etc/nginx/sites-enabled/gateway-wpad
ok "Nginx/WPAD removido."

# Painel Flask/Gunicorn
log "Removendo painel web..."
rm -rf /opt/gateway-panel/
rm -rf /var/log/gateway-panel/
rm -f  /etc/systemd/system/gateway-panel.service
rm -f  /etc/gateway-panel.env
ok "Painel removido."

# Scripts utilitários
log "Removendo scripts utilitários..."
rm -f /usr/local/bin/update-nat1to1.sh
rm -f /usr/local/bin/squid-force-block.sh
rm -f /usr/local/bin/squid-open-schedule.sh
rm -f /usr/local/bin/sync-gateway-ca.sh
rm -f /usr/local/bin/gateway-panel-senha.sh
ok "Scripts removidos."

# Cron
log "Removendo cron jobs..."
rm -f /etc/cron.d/squid-schedule
ok "Cron removido."

# Sysctl
log "Removendo parâmetros de kernel..."
rm -f /etc/sysctl.d/99-gateway.conf
sysctl --system -q 2>/dev/null || true
ok "sysctl removido."

# Logs de schedule
rm -f /var/log/squid-schedule.log
rm -f /tmp/squid-init.log
rm -f /tmp/apt-update.log

# ==============================================================================
step "4. REMOVENDO USUÁRIO DO PAINEL"
# ==============================================================================
if id "gateway-panel" &>/dev/null; then
    log "Removendo usuário gateway-panel..."
    userdel -r gateway-panel 2>/dev/null || userdel gateway-panel 2>/dev/null || true
    ok "Usuário gateway-panel removido."
else
    warn "Usuário gateway-panel não encontrado — pulando."
fi

# ==============================================================================
step "5. REVERTENDO CONFIGURAÇÕES DE REDE"
# ==============================================================================
log "Revertendo systemd-resolved..."
systemctl unmask systemd-resolved 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
systemctl start  systemd-resolved 2>/dev/null || true

# Remover interfaces customizadas do gateway
log "Removendo configurações de interface do gateway..."
rm -f /etc/network/interfaces.d/gateway-mon
rm -f /etc/systemd/network/10-gateway-wan.network
rm -f /etc/systemd/network/20-gateway-lan.network

# Restaurar /etc/network/interfaces para o padrão Debian
if grep -q "gateway-v" /etc/network/interfaces 2>/dev/null; then
    warn "Detectado /etc/network/interfaces modificado pelo gateway."
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)
    cat <<'EOF' > /etc/network/interfaces
# Gerado pelo gateway-uninstall — configure conforme necessário
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
    warn "interfaces restaurado para padrão. Configure seu IP manualmente."
fi

# Restaurar resolv.conf para symlink do systemd-resolved (padrão Debian 13)
if [ ! -L /etc/resolv.conf ]; then
    log "Restaurando resolv.conf como symlink para systemd-resolved..."
    rm -f /etc/resolv.conf
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || \
        printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf
fi

# Reabilitar NetworkManager se estava instalado
if dpkg -l NetworkManager 2>/dev/null | grep -q '^ii'; then
    log "Reabilitando NetworkManager..."
    systemctl enable NetworkManager 2>/dev/null || true
    systemctl start  NetworkManager 2>/dev/null || true
fi

ok "Rede revertida."

# ==============================================================================
step "6. RECARREGANDO SYSTEMD"
# ==============================================================================
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
ok "systemd recarregado."

# ==============================================================================
echo ""
echo -e "${GREEN}=============================================================================="
echo " REMOÇÃO CONCLUÍDA"
echo "=============================================================================="
echo -e "${NC}"
echo -e " ${GREEN}Removido:${NC} squid, bind9, chrony, nginx, nftables, gateway-panel"
echo -e " ${GREEN}Removido:${NC} /etc/squid /etc/bind/zones /etc/nftables /opt/gateway-panel"
echo -e " ${GREEN}Removido:${NC} usuário gateway-panel, cron jobs, sysctl, scripts utilitários"
echo -e " ${GREEN}Restaurado:${NC} systemd-resolved, /etc/network/interfaces, resolv.conf"
if [[ "${DO_BACKUP:-N}" =~ ^[SsYy]$ ]]; then
    echo -e " ${YELLOW}Backup das listas:${NC} $BACKUP_DIR"
fi
echo ""
echo -e "${YELLOW} PRÓXIMOS PASSOS:${NC}"
echo -e "  1. Configure a rede manualmente em /etc/network/interfaces"
echo -e "     ou reative NetworkManager: systemctl start NetworkManager"
echo -e "  2. Verifique conectividade: ping 8.8.8.8"
echo -e "  3. Execute o novo script de instalação: bash gateway-v27.sh"
echo ""
echo -e "${CYAN} Recomendado reiniciar antes de reinstalar: reboot${NC}"
echo ""