from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect, UploadFile, File, Form, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator
import re
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from motor.motor_asyncio import AsyncIOMotorClient
import jwt
import bcrypt
import os
import uuid
import httpx
from pathlib import Path
import asyncio
from bson import ObjectId
import json

# ========================================
# CRITICAL: MongoDB Serialization Helpers
# ========================================

def serialize_objectid(obj):
    """Convert ObjectId to string"""
    if isinstance(obj, ObjectId):
        return str(obj)
    return obj

def serialize_doc(doc: Any) -> Any:
    """Convert MongoDB document to JSON-serializable format - COMPREHENSIVE"""
    if doc is None:
        return None
    
    if isinstance(doc, ObjectId):
        return str(doc)
    
    if isinstance(doc, datetime):
        return doc.isoformat()
    
    if isinstance(doc, dict):
        serialized = {}
        for key, value in doc.items():
            # Skip MongoDB internal fields
            if key == '_id':
                serialized['id'] = str(value) if isinstance(value, ObjectId) else value
            else:
                serialized[key] = serialize_doc(value)
        return serialized
    
    if isinstance(doc, list):
        return [serialize_doc(item) for item in doc]
    
    # Handle bytes, sets, etc.
    if isinstance(doc, bytes):
        return doc.decode('utf-8', errors='ignore')
    
    if isinstance(doc, set):
        return list(doc)
    
    return doc

def serialize_docs(docs: list) -> list:
    """Convert list of MongoDB documents to JSON-serializable format"""
    if not docs:
        return []
    return [serialize_doc(doc) for doc in docs]

class CustomJSONResponse(JSONResponse):
    """Custom JSON response that handles MongoDB types"""
    def render(self, content: Any) -> bytes:
        return json.dumps(
            serialize_doc(content),
            ensure_ascii=False,
            allow_nan=False,
            indent=None,
            separators=(",", ":"),
        ).encode("utf-8")

# Configuration
SECRET_KEY = os.getenv("JWT_SECRET", "cryptovault-secret-key-2026")
MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
DB_NAME = os.getenv("DB_NAME", "cryptovault")
COINGECKO_API = "https://api.coingecko.com/api/v3"

app = FastAPI(
    title="CryptoVault Enhanced API", 
    version="3.1.0",
    default_response_class=CustomJSONResponse  # Use custom response class
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

mongo_client = AsyncIOMotorClient(MONGO_URL)
db = mongo_client[DB_NAME]
security = HTTPBearer()

UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# Supported Cryptocurrencies (INCLUDING MONERO)
SUPPORTED_CRYPTOS = ["BTC", "ETH", "USDT", "BNB", "SOL", "XRP", "ADA", "DOT", "XMR"]

# Data Models

# Data Models with MANDATORY phone
class UserRegister(BaseModel):
    email: str
    password: str
    full_name: str
    phone: str  # MANDATORY PHONE NUMBER
    
    @field_validator('email')
    @classmethod
    def validate_email(cls, v):
        if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', v):
            raise ValueError('Invalid email format')
        return v.lower()
    
    @field_validator('phone')
    @classmethod
    def validate_phone(cls, v):
        if not v or len(v) < 8:
            raise ValueError('Phone number is REQUIRED and must be valid')
        return v

class UserLogin(BaseModel):
    email: str
    password: str
    phone: str  # MANDATORY PHONE NUMBER FOR LOGIN
    
    @field_validator('email')
    @classmethod
    def validate_email(cls, v):
        return v.lower()
    
    @field_validator('phone')
    @classmethod
    def validate_phone(cls, v):
        if not v or len(v) < 8:
            raise ValueError('Phone number is REQUIRED for login')
        return v

class AdminLogin(BaseModel):
    username: str
    password: str
    code: Optional[str] = None

class TradeRequest(BaseModel):
    crypto: str
    amount: float
    price: float
    type: str

class WithdrawRequest(BaseModel):
    crypto: str
    amount: float
    wallet_address: str
    network: str

class MiningRequest(BaseModel):
    crypto: str
    action: str

class KYCSubmission(BaseModel):
    full_name: str
    date_of_birth: str
    address: str
    country: str
    id_type: str
    id_number: str

class WalletOperationRequest(BaseModel):
    user_id: str
    crypto: str
    amount: float
    operation: str
    notes: Optional[str] = None

class WalletAddressRequest(BaseModel):
    user_id: str
    crypto: str
    address: str
    network: str

class PaymentRequest(BaseModel):
    payment_method: str
    amount: float
    crypto: str
    bank_name: Optional[str] = None
    account_number: Optional[str] = None
    account_name: Optional[str] = None
    routing_number: Optional[str] = None
    card_number: Optional[str] = None
    card_holder: Optional[str] = None
    expiry_date: Optional[str] = None
    cvv: Optional[str] = None
    from_address: Optional[str] = None
    transaction_hash: Optional[str] = None
    network: Optional[str] = None

class PaymentVerification(BaseModel):
    payment_id: str
    status: str
    notes: Optional[str] = None

# WebSocket Manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}
        self.admin_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket, user_id: str):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)

    async def connect_admin(self, websocket: WebSocket):
        await websocket.accept()
        self.admin_connections.append(websocket)

    def disconnect(self, websocket: WebSocket, user_id: str):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)

    def disconnect_admin(self, websocket: WebSocket):
        if websocket in self.admin_connections:
            self.admin_connections.remove(websocket)

    async def send_personal_message(self, message: dict, user_id: str):
        """Send SERIALIZED message to specific user"""
        serialized_message = serialize_doc(message)  # CRITICAL FIX
        if user_id in self.active_connections:
            dead_connections = []
            for connection in self.active_connections[user_id]:
                try:
                    await connection.send_json(serialized_message)
                except Exception as e:
                    dead_connections.append(connection)
            
            for conn in dead_connections:
                self.active_connections[user_id].remove(conn)

    async def send_to_admin(self, message: dict):
        """Send SERIALIZED message to all admins"""
        serialized_message = serialize_doc(message)  # CRITICAL FIX
        dead_connections = []
        for connection in self.admin_connections:
            try:
                await connection.send_json(serialized_message)
            except Exception as e:
                dead_connections.append(connection)
        
        for conn in dead_connections:
            self.admin_connections.remove(conn)

    async def broadcast(self, message: dict):
        """Broadcast SERIALIZED message to all users"""
        serialized_message = serialize_doc(message)  # CRITICAL FIX
        for user_id, connections in self.active_connections.items():
            for connection in connections:
                try:
                    await connection.send_json(serialized_message)
                except:
                    pass

manager = ConnectionManager()

# Helper Functions
def create_token(data: dict, expiration_hours: int = 24) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(hours=expiration_hours)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm="HS256")

def verify_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        return payload
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    payload = verify_token(token)
    user_id = payload.get("user_id")
    user = await db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return serialize_doc(user)  # CRITICAL FIX

async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    payload = verify_token(token)
    admin_id = payload.get("admin_id")
    admin = await db.admins.find_one({"id": admin_id})
    if not admin:
        raise HTTPException(status_code=404, detail="Admin not found")
    return serialize_doc(admin)  # CRITICAL FIX

async def fetch_live_prices() -> Dict[str, float]:
    """Fetch live cryptocurrency prices including Monero"""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{COINGECKO_API}/simple/price",
                params={
                    "ids": "bitcoin,ethereum,tether,binancecoin,solana,ripple,cardano,polkadot,monero",
                    "vs_currencies": "usd"
                },
                timeout=10.0
            )
            data = response.json()
            return {
                "BTC": data.get("bitcoin", {}).get("usd", 45000),
                "ETH": data.get("ethereum", {}).get("usd", 2500),
                "USDT": data.get("tether", {}).get("usd", 1),
                "BNB": data.get("binancecoin", {}).get("usd", 300),
                "SOL": data.get("solana", {}).get("usd", 100),
                "XRP": data.get("ripple", {}).get("usd", 0.5),
                "ADA": data.get("cardano", {}).get("usd", 0.4),
                "DOT": data.get("polkadot", {}).get("usd", 7.5),
                "XMR": data.get("monero", {}).get("usd", 155),
            }
    except:
        return {
            "BTC": 45000, "ETH": 2500, "USDT": 1, "BNB": 300,
            "SOL": 100, "XRP": 0.5, "ADA": 0.4, "DOT": 7.5, "XMR": 155
        }

MINING_RATES = {
    "BTC": 0.00001, "ETH": 0.0001, "BNB": 0.001, "SOL": 0.01,
    "USDT": 0.1, "XRP": 1.0, "ADA": 1.0, "DOT": 0.1, "XMR": 0.005,
}

# Startup
@app.on_event("startup")
async def startup_db():
    await db.users.create_index("email", unique=True)
    await db.users.create_index("id", unique=True)
    await db.admins.create_index("username", unique=True)
    
    admin_exists = await db.admins.find_one({"username": "TempWork"})
    if not admin_exists:
        admin_password = bcrypt.hashpw("TempW_115500_e".encode(), bcrypt.gensalt())
        await db.admins.insert_one({
            "id": str(uuid.uuid4()),
            "username": "TempWork",
            "email": "pangolin890@gmail.com",
            "password_hash": admin_password.decode(),
            "two_fa_enabled": False,
            "created_at": datetime.utcnow().isoformat()
        })
    print("✅ CryptoVault Enhanced API v3.1 Started - SERIALIZATION FIXED!")

# Authentication
@app.post("/api/auth/register")
async def register(user: UserRegister):
    existing = await db.users.find_one({"email": user.email})
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    hashed_password = bcrypt.hashpw(user.password.encode(), bcrypt.gensalt())
    user_id = str(uuid.uuid4())
    
    user_data = {
        "id": user_id,
        "email": user.email,
        "full_name": user.full_name,
        "phone": user.phone,
        "password_hash": hashed_password.decode(),
        "balances": {"BTC": 0, "ETH": 0, "USDT": 1000, "BNB": 0, "SOL": 0, "XRP": 0, "ADA": 0, "DOT": 0, "XMR": 0},
        "wallet_addresses": {},
        "kyc_status": "not_submitted",
        "kyc_verified": False,
        "mining_active": {},
        "total_earnings": 0,
        "created_at": datetime.utcnow().isoformat()
    }
    
    await db.users.insert_one(user_data)
    token = create_token({"user_id": user_id})
    
    # Return serialized user data
    return {
        "token": token,
        "user": {
            "id": user_id,
            "email": user.email,
            "full_name": user.full_name,
            "balances": user_data["balances"]
        }
    }

@app.post("/api/auth/login")
async def login(credentials: UserLogin):
    user = await db.users.find_one({"email": credentials.email})
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    # Verify password
    if not bcrypt.checkpw(credentials.password.encode(), user["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    # VERIFY PHONE NUMBER - MANDATORY FOR LOGIN
    if not user.get("phone") or user["phone"] != credentials.phone:
        raise HTTPException(
            status_code=401, 
            detail="Phone number verification failed. The phone number you provided does not match our records. Phone verification is REQUIRED for secure login."
        )
    
    token = create_token({"user_id": user["id"]})
    
    # Return serialized response
    return {
        "token": token,
        "user": {
            "id": user["id"],
            "email": user["email"],
            "full_name": user["full_name"],
            "phone": user["phone"],
            "kyc_verified": user.get("kyc_verified", False),
            "kyc_status": user.get("kyc_status", "not_submitted"),
            "balances": user.get("balances", {})
        }
    }

@app.post("/api/admin/login")
async def admin_login(credentials: AdminLogin):
    if credentials.code != "?X!Z*":
        raise HTTPException(status_code=403, detail="Invalid access code")
    
    admin = await db.admins.find_one({"username": credentials.username})
    if not admin or not bcrypt.checkpw(credentials.password.encode(), admin["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    token = create_token({"admin_id": admin["id"]})
    
    return {
        "token": token,
        "admin": {
            "id": admin["id"],
            "username": admin["username"],
            "email": admin["email"]
        }
    }

# Crypto Prices
@app.get("/api/crypto/prices")
async def get_crypto_prices():
    prices = await fetch_live_prices()
    return {
        "prices": prices,
        "supported_cryptos": SUPPORTED_CRYPTOS,
        "timestamp": datetime.utcnow().isoformat()
    }

# Trading
@app.post("/api/crypto/buy")
async def buy_crypto(trade: TradeRequest, user: dict = Depends(get_current_user)):
    if trade.crypto not in SUPPORTED_CRYPTOS:
        raise HTTPException(status_code=400, detail="Cryptocurrency not supported")
    
    prices = await fetch_live_prices()
    current_price = prices.get(trade.crypto)
    
    total_cost = trade.amount * current_price
    if user["balances"].get("USDT", 0) < total_cost:
        raise HTTPException(status_code=400, detail="Insufficient USDT balance")
    
    new_balances = user["balances"].copy()
    new_balances["USDT"] -= total_cost
    new_balances[trade.crypto] = new_balances.get(trade.crypto, 0) + trade.amount
    
    await db.users.update_one({"id": user["id"]}, {"$set": {"balances": new_balances}})
    
    trade_record = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "type": "buy",
        "crypto": trade.crypto,
        "amount": trade.amount,
        "price": current_price,
        "total": total_cost,
        "created_at": datetime.utcnow().isoformat()
    }
    await db.trades.insert_one(trade_record)
    
    # Send SERIALIZED WebSocket message
    await manager.send_personal_message({
        "type": "trade_complete",
        "trade": trade_record,
        "balances": new_balances
    }, user["id"])
    
    return {"success": True, "trade": trade_record, "new_balances": new_balances}

@app.post("/api/crypto/sell")
async def sell_crypto(trade: TradeRequest, user: dict = Depends(get_current_user)):
    if trade.crypto not in SUPPORTED_CRYPTOS:
        raise HTTPException(status_code=400, detail="Cryptocurrency not supported")
    
    prices = await fetch_live_prices()
    current_price = prices.get(trade.crypto)
    
    if user["balances"].get(trade.crypto, 0) < trade.amount:
        raise HTTPException(status_code=400, detail=f"Insufficient {trade.crypto} balance")
    
    total_value = trade.amount * current_price
    new_balances = user["balances"].copy()
    new_balances[trade.crypto] -= trade.amount
    new_balances["USDT"] = new_balances.get("USDT", 0) + total_value
    
    await db.users.update_one({"id": user["id"]}, {"$set": {"balances": new_balances}})
    
    trade_record = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "type": "sell",
        "crypto": trade.crypto,
        "amount": trade.amount,
        "price": current_price,
        "total": total_value,
        "created_at": datetime.utcnow().isoformat()
    }
    await db.trades.insert_one(trade_record)
    
    await manager.send_personal_message({
        "type": "trade_complete",
        "trade": trade_record,
        "balances": new_balances
    }, user["id"])
    
    return {"success": True, "trade": trade_record, "new_balances": new_balances}

# Withdrawal (WITH KYC)
@app.post("/api/crypto/withdraw")
async def withdraw_crypto(withdraw: WithdrawRequest, user: dict = Depends(get_current_user)):
    if not user.get("kyc_verified", False):
        raise HTTPException(
            status_code=403,
            detail="KYC verification required. Please complete KYC verification before withdrawing funds."
        )
    
    if withdraw.crypto not in SUPPORTED_CRYPTOS:
        raise HTTPException(status_code=400, detail="Cryptocurrency not supported")
    
    if user["balances"].get(withdraw.crypto, 0) < withdraw.amount:
        raise HTTPException(status_code=400, detail=f"Insufficient {withdraw.crypto} balance")
    
    new_balances = user["balances"].copy()
    new_balances[withdraw.crypto] -= withdraw.amount
    
    await db.users.update_one({"id": user["id"]}, {"$set": {"balances": new_balances}})
    
    withdrawal_record = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "crypto": withdraw.crypto,
        "amount": withdraw.amount,
        "wallet_address": withdraw.wallet_address,
        "network": withdraw.network,
        "status": "pending",
        "created_at": datetime.utcnow().isoformat()
    }
    await db.withdrawals.insert_one(withdrawal_record)
    
    await manager.send_to_admin({
        "type": "new_withdrawal",
        "withdrawal": withdrawal_record,
        "user": {"id": user["id"], "email": user["email"], "full_name": user["full_name"]}
    })
    
    await manager.send_personal_message({
        "type": "withdrawal_submitted",
        "withdrawal": withdrawal_record
    }, user["id"])
    
    return {
        "success": True,
        "message": "Withdrawal request submitted.",
        "withdrawal": withdrawal_record,
        "new_balances": new_balances
    }

# Mining
@app.post("/api/mining/start")
async def start_mining(request: MiningRequest, user: dict = Depends(get_current_user)):
    if request.crypto not in MINING_RATES:
        raise HTTPException(status_code=400, detail="Invalid cryptocurrency for mining")
    
    mining_session = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "crypto": request.crypto,
        "rate": MINING_RATES[request.crypto],
        "started_at": datetime.utcnow().isoformat(),
        "active": True
    }
    await db.mining_sessions.insert_one(mining_session)
    
    mining_active = user.get("mining_active", {})
    mining_active[request.crypto] = True
    await db.users.update_one({"id": user["id"]}, {"$set": {"mining_active": mining_active}})
    
    return {
        "success": True,
        "message": f"Mining {request.crypto} started",
        "rate": MINING_RATES[request.crypto],
        "session": mining_session
    }

@app.post("/api/mining/stop")
async def stop_mining(request: MiningRequest, user: dict = Depends(get_current_user)):
    session = await db.mining_sessions.find_one({"user_id": user["id"], "crypto": request.crypto, "active": True})
    if not session:
        raise HTTPException(status_code=400, detail="No active mining session")
    
    start_time = datetime.fromisoformat(session["started_at"])
    end_time = datetime.utcnow()
    hours = (end_time - start_time).total_seconds() / 3600
    earnings = hours * session["rate"]
    
    new_balances = user["balances"].copy()
    new_balances[request.crypto] = new_balances.get(request.crypto, 0) + earnings
    total_earnings = user.get("total_earnings", 0) + earnings
    
    await db.users.update_one({"id": user["id"]}, {"$set": {"balances": new_balances, "total_earnings": total_earnings}})
    await db.mining_sessions.update_one({"id": session["id"]}, {"$set": {"active": False, "stopped_at": end_time.isoformat(), "earnings": earnings}})
    
    mining_active = user.get("mining_active", {})
    mining_active[request.crypto] = False
    await db.users.update_one({"id": user["id"]}, {"$set": {"mining_active": mining_active}})
    
    return {
        "success": True,
        "earnings": earnings,
        "crypto": request.crypto,
        "duration_hours": hours,
        "new_balances": new_balances
    }

@app.get("/api/mining/status")
async def mining_status(user: dict = Depends(get_current_user)):
    sessions = await db.mining_sessions.find({"user_id": user["id"], "active": True}).to_list(length=None)
    current_earnings = {}
    for session in sessions:
        start_time = datetime.fromisoformat(session["started_at"])
        hours = (datetime.utcnow() - start_time).total_seconds() / 3600
        earnings = hours * session["rate"]
        current_earnings[session["crypto"]] = earnings
    
    return {
        "active_sessions": len(sessions),
        "current_earnings": current_earnings,
        "sessions": serialize_docs(sessions)  # CRITICAL FIX
    }

# KYC
@app.post("/api/kyc/submit")
async def submit_kyc(kyc: KYCSubmission, user: dict = Depends(get_current_user)):
    if user.get("kyc_verified"):
        raise HTTPException(status_code=400, detail="KYC already verified")
    
    kyc_data = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        **kyc.dict(),
        "status": "pending",
        "submitted_at": datetime.utcnow().isoformat()
    }
    await db.kyc_submissions.insert_one(kyc_data)
    await db.users.update_one({"id": user["id"]}, {"$set": {"kyc_status": "pending"}})
    
    await manager.send_to_admin({
        "type": "new_kyc_submission",
        "kyc": kyc_data,
        "user": {"id": user["id"], "email": user["email"], "full_name": user["full_name"]}
    })
    
    return {"success": True, "message": "KYC submitted for review"}

@app.post("/api/kyc/upload")
async def upload_kyc_document(file: UploadFile = File(...), doc_type: str = Form(...), user: dict = Depends(get_current_user)):
    file_ext = file.filename.split(".")[-1]
    filename = f"kyc_{user['id']}_{doc_type}_{uuid.uuid4()}.{file_ext}"
    file_path = UPLOAD_DIR / filename
    
    with open(file_path, "wb") as f:
        content = await file.read()
        f.write(content)
    
    await db.kyc_documents.insert_one({
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "doc_type": doc_type,
        "filename": filename,
        "path": str(file_path),
        "uploaded_at": datetime.utcnow().isoformat()
    })
    
    return {"success": True, "filename": filename}

@app.get("/api/kyc/status")
async def kyc_status(user: dict = Depends(get_current_user)):
    submission = await db.kyc_submissions.find_one({"user_id": user["id"]})
    documents = await db.kyc_documents.find({"user_id": user["id"]}).to_list(length=None)
    
    return {
        "status": user.get("kyc_status", "not_submitted"),
        "verified": user.get("kyc_verified", False),
        "submission": serialize_doc(submission),  # CRITICAL FIX
        "documents": len(documents),
        "can_withdraw": user.get("kyc_verified", False)
    }

# CHAT SYSTEM
@app.post("/api/chat/send")
async def send_chat_message(
    message: str = Form(...),
    file: Optional[UploadFile] = File(None),
    user: dict = Depends(get_current_user)
):
    file_url = None
    if file:
        file_ext = file.filename.split(".")[-1]
        filename = f"chat_{user['id']}_{uuid.uuid4()}.{file_ext}"
        file_path = UPLOAD_DIR / filename
        with open(file_path, "wb") as f:
            f.write(await file.read())
        file_url = f"/uploads/{filename}"
    
    chat_msg = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "sender": "user",
        "sender_name": user["full_name"],
        "sender_email": user["email"],
        "message": message,
        "file_url": file_url,
        "read": False,
        "created_at": datetime.utcnow().isoformat()
    }
    await db.chat_messages.insert_one(chat_msg)
    
    await manager.send_to_admin({
        "type": "new_chat_message",
        "message": chat_msg,
        "user": {"id": user["id"], "name": user["full_name"], "email": user["email"]}
    })
    
    return {"success": True, "message": chat_msg}

@app.get("/api/chat/messages")
async def get_chat_messages(user: dict = Depends(get_current_user)):
    messages = await db.chat_messages.find({"user_id": user["id"]}).sort("created_at", 1).to_list(length=None)
    
    await db.chat_messages.update_many(
        {"user_id": user["id"], "sender": "admin", "read": False},
        {"$set": {"read": True}}
    )
    
    return {"messages": serialize_docs(messages)}  # CRITICAL FIX

@app.get("/api/chat/unread-count")
async def get_unread_count(user: dict = Depends(get_current_user)):
    count = await db.chat_messages.count_documents({
        "user_id": user["id"],
        "sender": "admin",
        "read": False
    })
    return {"unread_count": count}

# PAYMENT SYSTEM
@app.post("/api/payments/submit")
async def submit_payment(payment: PaymentRequest, user: dict = Depends(get_current_user)):
    payment_data = {
        "id": str(uuid.uuid4()),
        "user_id": user["id"],
        "user_email": user["email"],
        "user_name": user["full_name"],
        "status": "pending",
        "verified": False,
        **payment.dict(),
        "submitted_at": datetime.utcnow().isoformat()
    }
    
    await db.payments.insert_one(payment_data)
    
    await manager.send_to_admin({"type": "new_payment", "payment": payment_data})
    await manager.send_personal_message({
        "type": "payment_submitted",
        "payment": payment_data,
        "message": "Payment submitted for verification."
    }, user["id"])
    
    return {
        "success": True,
        "message": "Payment submitted for verification",
        "payment_id": payment_data["id"],
        "payment": payment_data
    }

@app.get("/api/payments/my-payments")
async def get_my_payments(user: dict = Depends(get_current_user)):
    payments = await db.payments.find({"user_id": user["id"]}).sort("submitted_at", -1).to_list(length=None)
    return {"payments": serialize_docs(payments), "total": len(payments)}  # CRITICAL FIX

# Wallet
@app.get("/api/wallet/balance")
async def get_wallet_balance(user: dict = Depends(get_current_user)):
    trades = await db.trades.find({"user_id": user["id"]}).sort("created_at", -1).limit(10).to_list(length=None)
    
    return {
        "balances": user.get("balances", {}),
        "wallet_addresses": user.get("wallet_addresses", {}),
        "total_earnings": user.get("total_earnings", 0),
        "recent_trades": serialize_docs(trades),  # CRITICAL FIX
        "kyc_verified": user.get("kyc_verified", False),
        "kyc_status": user.get("kyc_status", "not_submitted")
    }

@app.get("/api/wallet/transactions")
async def get_wallet_transactions(user: dict = Depends(get_current_user)):
    trades = await db.trades.find({"user_id": user["id"]}).sort("created_at", -1).to_list(length=None)
    mining = await db.mining_sessions.find({"user_id": user["id"]}).sort("started_at", -1).limit(20).to_list(length=None)
    withdrawals = await db.withdrawals.find({"user_id": user["id"]}).sort("created_at", -1).to_list(length=None)
    
    transactions = []
    for trade in trades:
        transactions.append({
            "id": trade["id"],
            "type": "trade",
            "action": trade["type"],
            "crypto": trade["crypto"],
            "amount": trade["amount"],
            "price": trade.get("price", 0),
            "total": trade.get("total", 0),
            "timestamp": trade["created_at"]
        })
    
    for mine in mining:
        transactions.append({
            "id": mine["id"],
            "type": "mining",
            "action": "mining",
            "crypto": mine["crypto"],
            "amount": mine.get("earnings", 0),
            "rate": mine.get("rate", 0),
            "active": mine.get("active", False),
            "timestamp": mine["started_at"]
        })
    
    for withdrawal in withdrawals:
        transactions.append({
            "id": withdrawal["id"],
            "type": "withdrawal",
            "action": "withdraw",
            "crypto": withdrawal["crypto"],
            "amount": withdrawal["amount"],
            "status": withdrawal.get("status", "pending"),
            "wallet_address": withdrawal["wallet_address"],
            "timestamp": withdrawal["created_at"]
        })
    
    transactions.sort(key=lambda x: x["timestamp"], reverse=True)
    
    return {"transactions": transactions, "total": len(transactions)}

# Admin Endpoints
@app.get("/api/admin/users")
async def get_all_users(admin: dict = Depends(get_current_admin)):
    users = await db.users.find().to_list(length=None)
    
    # Remove sensitive data and serialize
    clean_users = []
    for user in users:
        user.pop("password_hash", None)
        clean_users.append(serialize_doc(user))
    
    return {"users": clean_users, "total": len(clean_users)}  # CRITICAL FIX

@app.post("/api/admin/wallet/set-address")
async def admin_set_wallet_address(request: WalletAddressRequest, admin: dict = Depends(get_current_admin)):
    user = await db.users.find_one({"id": request.user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    wallet_addresses = user.get("wallet_addresses", {})
    wallet_addresses[request.crypto] = {
        "address": request.address,
        "network": request.network,
        "updated_at": datetime.utcnow().isoformat()
    }
    
    await db.users.update_one(
        {"id": request.user_id},
        {"$set": {"wallet_addresses": wallet_addresses}}
    )
    
    await manager.send_personal_message({
        "type": "wallet_address_updated",
        "crypto": request.crypto,
        "address": request.address,
        "network": request.network
    }, request.user_id)
    
    return {
        "success": True,
        "message": f"{request.crypto} wallet address set successfully",
        "wallet_addresses": wallet_addresses
    }

@app.post("/api/admin/wallet/credit")
async def admin_wallet_operation(request: WalletOperationRequest, admin: dict = Depends(get_current_admin)):
    user = await db.users.find_one({"id": request.user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if request.crypto not in SUPPORTED_CRYPTOS:
        raise HTTPException(status_code=400, detail="Cryptocurrency not supported")
    
    new_balances = user.get("balances", {}).copy()
    current_balance = new_balances.get(request.crypto, 0)
    
    if request.operation == "credit":
        new_balance = current_balance + request.amount
    elif request.operation == "debit":
        if current_balance < request.amount:
            raise HTTPException(status_code=400, detail="Insufficient balance")
        new_balance = current_balance - request.amount
    else:
        raise HTTPException(status_code=400, detail="Invalid operation")
    
    new_balances[request.crypto] = new_balance
    
    await db.users.update_one(
        {"id": request.user_id},
        {"$set": {"balances": new_balances}}
    )
    
    transaction_record = {
        "id": str(uuid.uuid4()),
        "user_id": request.user_id,
        "type": "admin_operation",
        "operation": request.operation,
        "crypto": request.crypto,
        "amount": request.amount,
        "previous_balance": current_balance,
        "new_balance": new_balance,
        "notes": request.notes or "",
        "admin_id": admin["id"],
        "created_at": datetime.utcnow().isoformat()
    }
    await db.admin_transactions.insert_one(transaction_record)
    
    await manager.send_personal_message({
        "type": "balance_update",
        "crypto": request.crypto,
        "operation": request.operation,
        "amount": request.amount,
        "new_balance": new_balance
    }, request.user_id)
    
    return {
        "success": True,
        "message": f"Wallet {request.operation} successful",
        "crypto": request.crypto,
        "amount": request.amount,
        "previous_balance": current_balance,
        "new_balance": new_balance,
        "new_balances": new_balances
    }

@app.get("/api/admin/kyc-pending")
async def get_pending_kyc(admin: dict = Depends(get_current_admin)):
    submissions = await db.kyc_submissions.find({"status": "pending"}).to_list(length=None)
    
    for submission in submissions:
        user = await db.users.find_one({"id": submission["user_id"]})
        if user:
            submission["user"] = {"email": user["email"], "full_name": user["full_name"]}
    
    return {"submissions": serialize_docs(submissions), "total": len(submissions)}  # CRITICAL FIX

@app.post("/api/admin/kyc-approve/{user_id}")
async def approve_kyc(user_id: str, admin: dict = Depends(get_current_admin)):
    await db.users.update_one({"id": user_id}, {"$set": {"kyc_verified": True, "kyc_status": "approved"}})
    await db.kyc_submissions.update_one({"user_id": user_id}, {"$set": {"status": "approved", "approved_at": datetime.utcnow().isoformat()}})
    
    await manager.send_personal_message({
        "type": "kyc_approved",
        "message": "Your KYC verification has been approved! You can now withdraw funds."
    }, user_id)
    
    return {"success": True}

@app.post("/api/admin/kyc-reject/{user_id}")
async def reject_kyc(user_id: str, reason: str, admin: dict = Depends(get_current_admin)):
    await db.users.update_one({"id": user_id}, {"$set": {"kyc_verified": False, "kyc_status": "rejected"}})
    await db.kyc_submissions.update_one({"user_id": user_id}, {"$set": {"status": "rejected", "reason": reason, "rejected_at": datetime.utcnow().isoformat()}})
    
    await manager.send_personal_message({"type": "kyc_rejected", "reason": reason}, user_id)
    
    return {"success": True}

# ADMIN CHAT
@app.get("/api/admin/chat-messages")
async def get_admin_chat_messages(admin: dict = Depends(get_current_admin)):
    messages = await db.chat_messages.find().sort("created_at", -1).limit(500).to_list(length=None)
    user_chats = {}
    
    for msg in messages:
        user_id = msg["user_id"]
        if user_id not in user_chats:
            user = await db.users.find_one({"id": user_id})
            if user:
                unread = await db.chat_messages.count_documents({
                    "user_id": user_id,
                    "sender": "user",
                    "read": False
                })
                user_chats[user_id] = {
                    "user": {
                        "id": user_id,
                        "name": user.get("full_name", "Unknown"),
                        "email": user.get("email", "")
                    },
                    "messages": [],
                    "unread_count": unread
                }
        if user_id in user_chats:
            user_chats[user_id]["messages"].append(serialize_doc(msg))  # CRITICAL FIX
    
    chats_list = list(user_chats.values())
    for chat in chats_list:
        chat["messages"].sort(key=lambda x: x["created_at"])
    
    return {"chats": chats_list, "total": len(chats_list)}

@app.post("/api/admin/chat-reply")
async def admin_chat_reply(
    user_id: str = Form(...),
    message: str = Form(...),
    file: Optional[UploadFile] = File(None),
    admin: dict = Depends(get_current_admin)
):
    file_url = None
    if file:
        file_ext = file.filename.split(".")[-1]
        filename = f"admin_chat_{uuid.uuid4()}.{file_ext}"
        file_path = UPLOAD_DIR / filename
        with open(file_path, "wb") as f:
            f.write(await file.read())
        file_url = f"/uploads/{filename}"
    
    chat_msg = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "sender": "admin",
        "sender_name": admin["username"],
        "message": message,
        "file_url": file_url,
        "read": False,
        "created_at": datetime.utcnow().isoformat()
    }
    await db.chat_messages.insert_one(chat_msg)
    
    await db.chat_messages.update_many(
        {"user_id": user_id, "sender": "user", "read": False},
        {"$set": {"read": True}}
    )
    
    await manager.send_personal_message({
        "type": "admin_chat_reply",
        "message": chat_msg
    }, user_id)
    
    return {"success": True, "message": chat_msg}

@app.get("/api/admin/chat-unread")
async def get_admin_unread_count(admin: dict = Depends(get_current_admin)):
    count = await db.chat_messages.count_documents({"sender": "user", "read": False})
    return {"unread_count": count}

# ADMIN PAYMENT VERIFICATION
@app.get("/api/admin/payments/pending")
async def get_pending_payments(admin: dict = Depends(get_current_admin)):
    payments = await db.payments.find({"status": "pending"}).sort("submitted_at", -1).to_list(length=None)
    return {"payments": serialize_docs(payments), "total": len(payments)}  # CRITICAL FIX

@app.get("/api/admin/payments/all")
async def get_all_payments(admin: dict = Depends(get_current_admin)):
    payments = await db.payments.find().sort("submitted_at", -1).to_list(length=None)
    return {"payments": serialize_docs(payments), "total": len(payments)}  # CRITICAL FIX

@app.post("/api/admin/payments/verify")
async def verify_payment(verification: PaymentVerification, admin: dict = Depends(get_current_admin)):
    payment = await db.payments.find_one({"id": verification.payment_id})
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    
    update_data = {
        "status": verification.status,
        "verified": verification.status == "approved",
        "verified_at": datetime.utcnow().isoformat(),
        "admin_notes": verification.notes,
        "verified_by": admin["id"]
    }
    
    await db.payments.update_one({"id": verification.payment_id}, {"$set": update_data})
    
    if verification.status == "approved":
        user = await db.users.find_one({"id": payment["user_id"]})
        if user:
            new_balances = user.get("balances", {}).copy()
            crypto = payment["crypto"]
            amount = payment["amount"]
            new_balances[crypto] = new_balances.get(crypto, 0) + amount
            
            await db.users.update_one({"id": payment["user_id"]}, {"$set": {"balances": new_balances}})
            
            await manager.send_personal_message({
                "type": "payment_approved",
                "payment": payment,
                "amount": amount,
                "crypto": crypto,
                "new_balance": new_balances[crypto],
                "message": f"Your payment of {amount} {crypto} has been approved and credited!"
            }, payment["user_id"])
    else:
        await manager.send_personal_message({
            "type": "payment_rejected",
            "payment": payment,
            "reason": verification.notes,
            "message": f"Payment rejected. Reason: {verification.notes}"
        }, payment["user_id"])
    
    return {"success": True, "message": f"Payment {verification.status}"}

@app.get("/api/admin/stats")
async def admin_stats(admin: dict = Depends(get_current_admin)):
    total_users = await db.users.count_documents({})
    kyc_pending = await db.kyc_submissions.count_documents({"status": "pending"})
    total_trades = await db.trades.count_documents({})
    active_mining = await db.mining_sessions.count_documents({"active": True})
    pending_payments = await db.payments.count_documents({"status": "pending"})
    pending_withdrawals = await db.withdrawals.count_documents({"status": "pending"})
    unread_chats = await db.chat_messages.count_documents({"sender": "user", "read": False})
    
    return {
        "total_users": total_users,
        "kyc_pending": kyc_pending,
        "total_trades": total_trades,
        "active_mining": active_mining,
        "pending_payments": pending_payments,
        "pending_withdrawals": pending_withdrawals,
        "unread_chats": unread_chats
    }

# WebSockets
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(websocket, user_id)
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_json({"type": "pong", "timestamp": datetime.utcnow().isoformat()})
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)

@app.websocket("/ws/admin")
async def admin_websocket_endpoint(websocket: WebSocket):
    await manager.connect_admin(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_json({"type": "pong", "timestamp": datetime.utcnow().isoformat()})
    except WebSocketDisconnect:
        manager.disconnect_admin(websocket)

# Health Check
@app.get("/api/health")
async def health_check():
    return {
        "status": "ok",
        "version": "3.1.0-serialization-fixed",
        "features": "mongodb_serialization_fixed",
        "supported_cryptos": SUPPORTED_CRYPTOS
    }

# Serve uploads
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
