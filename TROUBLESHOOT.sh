#!/bin/bash

# CryptoVault Troubleshooting Script
# Run this if you encounter issues

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔════════════════════════════════════════════╗
║                                            ║
║     🔧 CryptoVault Troubleshooter         ║
║                                            ║
╚════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"

echo -e "${YELLOW}Checking system status...${NC}"
echo ""

# 1. Check services
echo -e "${BLUE}1. Services Status:${NC}"
echo -n "   MongoDB: "
if systemctl is-active --quiet mongod 2>/dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
elif pgrep mongod > /dev/null; then
    echo -e "${GREEN}✓ Running (no systemd)${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo -e "      Fix: ${YELLOW}systemctl start mongod${NC}"
fi

echo -n "   Backend: "
if systemctl is-active --quiet cryptovault-backend 2>/dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo -e "      Fix: ${YELLOW}systemctl start cryptovault-backend${NC}"
    echo ""
    echo -e "      ${YELLOW}Check logs:${NC}"
    echo -e "      journalctl -u cryptovault-backend -n 30"
fi

echo -n "   Nginx:   "
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "${GREEN}✓ Running${NC}"
elif pgrep nginx > /dev/null; then
    echo -e "${GREEN}✓ Running (no systemd)${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo -e "      Fix: ${YELLOW}systemctl start nginx${NC}"
fi
echo ""

# 2. Check ports
echo -e "${BLUE}2. Port Status:${NC}"
echo -n "   Port 8001 (API): "
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Open${NC}"
    PROC=$(lsof -Pi :8001 -sTCP:LISTEN | tail -1)
    echo "      $PROC"
else
    echo -e "${RED}✗ Nothing listening${NC}"
fi

echo -n "   Port 80 (Web):   "
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Open${NC}"
else
    echo -e "${RED}✗ Nothing listening${NC}"
fi
echo ""

# 3. Check API
echo -e "${BLUE}3. API Health Check:${NC}"
echo -n "   Testing http://localhost:8001/api/health ... "
HEALTH=$(curl -s http://localhost:8001/api/health 2>&1)
if echo "$HEALTH" | grep -q "ok"; then
    echo -e "${GREEN}✓ OK${NC}"
    echo "      Response: $HEALTH"
else
    echo -e "${RED}✗ Failed${NC}"
    echo "      Response: $HEALTH"
fi
echo ""

# 4. Check dependencies
echo -e "${BLUE}4. Python Dependencies:${NC}"
if [ -f "$BACKEND_DIR/venv/bin/python" ]; then
    echo -e "   Virtual environment: ${GREEN}✓ Found${NC}"
    echo -n "   Testing imports... "
    
    source "$BACKEND_DIR/venv/bin/activate"
    TEST=$(python3 -c "
import sys
try:
    import fastapi
    import uvicorn
    import motor
    import pymongo
    print('OK')
except ImportError as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1)
    deactivate
    
    if echo "$TEST" | grep -q "OK"; then
        echo -e "${GREEN}✓ All imports working${NC}"
    else
        echo -e "${RED}✗ Import failed${NC}"
        echo "      $TEST"
        echo -e "      Fix: ${YELLOW}cd $BACKEND_DIR && source venv/bin/activate && pip install -r requirements.txt${NC}"
    fi
else
    echo -e "   Virtual environment: ${RED}✗ Not found${NC}"
    echo -e "      Fix: ${YELLOW}cd $BACKEND_DIR && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt${NC}"
fi
echo ""

# 5. Show recent errors
echo -e "${BLUE}5. Recent Backend Errors (last 10 lines):${NC}"
if [ -f "/var/log/cryptovault-backend-error.log" ]; then
    tail -10 /var/log/cryptovault-backend-error.log 2>/dev/null | head -10
else
    journalctl -u cryptovault-backend -n 10 --no-pager 2>/dev/null | tail -10 || echo "   No logs found"
fi
echo ""

# 6. Quick fixes
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Quick Fixes:${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}If backend won't start:${NC}"
echo "1. Check logs: journalctl -u cryptovault-backend -f"
echo "2. Try manual run: cd $BACKEND_DIR && source venv/bin/activate && python3 server.py"
echo "3. Reinstall deps: cd $BACKEND_DIR && source venv/bin/activate && pip install --force-reinstall -r requirements.txt"
echo ""
echo -e "${BLUE}If port 8001 is blocked:${NC}"
echo "kill -9 \$(lsof -t -i:8001)"
echo ""
echo -e "${BLUE}If MongoDB won't start:${NC}"
echo "systemctl start mongod"
echo "# Or if no systemd:"
echo "mongod --fork --logpath /var/log/mongodb/mongod.log --dbpath /var/lib/mongodb"
echo ""
echo -e "${BLUE}Restart everything:${NC}"
echo "systemctl restart mongod cryptovault-backend nginx"
echo ""
echo -e "${BLUE}Re-deploy from scratch:${NC}"
echo "systemctl stop cryptovault-backend"
echo "cd $SCRIPT_DIR"
echo "bash DEPLOY_BULLETPROOF.sh"
echo ""
