#!/bin/bash

##############################################
# Configure CryptoVault Hostname
# Updates all files to use cryptovault.hopto.org
##############################################

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOSTNAME="cryptovault.hopto.org"
IP="164.92.138.206"

echo -e "${BLUE}Configuring hostname: $HOSTNAME${NC}"
echo ""

echo "Updating all HTML files..."
find frontend -name "*.html" -type f -exec sed -i \
    -e "s|http://localhost:8001|http://$HOSTNAME:8001|g" \
    -e "s|ws://localhost:8001|ws://$HOSTNAME:8001|g" \
    -e "s|http://164\.92\.138\.206:8001|http://$HOSTNAME:8001|g" \
    -e "s|ws://164\.92\.138\.206:8001|ws://$HOSTNAME:8001|g" \
    -e "s|http://$IP:8001|http://$HOSTNAME:8001|g" \
    -e "s|ws://$IP:8001|ws://$HOSTNAME:8001|g" \
    {} \;

echo -e "${GREEN}✓ Updated all HTML files${NC}"

echo ""
echo "Verification:"
echo "  Hostname: $HOSTNAME"
echo "  IP Address: $IP"
echo ""
echo -e "${GREEN}Configuration complete!${NC}"
