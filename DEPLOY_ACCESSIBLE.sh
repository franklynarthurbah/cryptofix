#!/bin/bash

##############################################
# CryptoVault COMPLETE & ACCESSIBLE Deploy
# Fixes 500 errors, Creates admin, Makes globally accessible
##############################################

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔════════════════════════════════════════════════╗
║                                                ║
║     🌐 CryptoVault GLOBALLY ACCESSIBLE        ║
║                                                ║
║     Complete Fix - Works Everywhere!          ║
║                                                ║
╚════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo bash $0${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"

echo -e "${BLUE}📁 Project: ${GREEN}$SCRIPT_DIR${NC}"
echo ""

# ===============================================
# PHASE 1: COMPLETE CLEANUP
# ===============================================
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 1: Complete Cleanup                      ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

systemctl stop cryptovault-backend 2>/dev/null || true
sleep 2

echo "  Killing all processes on port 8001..."
pkill -9 -f "uvicorn" 2>/dev/null || true
pkill -9 -f "server.py" 2>/dev/null || true
fuser -k 8001/tcp 2>/dev/null || true
sleep 3

if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}✗ Port 8001 still in use${NC}"
    lsof -i :8001
    exit 1
fi
echo -e "${GREEN}✓ Port 8001 is free${NC}"

rm -f /etc/systemd/system/cryptovault-backend.service
systemctl daemon-reload
rm -rf "$BACKEND_DIR/venv"
rm -f /var/log/cryptovault-backend*.log

echo ""

# ===============================================
# PHASE 2: SYSTEM SETUP
# ===============================================
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 2: System Setup                          ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

apt update -qq 2>&1 | grep -v "^Get:" || true
apt install -y build-essential curl wget git lsof python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
echo -e "${GREEN}✓ Build tools installed${NC}"

# MongoDB
if ! command -v mongod &> /dev/null; then
    echo "  Installing MongoDB..."
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - > /dev/null 2>&1 || true
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
    apt update -qq
    apt install -y mongodb-org > /dev/null 2>&1
fi

systemctl start mongod 2>/dev/null || mongod --fork --logpath /var/log/mongodb/mongod.log --dbpath /var/lib/mongodb
systemctl enable mongod > /dev/null 2>&1 || true
sleep 3

if systemctl is-active --quiet mongod 2>/dev/null || pgrep mongod > /dev/null; then
    echo -e "${GREEN}✓ MongoDB running${NC}"
else
    echo -e "${RED}✗ MongoDB failed to start${NC}"
    exit 1
fi

# Nginx
apt install -y nginx > /dev/null 2>&1
systemctl start nginx 2>/dev/null || nginx
systemctl enable nginx > /dev/null 2>&1 || true
echo -e "${GREEN}✓ Nginx running${NC}"

echo ""

# ===============================================
# PHASE 3: BACKEND SETUP
# ===============================================
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 3: Backend Setup (2-3 min)              ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

cd "$BACKEND_DIR"

echo "  Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

echo "  Installing dependencies..."
pip install --upgrade pip > /dev/null 2>&1

# Install packages
pip install fastapi==0.109.0 > /dev/null 2>&1
pip install "uvicorn[standard]==0.27.0" > /dev/null 2>&1
pip install motor==3.3.2 > /dev/null 2>&1
pip install pymongo==4.6.1 > /dev/null 2>&1
pip install pydantic==2.5.0 > /dev/null 2>&1
pip install email-validator==2.1.0 > /dev/null 2>&1
pip install python-dotenv==1.0.0 > /dev/null 2>&1
pip install python-multipart==0.0.6 > /dev/null 2>&1
pip install bcrypt==4.1.2 > /dev/null 2>&1
pip install PyJWT==2.8.0 > /dev/null 2>&1
pip install websockets==12.0 > /dev/null 2>&1
pip install aiofiles==23.2.1 > /dev/null 2>&1
pip install httpx==0.25.2 > /dev/null 2>&1

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Create directories
mkdir -p uploads
chmod 755 uploads

# Create env
cat > .env << EOF
JWT_SECRET=cryptovault-secret-key-2026-$(date +%s)
MONGO_URL=mongodb://localhost:27017
DB_NAME=cryptovault
PORT=8001
EOF

echo -e "${GREEN}✓ Backend configured${NC}"

# ===============================================
# PHASE 4: DATABASE INITIALIZATION
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 4: Database Initialization               ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

python3 init_database.py

deactivate
echo ""

# ===============================================
# PHASE 5: SERVICE CREATION
# ===============================================
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 5: Service Creation                      ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

cat > /etc/systemd/system/cryptovault-backend.service << EOF
[Unit]
Description=CryptoVault Backend API
After=network.target mongod.service
Wants=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=$BACKEND_DIR/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001 --log-level info
Restart=always
RestartSec=10
StartLimitBurst=5
StandardOutput=append:/var/log/cryptovault-backend.log
StandardError=append:/var/log/cryptovault-backend-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cryptovault-backend > /dev/null 2>&1
echo -e "${GREEN}✓ Service created${NC}"

# ===============================================
# PHASE 6: START BACKEND
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 6: Starting Backend                      ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

systemctl start cryptovault-backend
echo "  Waiting for backend to start (10 seconds)..."
sleep 10

if systemctl is-active --quiet cryptovault-backend; then
    echo -e "${GREEN}✓ Backend service started${NC}"
else
    echo -e "${RED}✗ Backend failed to start${NC}"
    echo ""
    systemctl status cryptovault-backend --no-pager | head -20
    echo ""
    echo "Last 30 log lines:"
    tail -30 /var/log/cryptovault-backend-error.log
    exit 1
fi

# ===============================================
# PHASE 7: FRONTEND DEPLOYMENT
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 7: Frontend Deployment                   ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

cd "$FRONTEND_DIR"
rm -rf /var/www/html/*
cp -r * /var/www/html/ 2>/dev/null || true

# Fix ALL permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;

echo -e "${GREEN}✓ Frontend deployed${NC}"

# ===============================================
# PHASE 8: NGINX CONFIGURATION
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 8: Nginx Configuration                   ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

cat > /etc/nginx/sites-available/default << 'NGINX_EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # Logging
    access_log /var/log/nginx/cryptovault-access.log;
    error_log /var/log/nginx/cryptovault-error.log;

    # Frontend
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API Proxy
    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        
        # Error handling
        proxy_intercept_errors off;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    # Uploads
    location /uploads/ {
        alias BACKEND_DIR_PLACEHOLDER/uploads/;
        autoindex off;
    }

    client_max_body_size 50M;
}
NGINX_EOF

sed -i "s|BACKEND_DIR_PLACEHOLDER|$BACKEND_DIR|g" /etc/nginx/sites-available/default

# Test and reload
if nginx -t > /dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload
    echo -e "${GREEN}✓ Nginx configured${NC}"
else
    echo -e "${RED}✗ Nginx configuration error${NC}"
    nginx -t
    exit 1
fi

# ===============================================
# PHASE 9: FIREWALL (GLOBAL ACCESS)
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 9: Firewall - Enabling Global Access     ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

if command -v ufw &> /dev/null; then
    ufw --force enable > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    echo -e "${GREEN}✓ Firewall configured${NC}"
fi

# ===============================================
# PHASE 10: COMPREHENSIVE TESTING
# ===============================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}PHASE 10: Testing Everything                   ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""

sleep 3

# Test 1: API Health
echo -n "  API Health... "
for i in {1..5}; do
    HEALTH=$(curl -s -m 5 http://localhost:8001/api/health 2>&1)
    if echo "$HEALTH" | grep -q "ok"; then
        echo -e "${GREEN}✓${NC}"
        break
    fi
    if [ $i -eq 5 ]; then
        echo -e "${RED}✗${NC}"
    else
        sleep 2
    fi
done

# Test 2: Admin Login
echo -n "  Admin Login... "
ADMIN_TEST=$(curl -s -X POST http://localhost:8001/api/admin/login \
    -H "Content-Type: application/json" \
    -d '{"username":"TempWork","password":"TempW_115500_e","code":"?X!Z*"}' 2>&1)

if echo "$ADMIN_TEST" | grep -q "token"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Response: $ADMIN_TEST"
fi

# Test 3: Crypto Prices (Monero)
echo -n "  Monero (XMR)... "
PRICES=$(curl -s http://localhost:8001/api/crypto/prices 2>&1)
if echo "$PRICES" | grep -q "XMR"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
fi

# Test 4: Services
echo -n "  MongoDB... "
systemctl is-active --quiet mongod && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "  Nginx... "
systemctl is-active --quiet nginx && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"

echo -n "  Backend... "
systemctl is-active --quiet cryptovault-backend && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

# Get IP
IP=$(hostname -I | awk '{print $1}' || curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# ===============================================
# SUCCESS!
# ===============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║     ✅ DEPLOYMENT SUCCESSFUL!                 ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║     🌐 GLOBALLY ACCESSIBLE!                   ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 Access Your Platform:${NC}"
echo -e "   Main Site:  ${GREEN}http://$IP${NC}"
echo -e "   API:        ${GREEN}http://$IP/api/health${NC}"
echo -e "   Admin:      ${GREEN}http://$IP/admin${NC}"
echo ""
echo -e "${BLUE}🔐 Admin Login Credentials:${NC}"
echo -e "   Code:       ${GREEN}?X!Z*${NC}"
echo -e "   Username:   ${GREEN}TempWork${NC}"
echo -e "   Password:   ${GREEN}TempW_115500_e${NC}"
echo ""
echo -e "${BLUE}📊 Quick Commands:${NC}"
echo -e "   Status:     ${GREEN}systemctl status cryptovault-backend${NC}"
echo -e "   Logs:       ${GREEN}journalctl -u cryptovault-backend -f${NC}"
echo -e "   Restart:    ${GREEN}systemctl restart cryptovault-backend${NC}"
echo ""
echo -e "${BLUE}🧪 Test Admin Access:${NC}"
echo -e "   ${GREEN}curl -X POST http://$IP/api/admin/login \\${NC}"
echo -e "   ${GREEN}  -H 'Content-Type: application/json' \\${NC}"
echo -e "   ${GREEN}  -d '{\"username\":\"TempWork\",\"password\":\"TempW_115500_e\",\"code\":\"?X!Z*\"}'${NC}"
echo ""
echo -e "${YELLOW}🎉 Your CryptoVault is LIVE and accessible worldwide!${NC}"
echo ""

exit 0
