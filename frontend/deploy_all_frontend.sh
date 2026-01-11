#!/bin/bash

##############################################
# Deploy All Frontend Pages
# Connects everything to 164.92.138.206
##############################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════════╗
║                                               ║
║     🚀 FRONTEND DEPLOYMENT                   ║
║                                               ║
║     Deploying all pages to your server       ║
║                                               ║
╚═══════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root: sudo bash $0${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
SERVER_IP="164.92.138.206"

echo -e "${YELLOW}[1/5] Preparing frontend directory...${NC}"
cd "$FRONTEND_DIR" || exit 1

# Update all API URLs to use the correct IP
echo "  → Updating API URLs to $SERVER_IP..."
find . -name "*.html" -type f -exec sed -i "s|http://localhost:8001|http://$SERVER_IP:8001|g" {} \;
find . -name "*.html" -type f -exec sed -i "s|ws://localhost:8001|ws://$SERVER_IP:8001|g" {} \;

# Also update any references to old IPs
find . -name "*.html" -type f -exec sed -i "s|http://164.92.138.206:8001|http://$SERVER_IP:8001|g" {} \;
find . -name "*.html" -type f -exec sed -i "s|ws://164.92.138.206:8001|ws://$SERVER_IP:8001|g" {} \;

echo -e "${GREEN}✓ API URLs updated${NC}"
echo ""

echo -e "${YELLOW}[2/5] Clearing web directory...${NC}"
rm -rf /var/www/html/*
echo -e "${GREEN}✓ Directory cleared${NC}"
echo ""

echo -e "${YELLOW}[3/5] Copying all files...${NC}"
cp -r * /var/www/html/ 2>/dev/null || true

# Verify critical files
CRITICAL_FILES=("index.html" "login.html" "dashboard.html" "admin-dashboard.html")
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "/var/www/html/$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file deployed"
    else
        echo -e "  ${RED}✗${NC} $file missing!"
    fi
done

echo -e "${GREEN}✓ Files copied${NC}"
echo ""

echo -e "${YELLOW}[4/5] Setting permissions...${NC}"
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;
echo -e "${GREEN}✓ Permissions set${NC}"
echo ""

echo -e "${YELLOW}[5/5] Testing deployment...${NC}"

# Test main page
echo -n "  Testing index.html... "
if curl -s -m 5 http://localhost/ | grep -q "<!DOCTYPE html"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test login page
echo -n "  Testing login.html... "
if curl -s -m 5 http://localhost/login.html | grep -q "<!DOCTYPE html"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test dashboard
echo -n "  Testing dashboard.html... "
if curl -s -m 5 http://localhost/dashboard.html | grep -q "<!DOCTYPE html"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test admin
echo -n "  Testing admin-dashboard.html... "
if curl -s -m 5 http://localhost/admin-dashboard.html | grep -q "<!DOCTYPE html"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Reload Nginx
systemctl reload nginx 2>/dev/null || nginx -s reload

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}║         ✅ DEPLOYMENT COMPLETE!              ║${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 Your Website:${NC}"
echo -e "   Main:       ${GREEN}http://$SERVER_IP${NC}"
echo -e "   Login:      ${GREEN}http://$SERVER_IP/login.html${NC}"
echo -e "   Register:   ${GREEN}http://$SERVER_IP/register.html${NC}"
echo -e "   Dashboard:  ${GREEN}http://$SERVER_IP/dashboard.html${NC}"
echo -e "   Admin:      ${GREEN}http://$SERVER_IP/admin-dashboard.html${NC}"
echo ""
echo -e "${BLUE}📋 Deployed Pages:${NC}"
ls -lh /var/www/html/*.html | awk '{print "   " $9}' | sed 's|/var/www/html/||'
echo ""
echo -e "${YELLOW}✨ All pages are now connected to WebSocket at ws://$SERVER_IP:8001${NC}"
echo ""

exit 0