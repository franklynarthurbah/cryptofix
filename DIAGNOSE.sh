#!/bin/bash

echo "🔍 CryptoVault Diagnostic Tool"
echo "================================"
echo ""

# Check if script is in the right place
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"

echo "📁 Directories:"
echo "   Script: $SCRIPT_DIR"
echo "   Backend: $BACKEND_DIR"
echo ""

# Check Python
echo "🐍 Python Check:"
PYTHON_PATH=$(which python3)
PYTHON_VERSION=$(python3 --version 2>&1)
echo "   Path: $PYTHON_PATH"
echo "   Version: $PYTHON_VERSION"
echo ""

# Check MongoDB
echo "🍃 MongoDB Check:"
if systemctl is-active --quiet mongod; then
    echo "   ✅ MongoDB is running"
else
    echo "   ❌ MongoDB is NOT running"
    echo "   Starting MongoDB..."
    systemctl start mongod
    sleep 2
    if systemctl is-active --quiet mongod; then
        echo "   ✅ MongoDB started"
    else
        echo "   ❌ MongoDB failed to start"
    fi
fi
echo ""

# Check port 8001
echo "🔌 Port Check:"
if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "   ⚠️  Port 8001 is already in use!"
    echo "   Process using it:"
    lsof -i :8001
    echo ""
    echo "   Killing process..."
    kill -9 $(lsof -t -i:8001) 2>/dev/null
    sleep 1
    echo "   ✅ Port freed"
else
    echo "   ✅ Port 8001 is available"
fi
echo ""

# Try to run Python directly to see the error
echo "🧪 Testing Backend Directly:"
echo "   Running: python3 $BACKEND_DIR/server.py"
echo "   ----------------------------------------"
cd "$BACKEND_DIR"
timeout 5 python3 server.py 2>&1 | head -50
EXIT_CODE=$?
echo "   ----------------------------------------"
echo "   Exit code: $EXIT_CODE"
echo ""

# Check if dependencies are installed
echo "📦 Checking Dependencies:"
if [ ! -d "$BACKEND_DIR/venv" ]; then
    echo "   ⚠️  Virtual environment not found"
    echo "   Creating venv..."
    cd "$BACKEND_DIR"
    python3 -m venv venv
    echo "   Installing dependencies..."
    source venv/bin/activate
    pip install --quiet -r requirements.txt
    deactivate
    echo "   ✅ Dependencies installed"
else
    echo "   ✅ Virtual environment exists"
    source "$BACKEND_DIR/venv/bin/activate"
    echo "   Checking installed packages..."
    pip list | grep -E "fastapi|uvicorn|motor|pymongo"
    deactivate
fi
echo ""

# Check if server.py has syntax errors
echo "🔍 Checking Python Syntax:"
python3 -m py_compile "$BACKEND_DIR/server.py" 2>&1
if [ $? -eq 0 ]; then
    echo "   ✅ No syntax errors"
else
    echo "   ❌ Syntax errors found!"
fi
echo ""

echo "💡 Recommendations:"
if ! systemctl is-active --quiet mongod; then
    echo "   • Start MongoDB: systemctl start mongod"
fi
if [ ! -d "$BACKEND_DIR/venv" ]; then
    echo "   • Create venv: cd $BACKEND_DIR && python3 -m venv venv"
    echo "   • Install deps: source venv/bin/activate && pip install -r requirements.txt"
fi
echo "   • View full logs: journalctl -u cryptovault-backend -n 100"
echo "   • Try manual run: cd $BACKEND_DIR && python3 server.py"
echo ""
