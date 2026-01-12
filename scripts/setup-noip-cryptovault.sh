#!/bin/bash

##############################################
# CryptoVault No-IP Setup
# Maps cryptovault.hopto.org → 164.92.138.206
# Keeps hostname active continuously
##############################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║     🌐 CryptoVault No-IP DDNS Setup              ║
║                                                   ║
║     cryptovault.hopto.org → 164.92.138.206       ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo bash $0${NC}"
    exit 1
fi

HOSTNAME="cryptovault.hopto.org"
IP="164.92.138.206"

echo -e "${YELLOW}This will set up automatic DNS updates for:${NC}"
echo -e "  Hostname: ${GREEN}$HOSTNAME${NC}"
echo -e "  IP: ${GREEN}$IP${NC}"
echo ""
echo -e "${YELLOW}Requirements:${NC}"
echo "  • No-IP account (free at https://www.noip.com/sign-up)"
echo "  • Hostname '$HOSTNAME' created in your No-IP account"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."
echo ""

# Step 1: Install dependencies
echo -e "${YELLOW}[1/7] Installing dependencies...${NC}"
apt update -qq
apt install -y python3 python3-pip curl > /dev/null 2>&1
pip3 install requests > /dev/null 2>&1
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Step 2: Get No-IP credentials
echo ""
echo -e "${YELLOW}[2/7] No-IP Account Credentials${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if credentials already exist
if [ -f /etc/noip-credentials ]; then
    echo -e "${YELLOW}Existing credentials found.${NC}"
    read -p "Use existing credentials? (y/n): " USE_EXISTING
    if [ "$USE_EXISTING" != "y" ]; then
        read -p "Enter your No-IP email: " NOIP_USER
        read -s -p "Enter your No-IP password: " NOIP_PASS
        echo ""
    else
        source /etc/noip-credentials
        NOIP_USER=$NOIP_USERNAME
        NOIP_PASS=$NOIP_PASSWORD
    fi
else
    read -p "Enter your No-IP email: " NOIP_USER
    read -s -p "Enter your No-IP password: " NOIP_PASS
    echo ""
fi

# Validate credentials
echo -e "${YELLOW}Validating credentials...${NC}"
TEST_RESPONSE=$(curl -s -u "$NOIP_USER:$NOIP_PASS" \
    "https://dynupdate.no-ip.com/nic/update?hostname=$HOSTNAME&myip=$IP" \
    -A "CryptoVault-Installer/1.0")

if echo "$TEST_RESPONSE" | grep -qE "good|nochg"; then
    echo -e "${GREEN}✓ Credentials validated${NC}"
elif echo "$TEST_RESPONSE" | grep -q "nohost"; then
    echo -e "${RED}✗ Hostname not found in your No-IP account${NC}"
    echo -e "${YELLOW}Please add '$HOSTNAME' at https://www.noip.com/members/dns/${NC}"
    exit 1
elif echo "$TEST_RESPONSE" | grep -q "badauth"; then
    echo -e "${RED}✗ Invalid username or password${NC}"
    exit 1
else
    echo -e "${YELLOW}⚠ Could not validate (response: $TEST_RESPONSE)${NC}"
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

# Save credentials
cat > /etc/noip-credentials << EOF
NOIP_USERNAME=$NOIP_USER
NOIP_PASSWORD=$NOIP_PASS
EOF
chmod 600 /etc/noip-credentials
echo -e "${GREEN}✓ Credentials saved${NC}"

# Step 3: Install Python script
echo ""
echo -e "${YELLOW}[3/7] Installing updater script...${NC}"
cp noip-cryptovault.py /usr/local/bin/
chmod +x /usr/local/bin/noip-cryptovault.py
echo -e "${GREEN}✓ Updater installed${NC}"

# Step 4: Create systemd service
echo -e "${YELLOW}[4/7] Creating systemd service...${NC}"

cat > /etc/systemd/system/noip-cryptovault.service << 'EOF'
[Unit]
Description=CryptoVault No-IP Dynamic DNS Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/noip-credentials
ExecStart=/usr/bin/python3 /usr/local/bin/noip-cryptovault.py
Restart=always
RestartSec=30
StartLimitInterval=0
StartLimitBurst=10

# Logging
StandardOutput=append:/var/log/noip-cryptovault.log
StandardError=append:/var/log/noip-cryptovault-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable noip-cryptovault > /dev/null 2>&1
echo -e "${GREEN}✓ Service created${NC}"

# Step 5: Create monitoring script
echo -e "${YELLOW}[5/7] Creating health monitor...${NC}"

cat > /usr/local/bin/noip-monitor.sh << 'MONITOR'
#!/bin/bash

# No-IP Health Monitor
# Checks service health and DNS propagation

LOG="/var/log/noip-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Check if service is running
if ! systemctl is-active --quiet noip-cryptovault; then
    log "ERROR: Service not running - restarting"
    systemctl restart noip-cryptovault
    sleep 5
    
    if systemctl is-active --quiet noip-cryptovault; then
        log "SUCCESS: Service restarted"
    else
        log "CRITICAL: Failed to restart service"
    fi
else
    log "OK: Service is running"
fi

# Check DNS resolution
RESOLVED_IP=$(dig +short cryptovault.hopto.org @8.8.8.8 2>/dev/null | tail -1)
if [ "$RESOLVED_IP" == "164.92.138.206" ]; then
    log "OK: DNS resolves correctly to 164.92.138.206"
else
    log "WARNING: DNS resolves to $RESOLVED_IP (expected 164.92.138.206)"
fi

# Rotate log
if [ -f "$LOG" ]; then
    tail -500 "$LOG" > "$LOG.tmp"
    mv "$LOG.tmp" "$LOG"
fi
MONITOR

chmod +x /usr/local/bin/noip-monitor.sh

# Add cron job
cat > /etc/cron.d/noip-monitor << 'CRON'
# No-IP Health Monitor - Every 5 minutes
*/5 * * * * root /usr/local/bin/noip-monitor.sh
CRON

chmod 644 /etc/cron.d/noip-monitor
echo -e "${GREEN}✓ Health monitor created${NC}"

# Step 6: Start service
echo ""
echo -e "${YELLOW}[6/7] Starting No-IP service...${NC}"
systemctl start noip-cryptovault

sleep 5

if systemctl is-active --quiet noip-cryptovault; then
    echo -e "${GREEN}✓ Service started successfully${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo ""
    echo "Recent logs:"
    tail -20 /var/log/noip-cryptovault.log 2>/dev/null || echo "No logs yet"
    exit 1
fi

# Step 7: Verify setup
echo ""
echo -e "${YELLOW}[7/7] Verifying setup...${NC}"

# Check service
echo -n "  Service status... "
if systemctl is-active --quiet noip-cryptovault; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Check logs for successful update
sleep 3
echo -n "  Initial update... "
if grep -q "SUCCESS" /var/log/noip-cryptovault.log 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (check logs)${NC}"
fi

# Try DNS resolution
echo -n "  DNS resolution... "
RESOLVED=$(dig +short $HOSTNAME @8.8.8.8 2>/dev/null | tail -1)
if [ "$RESOLVED" == "$IP" ]; then
    echo -e "${GREEN}✓ ($RESOLVED)${NC}"
else
    echo -e "${YELLOW}⚠ Resolves to: $RESOLVED (may take 5-10 min)${NC}"
fi

# Success!
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║     ✅ No-IP Setup Complete!                  ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 Configuration:${NC}"
echo -e "   Hostname:      ${GREEN}$HOSTNAME${NC}"
echo -e "   IP Address:    ${GREEN}$IP${NC}"
echo -e "   Update Every:  ${GREEN}5 minutes${NC}"
echo -e "   Auto-restart:  ${GREEN}Enabled${NC}"
echo -e "   Monitoring:    ${GREEN}Every 5 minutes${NC}"
echo ""
echo -e "${BLUE}📊 Management Commands:${NC}"
echo -e "   Status:   ${GREEN}systemctl status noip-cryptovault${NC}"
echo -e "   Logs:     ${GREEN}tail -f /var/log/noip-cryptovault.log${NC}"
echo -e "   Monitor:  ${GREEN}tail -f /var/log/noip-monitor.log${NC}"
echo -e "   Restart:  ${GREEN}systemctl restart noip-cryptovault${NC}"
echo ""
echo -e "${BLUE}🔍 Test DNS:${NC}"
echo -e "   ${GREEN}dig $HOSTNAME${NC}"
echo -e "   ${GREEN}nslookup $HOSTNAME${NC}"
echo -e "   ${GREEN}ping $HOSTNAME${NC}"
echo ""
echo -e "${BLUE}🌐 Access Your Site:${NC}"
echo -e "   ${GREEN}http://$HOSTNAME${NC}"
echo -e "   ${GREEN}http://$HOSTNAME/admin${NC}"
echo ""
echo -e "${YELLOW}⏰ DNS propagation may take 5-10 minutes${NC}"
echo -e "${YELLOW}   Your hostname will auto-update every 5 minutes${NC}"
echo ""

# Create info file
cat > /root/noip-cryptovault-info.txt << INFO
CryptoVault No-IP Setup
=======================

Date: $(date)
Hostname: $HOSTNAME
IP: $IP

Status: $(systemctl is-active noip-cryptovault)
Updates: Every 5 minutes
Auto-restart: Enabled

Commands:
- Status: systemctl status noip-cryptovault
- Logs: tail -f /var/log/noip-cryptovault.log
- Monitor: tail -f /var/log/noip-monitor.log
- Restart: systemctl restart noip-cryptovault

Files:
- Service: /etc/systemd/system/noip-cryptovault.service
- Script: /usr/local/bin/noip-cryptovault.py
- Credentials: /etc/noip-credentials (chmod 600)
- Monitor: /usr/local/bin/noip-monitor.sh

Access:
http://$HOSTNAME
http://$HOSTNAME/admin
INFO

echo -e "${GREEN}✓ Info saved to /root/noip-cryptovault-info.txt${NC}"
echo ""

exit 0
