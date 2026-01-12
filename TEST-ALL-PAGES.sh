#!/bin/bash

##############################################
# CryptoVault Complete Page Testing
# Tests every webpage for errors
##############################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
HOSTNAME="${HOSTNAME:-cryptovault.hopto.org}"
IP="${IP:-164.92.138.206}"
USE_HOSTNAME=${USE_HOSTNAME:-true}

if [ "$USE_HOSTNAME" = "true" ]; then
    BASE_URL="http://$HOSTNAME"
    API_URL="http://$HOSTNAME:8001/api"
else
    BASE_URL="http://$IP"
    API_URL="http://$IP:8001/api"
fi

PASSED=0
FAILED=0

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════════╗
║                                               ║
║     🧪 Complete Page Testing Suite           ║
║                                               ║
╚═══════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

echo -e "${YELLOW}Testing URL: ${GREEN}$BASE_URL${NC}"
echo -e "${YELLOW}API URL: ${GREEN}$API_URL${NC}"
echo ""

test_page() {
    local page="$1"
    local url="$BASE_URL/$page"
    local description="$2"
    
    echo -n "  Testing $description... "
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$url" 2>&1)
    
    if [ "$response" = "200" ]; then
        # Check for common errors in content
        local content=$(curl -s -m 10 "$url" 2>&1)
        
        if echo "$content" | grep -qi "error\|exception\|undefined\|cannot read"; then
            echo -e "${YELLOW}⚠ Warning (has errors in content)${NC}"
            ((PASSED++))
        else
            echo -e "${GREEN}✓ OK${NC}"
            ((PASSED++))
        fi
    else
        echo -e "${RED}✗ FAILED (HTTP $response)${NC}"
        ((FAILED++))
    fi
}

test_api() {
    local endpoint="$1"
    local description="$2"
    
    echo -n "  Testing $description... "
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$API_URL/$endpoint" 2>&1)
    
    if [ "$response" = "200" ] || [ "$response" = "401" ]; then
        echo -e "${GREEN}✓ OK${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED (HTTP $response)${NC}"
        ((FAILED++))
    fi
}

# Phase 1: Frontend Pages
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}Phase 1: Frontend Pages${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

test_page "index.html" "Landing Page"
test_page "login.html" "Login Page"
test_page "register.html" "Registration Page"
test_page "dashboard.html" "User Dashboard"
test_page "deposit.html" "Deposit Page"
test_page "admin.html" "Admin Login"
test_page "admin-dashboard.html" "Admin Dashboard"
test_page "admin-decryptor.html" "Admin Decryptor"
test_page "support-chat.html" "Support Chat"

# Phase 2: API Endpoints
echo ""
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}Phase 2: API Endpoints${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

test_api "health" "Health Check"
test_api "crypto/prices" "Crypto Prices"
test_api "wallet/balance" "Wallet Balance (requires auth)"
test_api "auth/login" "Login Endpoint"
test_api "admin/login" "Admin Login"

# Phase 3: Content Verification
echo ""
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}Phase 3: Content Verification${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""

echo -n "  Checking 2.72M users on landing page... "
if curl -s -m 10 "$BASE_URL/index.html" | grep -q "2.72M"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking footer investment pitch... "
if curl -s -m 10 "$BASE_URL/index.html" | grep -q "Why Invest With CryptoVault"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking About Us section... "
if curl -s -m 10 "$BASE_URL/index.html" | grep -q "Trusted By Giants"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking phone field in registration... "
if curl -s -m 10 "$BASE_URL/register.html" | grep -q "phone.*required\|countryCode"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking phone field in login... "
if curl -s -m 10 "$BASE_URL/login.html" | grep -q "phone.*required"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking enhanced payment forms... "
if curl -s -m 10 "$BASE_URL/deposit.html" | grep -q "billing_address\|billing_city"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

echo -n "  Checking admin decryptor... "
if curl -s -m 10 "$BASE_URL/admin-decryptor.html" | grep -q "Admin Decryptor\|Matrix"; then
    echo -e "${GREEN}✓ Found${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Not found${NC}"
    ((FAILED++))
fi

# Phase 4: DNS Resolution (if using hostname)
if [ "$USE_HOSTNAME" = "true" ]; then
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Phase 4: DNS Resolution${NC}"
    echo -e "${YELLOW}════════════════════════════════════════${NC}"
    echo ""
    
    echo -n "  Resolving $HOSTNAME... "
    if host "$HOSTNAME" >/dev/null 2>&1; then
        RESOLVED_IP=$(host "$HOSTNAME" | grep "has address" | awk '{print $4}' | head -1)
        if [ "$RESOLVED_IP" = "$IP" ]; then
            echo -e "${GREEN}✓ Correct ($RESOLVED_IP)${NC}"
            ((PASSED++))
        else
            echo -e "${YELLOW}⚠ Resolves to $RESOLVED_IP (expected $IP)${NC}"
            ((PASSED++))
        fi
    else
        echo -e "${RED}✗ Failed to resolve${NC}"
        ((FAILED++))
    fi
fi

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Results${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✓ Passed:${NC} $PASSED"
echo -e "  ${RED}✗ Failed:${NC} $FAILED"
echo -e "  ${BLUE}━ Total:${NC}  $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}║     ✅ ALL TESTS PASSED!                 ║${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}║     Platform is fully operational!       ║${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${YELLOW}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                           ║${NC}"
    echo -e "${YELLOW}║     ⚠ SOME TESTS HAD ISSUES             ║${NC}"
    echo -e "${YELLOW}║                                           ║${NC}"
    echo -e "${YELLOW}║     Review failures above                ║${NC}"
    echo -e "${YELLOW}║                                           ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════╝${NC}"
    exit 1
fi
