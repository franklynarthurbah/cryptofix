#!/bin/bash

##############################################
# CryptoVault Complete Deployment
# Deploys to 164.92.138.206 with cryptovault.hopto.org
# Ensures constant running with systemd services
##############################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOSTNAME="cryptovault.hopto.org"
IP="164.92.138.206"

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║     🚀 CryptoVault Complete Deployment           ║
║                                                   ║
║     cryptovault.hopto.org (164.92.138.206)       ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo bash $0${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Phase 1: System Setup
echo -e "${YELLOW}[1/10] Installing system packages...${NC}"
apt update -qq
apt install -y build-essential curl wget git lsof python3 python3-pip python3-venv python3-dev nginx > /dev/null 2>&1
echo -e "${GREEN}✓ System packages installed${NC}"

# Phase 2: MongoDB
echo -e "${YELLOW}[2/10] Setting up MongoDB...${NC}"
if ! command -v mongod &> /dev/null; then
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - > /dev/null 2>&1
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
    apt update -qq
    apt install -y mongodb-org > /dev/null 2>&1
fi
systemctl start mongod
systemctl enable mongod > /dev/null 2>&1
echo -e "${GREEN}✓ MongoDB running${NC}"

# Phase 3: Backend Setup
echo -e "${YELLOW}[3/10] Setting up backend...${NC}"
cd backend

if [ -d "venv" ]; then
    rm -rf venv
fi

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt > /dev/null 2>&1

deactivate

mkdir -p uploads
chmod 755 uploads

cat > .env << ENVEOF
JWT_SECRET=cryptovault-secret-key-2026-$(date +%s)
MONGO_URL=mongodb://localhost:27017
DB_NAME=cryptovault
PORT=8001
ENVEOF

echo -e "${GREEN}✓ Backend configured${NC}"

# Phase 4: Initialize Database
echo -e "${YELLOW}[4/10] Initializing database...${NC}"
source venv/bin/activate
python3 init_database.py
deactivate
echo -e "${GREEN}✓ Database initialized${NC}"

cd ..

# Phase 5: Frontend Setup
echo -e "${YELLOW}[5/10] Setting up frontend...${NC}"
rm -rf /var/www/html/*
cp -r frontend/* /var/www/html/
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
echo -e "${GREEN}✓ Frontend deployed${NC}"

# Phase 6: Backend Service
echo -e "${YELLOW}[6/10] Creating backend service...${NC}"

cat > /etc/systemd/system/cryptovault-backend.service << SERVICEEOF
[Unit]
Description=CryptoVault Backend API
After=network.target mongod.service
Wants=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR/backend
Environment="PATH=$SCRIPT_DIR/backend/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=$SCRIPT_DIR/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001 --log-level info
Restart=always
RestartSec=10
StartLimitInterval=0
StartLimitBurst=5
StandardOutput=append:/var/log/cryptovault-backend.log
StandardError=append:/var/log/cryptovault-backend-error.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable cryptovault-backend > /dev/null 2>&1
systemctl stop cryptovault-backend > /dev/null 2>&1 || true
sleep 2
systemctl start cryptovault-backend
sleep 5

if systemctl is-active --quiet cryptovault-backend; then
    echo -e "${GREEN}✓ Backend service started${NC}"
else
    echo -e "${RED}✗ Backend failed to start${NC}"
    systemctl status cryptovault-backend --no-pager | head -20
    exit 1
fi

# Phase 7: No-IP Service (Optional)
echo -e "${YELLOW}[7/10] Setting up No-IP updater...${NC}"

cat > /etc/systemd/system/noip-cryptovault.service << NOIPEOF
[Unit]
Description=No-IP DNS Updater for CryptoVault
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR/scripts
ExecStart=/usr/bin/python3 $SCRIPT_DIR/scripts/noip-cryptovault.py
Restart=always
RestartSec=60
StandardOutput=append:/var/log/noip-cryptovault.log
StandardError=append:/var/log/noip-cryptovault-error.log

[Install]
WantedBy=multi-user.target
NOIPEOF

systemctl daemon-reload
systemctl enable noip-cryptovault > /dev/null 2>&1

echo -e "${GREEN}✓ No-IP service created (edit credentials in scripts/noip-cryptovault.py to start)${NC}"

# Phase 8: Nginx Configuration
echo -e "${YELLOW}[8/10] Configuring Nginx...${NC}"

cat > /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # Logging
    access_log /var/log/nginx/cryptovault-access.log;
    error_log /var/log/nginx/cryptovault-error.log;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
        
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
    }

    location /ws/ {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    location /uploads/ {
        alias BACKEND_DIR_PLACEHOLDER/uploads/;
        autoindex off;
    }

    client_max_body_size 50M;
}
NGINXEOF

sed -i "s|BACKEND_DIR_PLACEHOLDER|$SCRIPT_DIR/backend|g" /etc/nginx/sites-available/default

nginx -t > /dev/null 2>&1
systemctl reload nginx
echo -e "${GREEN}✓ Nginx configured${NC}"

# Phase 9: Firewall
echo -e "${YELLOW}[9/10] Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw --force enable > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow 8001/tcp > /dev/null 2>&1
    echo -e "${GREEN}✓ Firewall configured${NC}"
else
    echo -e "${YELLOW}⚠ UFW not available${NC}"
fi

# Phase 10: Health Checks
echo -e "${YELLOW}[10/10] Running health checks...${NC}"
sleep 3

echo -n "  API Health... "
for i in {1..5}; do
    if curl -s -m 5 http://localhost:8001/api/health 2>&1 | grep -q "ok"; then
        echo -e "${GREEN}✓${NC}"
        break
    fi
    [ $i -eq 5 ] && echo -e "${RED}✗${NC}"
    sleep 2
done

echo -n "  MongoDB... "
systemctl is-active --quiet mongod && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  Nginx... "
systemctl is-active --quiet nginx && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  Backend Service... "
systemctl is-active --quiet cryptovault-backend && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Success!
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║         ✅ DEPLOYMENT SUCCESSFUL!             ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 Access Information:${NC}"
echo -e "   Hostname:  ${GREEN}http://$HOSTNAME${NC}"
echo -e "   IP:        ${GREEN}http://$IP${NC}"
echo -e "   API:       ${GREEN}http://$IP:8001/api/health${NC}"
echo ""
echo -e "${BLUE}🔐 Admin Credentials:${NC}"
echo -e "   Code:      ${GREEN}?X!Z*${NC}"
echo -e "   Username:  ${GREEN}TempWork${NC}"
echo -e "   Password:  ${GREEN}TempW_115500_e${NC}"
echo ""
echo -e "${BLUE}📊 Services (Running Constantly):${NC}"
echo -e "   Backend:   ${GREEN}systemctl status cryptovault-backend${NC}"
echo -e "   MongoDB:   ${GREEN}systemctl status mongod${NC}"
echo -e "   Nginx:     ${GREEN}systemctl status nginx${NC}"
echo -e "   No-IP:     ${GREEN}systemctl status noip-cryptovault${NC}"
echo ""
echo -e "${BLUE}🧪 Test Everything:${NC}"
echo -e "   Run:       ${GREEN}bash TEST-ALL-PAGES.sh${NC}"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo "1. Edit scripts/noip-cryptovault.py with your No-IP credentials"
echo "2. Start No-IP service: systemctl start noip-cryptovault"
echo "3. Run tests: bash TEST-ALL-PAGES.sh"
echo "4. Access: http://$HOSTNAME or http://$IP"
echo ""
echo -e "${YELLOW}🎉 Platform is LIVE and will run constantly!${NC}"
echo ""

exit 0
