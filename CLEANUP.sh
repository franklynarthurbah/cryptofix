#!/bin/bash

##############################################
# CryptoVault Complete Cleanup & Fix Script
# Stops everything, cleans up, and prepares for fresh deployment
##############################################

set +e  # Don't exit on error for cleanup

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════╗
║                                           ║
║     🧹 CryptoVault Complete Cleanup      ║
║                                           ║
╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"

echo -e "${YELLOW}Stopping all services...${NC}"

# Stop backend service
echo -n "  Stopping backend service... "
systemctl stop cryptovault-backend 2>/dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}(not running)${NC}"

# Kill any process on port 8001
echo -n "  Killing processes on port 8001... "
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    kill -9 $(lsof -t -i:8001) 2>/dev/null
    sleep 2
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}(none found)${NC}"
fi

# Kill any uvicorn processes
echo -n "  Killing uvicorn processes... "
if pgrep -f "uvicorn" >/dev/null 2>&1; then
    pkill -9 -f "uvicorn" 2>/dev/null
    sleep 1
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}(none found)${NC}"
fi

# Kill any python processes running server.py
echo -n "  Killing server.py processes... "
if pgrep -f "server.py" >/dev/null 2>&1; then
    pkill -9 -f "server.py" 2>/dev/null
    sleep 1
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}(none found)${NC}"
fi

echo ""
echo -e "${YELLOW}Verifying port 8001 is free...${NC}"
sleep 2
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}✗ Port 8001 still in use!${NC}"
    echo "  Processes using it:"
    lsof -i :8001
    echo ""
    echo -e "${YELLOW}Force killing...${NC}"
    fuser -k 8001/tcp 2>/dev/null
    sleep 2
fi

if ! lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Port 8001 is free${NC}"
else
    echo -e "${RED}✗ Port 8001 still occupied${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Cleaning up old installations...${NC}"

# Remove old service file
echo -n "  Removing old service file... "
rm -f /etc/systemd/system/cryptovault-backend.service && echo -e "${GREEN}✓${NC}"

# Reload systemd
echo -n "  Reloading systemd... "
systemctl daemon-reload 2>/dev/null && echo -e "${GREEN}✓${NC}"

# Clean old venv if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/backend/venv" ]; then
    echo -n "  Removing old virtual environment... "
    rm -rf "$SCRIPT_DIR/backend/venv" && echo -e "${GREEN}✓${NC}"
fi

# Clean old logs
echo -n "  Cleaning old logs... "
rm -f /var/log/cryptovault-backend.log 2>/dev/null
rm -f /var/log/cryptovault-backend-error.log 2>/dev/null
echo -e "${GREEN}✓${NC}"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Cleanup Complete!                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}System is clean and ready for deployment.${NC}"
echo -e "${BLUE}Run: sudo bash DEPLOY_FINAL.sh${NC}"
echo ""
