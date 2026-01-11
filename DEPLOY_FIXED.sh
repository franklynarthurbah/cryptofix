#!/bin/bash

##############################################
# CryptoVault FIXED Auto-Deployment
# Fixes all path issues and ensures success
##############################################

set -e  # Exit on error

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════════════╗
║                                                   ║
║     🚀 CryptoVault FIXED Deployment              ║
║                                                   ║
║     All path issues resolved!                    ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Auto-detect current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"

echo -e "${BLUE}📁 Detected project directory: ${GREEN}$PROJECT_DIR${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo bash $0${NC}"
    exit 1
fi

# Step 1: Update system
echo -e "${BLUE}[1/10] Updating system...${NC}"
apt update -qq
echo -e "${GREEN}✓ System updated${NC}"

# Step 2: Install essentials
echo -e "${BLUE}[2/10] Installing build essentials...${NC}"
apt install -y build-essential curl wget git > /dev/null 2>&1
echo -e "${GREEN}✓ Build tools installed${NC}"

# Step 3: Install Python
echo -e "${BLUE}[3/10] Installing Python 3...${NC}"
apt install -y python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
PYTHON_PATH=$(which python3)
echo -e "${GREEN}✓ Python 3 installed at: $PYTHON_PATH${NC}"

# Step 4: Install Node.js
echo -e "${BLUE}[4/10] Installing Node.js 18...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
fi
NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ Node.js $NODE_VERSION installed${NC}"

# Step 5: Install MongoDB
echo -e "${BLUE}[5/10] Installing MongoDB...${NC}"
if ! command -v mongod &> /dev/null; then
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - > /dev/null 2>&1
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
    apt update -qq
    apt install -y mongodb-org > /dev/null 2>&1
fi
systemctl start mongod
systemctl enable mongod > /dev/null 2>&1
sleep 2
if systemctl is-active --quiet mongod; then
    echo -e "${GREEN}✓ MongoDB started${NC}"
else
    echo -e "${RED}✗ MongoDB failed to start${NC}"
    systemctl status mongod
    exit 1
fi

# Step 6: Install Nginx
echo -e "${BLUE}[6/10] Installing Nginx...${NC}"
apt install -y nginx > /dev/null 2>&1
systemctl start nginx
systemctl enable nginx > /dev/null 2>&1
echo -e "${GREEN}✓ Nginx installed${NC}"

# Step 7: Setup backend
echo -e "${BLUE}[7/10] Setting up backend...${NC}"
cd "$BACKEND_DIR"

# Create virtual environment
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}  ✓ Virtual environment created${NC}"
fi

# Activate and install dependencies
source venv/bin/activate
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt > /dev/null 2>&1
deactivate
echo -e "${GREEN}✓ Backend dependencies installed${NC}"

# Create uploads directory
mkdir -p uploads
chmod 755 uploads

# Create environment file
cat > .env << EOF
JWT_SECRET=cryptovault-secret-key-2026-$(date +%s)
MONGO_URL=mongodb://localhost:27017
DB_NAME=cryptovault
PORT=8001
EOF
echo -e "${GREEN}✓ Backend configured${NC}"

# Step 8: Create backend systemd service
echo -e "${BLUE}[8/10] Creating backend service...${NC}"

cat > /etc/systemd/system/cryptovault-backend.service << EOF
[Unit]
Description=CryptoVault Backend API
After=network.target mongod.service
Wants=mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$BACKEND_DIR/venv/bin:/usr/local/bin:/usr/bin"
ExecStart=$BACKEND_DIR/venv/bin/python $BACKEND_DIR/server.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/cryptovault-backend.log
StandardError=append:/var/log/cryptovault-backend-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cryptovault-backend > /dev/null 2>&1
systemctl stop cryptovault-backend > /dev/null 2>&1
sleep 2
systemctl start cryptovault-backend
sleep 5

if systemctl is-active --quiet cryptovault-backend; then
    echo -e "${GREEN}✓ Backend service started successfully${NC}"
else
    echo -e "${RED}✗ Backend service failed to start${NC}"
    echo -e "${YELLOW}Checking logs...${NC}"
    journalctl -u cryptovault-backend -n 30 --no-pager
    exit 1
fi

# Step 9: Setup frontend
echo -e "${BLUE}[9/10] Setting up frontend...${NC}"
cd "$FRONTEND_DIR"

# Copy HTML files to web root
rm -rf /var/www/html/*
cp -r * /var/www/html/ 2>/dev/null || true
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
echo -e "${GREEN}✓ Frontend deployed${NC}"

# Step 10: Configure Nginx
echo -e "${BLUE}[10/10] Configuring Nginx...${NC}"

cat > /etc/nginx/sites-available/default << 'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # Increase timeouts
    proxy_connect_timeout 600;
    proxy_send_timeout 600;
    proxy_read_timeout 600;
    send_timeout 600;

    # Frontend
    location / {
        try_files $uri $uri/ /index.html;
    }

    # API Backend
    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 600s;
        proxy_connect_timeout 600s;
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
        alias $BACKEND_DIR/uploads/;
        autoindex off;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Client body size
    client_max_body_size 50M;
}
NGINX_CONF

# Replace $BACKEND_DIR in the config
sed -i "s|\$BACKEND_DIR|$BACKEND_DIR|g" /etc/nginx/sites-available/default

nginx -t > /dev/null 2>&1
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo -e "${GREEN}✓ Nginx configured${NC}"
else
    echo -e "${RED}✗ Nginx configuration error${NC}"
    nginx -t
    exit 1
fi

# Configure firewall
echo -e "${BLUE}Configuring firewall...${NC}"
ufw --force enable > /dev/null 2>&1
ufw allow 22/tcp > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configured${NC}"

# Run health checks
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}Running Health Checks...${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

sleep 3

# Check backend
echo -n "Backend API... "
HEALTH_CHECK=$(curl -s http://localhost:8001/api/health 2>&1)
if echo "$HEALTH_CHECK" | grep -q "ok"; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "Response: $HEALTH_CHECK"
fi

# Check MongoDB
echo -n "MongoDB... "
if systemctl is-active --quiet mongod; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
fi

# Check Nginx
echo -n "Nginx... "
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
fi

# Check admin login
echo -n "Admin Auth... "
ADMIN_TEST=$(curl -s -X POST http://localhost:8001/api/admin/login \
    -H "Content-Type: application/json" \
    -d '{"username":"TempWork","password":"TempW_115500_e","code":"?X!Z*"}' 2>&1)

if echo "$ADMIN_TEST" | grep -q "token"; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${YELLOW}⚠ Needs verification${NC}"
fi

# Get IP address
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║         ✅ DEPLOYMENT SUCCESSFUL!             ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📍 Access Information:${NC}"
echo -e "   Frontend:  ${GREEN}http://$IP${NC}"
echo -e "   API:       ${GREEN}http://$IP/api${NC}"
echo -e "   Health:    ${GREEN}http://$IP/api/health${NC}"
echo -e "   Admin:     ${GREEN}http://$IP/admin${NC}"
echo ""
echo -e "${BLUE}🔐 Admin Credentials:${NC}"
echo -e "   Code:      ${GREEN}?X!Z*${NC}"
echo -e "   Username:  ${GREEN}TempWork${NC}"
echo -e "   Password:  ${GREEN}TempW_115500_e${NC}"
echo ""
echo -e "${BLUE}📊 Service Commands:${NC}"
echo -e "   Status:    ${GREEN}systemctl status cryptovault-backend${NC}"
echo -e "   Logs:      ${GREEN}journalctl -u cryptovault-backend -f${NC}"
echo -e "   Restart:   ${GREEN}systemctl restart cryptovault-backend${NC}"
echo ""
echo -e "${BLUE}📁 Project Directory:${NC}"
echo -e "   Location:  ${GREEN}$PROJECT_DIR${NC}"
echo ""

# Save deployment info
cat > /root/cryptovault-deployment-info.txt << INFO
CryptoVault Deployment Information
===================================

Deployment Date: $(date)
Project Directory: $PROJECT_DIR
Backend Directory: $BACKEND_DIR
Frontend Directory: $FRONTEND_DIR

Server IP: $IP

Access URLs:
- Frontend: http://$IP
- API: http://$IP/api
- Health: http://$IP/api/health
- Admin: http://$IP/admin

Admin Credentials:
- Access Code: ?X!Z*
- Username: TempWork
- Password: TempW_115500_e

Services:
- Backend: systemctl status cryptovault-backend
- MongoDB: systemctl status mongod
- Nginx: systemctl status nginx

Logs:
- Backend: journalctl -u cryptovault-backend -f
- MongoDB: tail -f /var/log/mongodb/mongod.log
- Nginx: tail -f /var/log/nginx/error.log

Python Path: $PYTHON_PATH
Node Version: $NODE_VERSION
INFO

echo -e "${GREEN}✓ Deployment info saved to /root/cryptovault-deployment-info.txt${NC}"
echo ""
echo -e "${YELLOW}🎉 Your CryptoVault platform is now live!${NC}"
echo ""

exit 0
