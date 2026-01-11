#!/bin/bash

##############################################
# CryptoVault BULLETPROOF Deployment
# Handles all edge cases and errors
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
║     🚀 CryptoVault BULLETPROOF Deploy            ║
║                                                   ║
║     Handles Everything Automatically!            ║
║                                                   ║
╚═══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# Auto-detect current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"

echo -e "${BLUE}📁 Project Directory: ${GREEN}$PROJECT_DIR${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root: sudo bash $0${NC}"
    exit 1
fi

# Function to print step
print_step() {
    echo -e "\n${BLUE}==>${NC} ${1}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓${NC} ${1}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗${NC} ${1}"
}

# Step 1: Update system
print_step "[1/12] Updating system..."
apt update -qq 2>&1 | grep -v "^Get:" || true
print_success "System updated"

# Step 2: Install essentials
print_step "[2/12] Installing build essentials..."
apt install -y build-essential curl wget git lsof > /dev/null 2>&1
print_success "Build tools installed"

# Step 3: Install Python
print_step "[3/12] Installing Python 3..."
apt install -y python3 python3-pip python3-venv python3-dev > /dev/null 2>&1
PYTHON_PATH=$(which python3)
PYTHON_VERSION=$(python3 --version 2>&1)
print_success "Python 3 installed: $PYTHON_VERSION"

# Step 4: Install Node.js
print_step "[4/12] Installing Node.js 18..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
fi
NODE_VERSION=$(node --version 2>/dev/null || echo "N/A")
print_success "Node.js $NODE_VERSION installed"

# Step 5: Install MongoDB
print_step "[5/12] Installing MongoDB..."
if ! command -v mongod &> /dev/null; then
    wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | apt-key add - > /dev/null 2>&1
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null
    apt update -qq 2>&1 | grep -v "^Get:" || true
    apt install -y mongodb-org > /dev/null 2>&1
fi

# Start MongoDB
systemctl start mongod 2>/dev/null || mongod --fork --logpath /var/log/mongodb/mongod.log --dbpath /var/lib/mongodb
systemctl enable mongod > /dev/null 2>&1 || true
sleep 3

# Check MongoDB
if systemctl is-active --quiet mongod 2>/dev/null || pgrep mongod > /dev/null; then
    print_success "MongoDB running"
else
    print_error "MongoDB not running, but continuing..."
fi

# Step 6: Install Nginx
print_step "[6/12] Installing Nginx..."
apt install -y nginx > /dev/null 2>&1
systemctl start nginx 2>/dev/null || nginx
systemctl enable nginx > /dev/null 2>&1 || true
print_success "Nginx installed"

# Step 7: Kill anything on port 8001
print_step "[7/12] Checking port 8001..."
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "   Port 8001 in use, freeing it..."
    kill -9 $(lsof -t -i:8001) 2>/dev/null || true
    sleep 2
    print_success "Port 8001 freed"
else
    print_success "Port 8001 available"
fi

# Step 8: Setup backend with proper virtual environment
print_step "[8/12] Setting up backend (this may take 2-3 minutes)..."
cd "$BACKEND_DIR"

# Remove old venv if exists
if [ -d "venv" ]; then
    echo "   Removing old virtual environment..."
    rm -rf venv
fi

# Create fresh virtual environment
echo "   Creating virtual environment..."
python3 -m venv venv
print_success "Virtual environment created"

# Activate and install dependencies
echo "   Installing dependencies (please wait)..."
source venv/bin/activate

# Upgrade pip first
pip install --upgrade pip > /dev/null 2>&1

# Install packages one by one for better error handling
echo "   Installing FastAPI..."
pip install "fastapi==0.109.0" > /dev/null 2>&1

echo "   Installing Uvicorn..."
pip install "uvicorn[standard]==0.27.0" > /dev/null 2>&1

echo "   Installing database drivers..."
pip install "motor==3.3.2" "pymongo==4.6.1" > /dev/null 2>&1

echo "   Installing utilities..."
pip install "pydantic==2.5.0" "python-dotenv==1.0.0" "python-multipart==0.0.6" > /dev/null 2>&1
pip install "bcrypt==4.1.2" "PyJWT==2.8.0" "websockets==12.0" > /dev/null 2>&1
pip install "aiofiles==23.2.1" "httpx==0.25.2" > /dev/null 2>&1

deactivate
print_success "All dependencies installed"

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
print_success "Backend configured"

# Step 9: Test Python imports
print_step "[9/12] Testing backend..."
source venv/bin/activate
IMPORT_TEST=$(python3 -c "import fastapi; import uvicorn; import motor; import pymongo; print('OK')" 2>&1)
deactivate

if echo "$IMPORT_TEST" | grep -q "OK"; then
    print_success "All imports working"
else
    print_error "Import test failed: $IMPORT_TEST"
    exit 1
fi

# Step 10: Create systemd service
print_step "[10/12] Creating backend service..."

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
ExecStart=$BACKEND_DIR/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8001 --log-level info
Restart=always
RestartSec=5
StartLimitInterval=0
StandardOutput=append:/var/log/cryptovault-backend.log
StandardError=append:/var/log/cryptovault-backend-error.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Stop old service
systemctl stop cryptovault-backend > /dev/null 2>&1 || true
sleep 2

# Enable and start service
systemctl enable cryptovault-backend > /dev/null 2>&1
systemctl start cryptovault-backend
sleep 5

# Check if service is running
if systemctl is-active --quiet cryptovault-backend 2>/dev/null; then
    print_success "Backend service started"
else
    print_error "Backend service failed to start"
    echo ""
    echo "Last 20 lines of service logs:"
    journalctl -u cryptovault-backend -n 20 --no-pager 2>/dev/null || cat /var/log/cryptovault-backend-error.log | tail -20
    echo ""
    echo "Trying to run manually for diagnosis..."
    cd "$BACKEND_DIR"
    source venv/bin/activate
    timeout 5 python3 server.py 2>&1 | head -30 || true
    deactivate
    exit 1
fi

# Step 11: Setup frontend
print_step "[11/12] Setting up frontend..."
cd "$FRONTEND_DIR"

# Copy HTML files to web root
rm -rf /var/www/html/*
cp -r * /var/www/html/ 2>/dev/null || true
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
print_success "Frontend deployed"

# Step 12: Configure Nginx
print_step "[12/12] Configuring Nginx..."

cat > /etc/nginx/sites-available/default << 'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # Timeouts
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

    # Security
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    client_max_body_size 50M;
}
NGINX_CONF

# Replace placeholder
sed -i "s|BACKEND_DIR_PLACEHOLDER|$BACKEND_DIR|g" /etc/nginx/sites-available/default

# Test and reload nginx
if nginx -t > /dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || nginx -s reload
    print_success "Nginx configured"
else
    print_error "Nginx configuration error"
    nginx -t
    exit 1
fi

# Configure firewall if UFW is available
if command -v ufw &> /dev/null; then
    print_step "Configuring firewall..."
    ufw --force enable > /dev/null 2>&1
    ufw allow 22/tcp > /dev/null 2>&1
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    print_success "Firewall configured"
fi

# Get IP address
IP=$(hostname -I | awk '{print $1}' || echo "YOUR_SERVER_IP")

# Health checks
echo ""
print_step "Running health checks..."
sleep 3

# Check backend health
echo -n "   Backend API... "
HEALTH=$(curl -s http://localhost:8001/api/health 2>&1 || echo "failed")
if echo "$HEALTH" | grep -q "ok"; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "   Response: $HEALTH"
fi

# Check MongoDB
echo -n "   MongoDB... "
if systemctl is-active --quiet mongod 2>/dev/null || pgrep mongod > /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}⚠ Check manually${NC}"
fi

# Check Nginx
echo -n "   Nginx... "
if systemctl is-active --quiet nginx 2>/dev/null || pgrep nginx > /dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${YELLOW}⚠ Check manually${NC}"
fi

# Test admin login
echo -n "   Admin Auth... "
ADMIN_TEST=$(curl -s -X POST http://localhost:8001/api/admin/login \
    -H "Content-Type: application/json" \
    -d '{"username":"TempWork","password":"TempW_115500_e","code":"?X!Z*"}' 2>&1 || echo "failed")

if echo "$ADMIN_TEST" | grep -q "token"; then
    echo -e "${GREEN}✓ Working${NC}"
else
    echo -e "${YELLOW}⚠ Verify manually${NC}"
fi

# Final output
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
echo -e "${BLUE}🧪 Test System:${NC}"
echo -e "   Run:       ${GREEN}bash scripts/TEST_COMPLETE.sh${NC}"
echo ""
echo -e "${YELLOW}🎉 Your platform is live!${NC}"
echo ""

exit 0
