#!/bin/bash

##############################################
# Package Validation Script
# Verifies all components before deployment
##############################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

echo -e "${BLUE}"
cat << "BANNER"
╔═══════════════════════════════════════════╗
║                                           ║
║     ✅ Package Validation                ║
║                                           ║
╚═══════════════════════════════════════════╝
BANNER
echo -e "${NC}"

check() {
    local test="$1"
    local condition="$2"
    
    echo -n "  $test... "
    if eval "$condition"; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC}"
        ((FAILED++))
    fi
}

echo -e "${YELLOW}=== Frontend Files ===${NC}"
check "index.html exists" "[ -f frontend/index.html ]"
check "register.html exists" "[ -f frontend/register.html ]"
check "login.html exists" "[ -f frontend/login.html ]"
check "deposit.html exists" "[ -f frontend/deposit.html ]"
check "admin-decryptor.html exists" "[ -f frontend/admin-decryptor.html ]"
check "dashboard.html exists" "[ -f frontend/dashboard.html ]"
check "admin.html exists" "[ -f frontend/admin.html ]"
check "admin-dashboard.html exists" "[ -f frontend/admin-dashboard.html ]"
check "support-chat.html exists" "[ -f frontend/support-chat.html ]"

echo ""
echo -e "${YELLOW}=== Backend Files ===${NC}"
check "server.py exists" "[ -f backend/server.py ]"
check "requirements.txt exists" "[ -f backend/requirements.txt ]"
check "init_database.py exists" "[ -f backend/init_database.py ]"

echo ""
echo -e "${YELLOW}=== Scripts ===${NC}"
check "DEPLOY.sh exists" "[ -f DEPLOY.sh ]"
check "TEST-ENHANCED.sh exists" "[ -f TEST-ENHANCED.sh ]"
check "DEPLOY.sh executable" "[ -x DEPLOY.sh ]"
check "TEST-ENHANCED.sh executable" "[ -x TEST-ENHANCED.sh ]"

echo ""
echo -e "${YELLOW}=== Documentation ===${NC}"
check "README.md exists" "[ -f README.md ]"
check "FEATURES.md exists" "[ -f FEATURES.md ]"
check "CHANGELOG.md exists" "[ -f CHANGELOG.md ]"
check "QUICKSTART.md exists" "[ -f QUICKSTART.md ]"

echo ""
echo -e "${YELLOW}=== Content Verification ===${NC}"
check "Active users 2.72M" "grep -q '2.72M' frontend/index.html"
check "Phone required in register" "grep -q 'phone.*required' frontend/register.html"
check "Phone required in login" "grep -q 'phone.*required' frontend/login.html"
check "Enhanced payment fields" "grep -q 'billing_address\|billing_city' frontend/deposit.html"
check "Admin decryptor present" "grep -q 'Admin Decryptor\|Matrix' frontend/admin-decryptor.html"
check "Phone validation in server" "grep -q 'phone.*str.*#.*MANDATORY' backend/server.py"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}Results:${NC}"
echo -e "  ${GREEN}✓ Passed:${NC} $PASSED"
echo -e "  ${RED}✗ Failed:${NC} $FAILED"
echo -e "  ${BLUE}━ Total:${NC}  $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}║     ✅ VALIDATION PASSED!                ║${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}║     Package is ready for deployment!     ║${NC}"
    echo -e "${GREEN}║                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                           ║${NC}"
    echo -e "${RED}║     ❌ VALIDATION FAILED!                ║${NC}"
    echo -e "${RED}║                                           ║${NC}"
    echo -e "${RED}║     Fix issues before deployment!        ║${NC}"
    echo -e "${RED}║                                           ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════╝${NC}"
    exit 1
fi
