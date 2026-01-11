#!/bin/bash

##############################################
# Quick Fix for 500 Internal Server Error
# Fixes admin login and makes site accessible
##############################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Quick Fix for 500 Error${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root: sudo bash $0${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"

# Step 1: Initialize database and create admin
echo -e "${YELLOW}[1/5] Creating admin user...${NC}"
cd "$BACKEND_DIR"

if [ -d "venv" ]; then
    source venv/bin/activate
    python3 init_database.py
    deactivate
    echo -e "${GREEN}✓ Admin created${NC}"
else
    echo -e "${RED}✗ Venv not found. Run DEPLOY_ACCESSIBLE.sh first${NC}"
    exit 1
fi

# Step 2: Restart backend
echo ""
echo -e "${YELLOW}[2/5] Restarting backend...${NC}"
systemctl restart cryptovault-backend
sleep 5

if systemctl is-active --quiet cryptovault-backend; then
    echo -e "${GREEN}✓ Backend restarted${NC}"
else
    echo -e "${RED}✗ Backend failed${NC}"
    systemctl status cryptovault-backend --no-pager -l | head -20
    exit 1
fi

# Step 3: Check logs for errors
echo ""
echo -e "${YELLOW}[3/5] Checking for errors...${NC}"
sleep 2

ERRORS=$(tail -20 /var/log/cryptovault-backend-error.log 2>/dev/null | grep -i "error\|exception\|traceback" || echo "none")

if [ "$ERRORS" = "none" ]; then
    echo -e "${GREEN}✓ No errors in logs${NC}"
else
    echo -e "${YELLOW}⚠ Recent errors found:${NC}"
    echo "$ERRORS"
fi

# Step 4: Test API
echo ""
echo -e "${YELLOW}[4/5] Testing API...${NC}"

# Health check
HEALTH=$(curl -s -m 5 http://localhost:8001/api/health 2>&1)
if echo "$HEALTH" | grep -q "ok"; then
    echo -e "${GREEN}✓ API is responding${NC}"
else
    echo -e "${RED}✗ API not responding${NC}"
    echo "Response: $HEALTH"
fi

# Admin login test
ADMIN=$(curl -s -X POST http://localhost:8001/api/admin/login \
    -H "Content-Type: application/json" \
    -d '{"username":"TempWork","password":"TempW_115500_e","code":"?X!Z*"}' 2>&1)

if echo "$ADMIN" | grep -q "token"; then
    echo -e "${GREEN}✓ Admin login works!${NC}"
else
    echo -e "${RED}✗ Admin login failed${NC}"
    echo "Response: $ADMIN"
fi

# Step 5: Test from browser
echo ""
echo -e "${YELLOW}[5/5] Browser access test...${NC}"

IP=$(hostname -I | awk '{print $1}')

# Test nginx proxy
PROXY_TEST=$(curl -s -m 5 http://localhost/api/health 2>&1)
if echo "$PROXY_TEST" | grep -q "ok"; then
    echo -e "${GREEN}✓ Nginx proxy working${NC}"
else
    echo -e "${YELLOW}⚠ Nginx proxy issue${NC}"
    echo "Response: $PROXY_TEST"
fi

echo ""
echo -e "${GREEN}═════════════════════════════════════${NC}"
echo -e "${GREEN}Fix Complete!${NC}"
echo -e "${GREEN}═════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}🌐 Try accessing now:${NC}"
echo -e "   Admin: ${GREEN}http://$IP/admin${NC}"
echo ""
echo -e "${BLUE}🔐 Login with:${NC}"
echo -e "   Code:     ${GREEN}?X!Z*${NC}"
echo -e "   Username: ${GREEN}TempWork${NC}"
echo -e "   Password: ${GREEN}TempW_115500_e${NC}"
echo ""

# Show last few log lines
echo -e "${BLUE}📋 Last 10 log lines:${NC}"
tail -10 /var/log/cryptovault-backend.log 2>/dev/null || echo "No logs yet"
echo ""

exit 0
