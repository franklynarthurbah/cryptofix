#!/usr/bin/env python3
"""
Initialize CryptoVault Database
Creates admin user and sets up initial data
"""

import asyncio
import bcrypt
from motor.motor_asyncio import AsyncIOMotorClient
import uuid
from datetime import datetime

MONGO_URL = "mongodb://localhost:27017"
DB_NAME = "cryptovault"

async def initialize_database():
    print("🔧 Initializing CryptoVault Database...")
    
    client = AsyncIOMotorClient(MONGO_URL)
    db = client[DB_NAME]
    
    # Create admin user
    print("\n📝 Creating admin user...")
    admin_exists = await db.admins.find_one({"username": "TempWork"})
    
    if not admin_exists:
        password = "TempW_115500_e"
        password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
        
        admin = {
            "id": str(uuid.uuid4()),
            "username": "TempWork",
            "email": "admin@cryptovault.com",
            "password_hash": password_hash,
            "created_at": datetime.utcnow().isoformat()
        }
        
        await db.admins.insert_one(admin)
        print("✅ Admin user created")
        print(f"   Username: TempWork")
        print(f"   Password: TempW_115500_e")
        print(f"   Code: ?X!Z*")
    else:
        print("✅ Admin user already exists")
    
    # Create indexes
    print("\n📚 Creating database indexes...")
    
    try:
        await db.users.create_index("email", unique=True)
        await db.users.create_index("id", unique=True)
        print("✅ User indexes created")
    except Exception as e:
        print(f"⚠️  User indexes: {e}")
    
    try:
        await db.trades.create_index("user_id")
        await db.trades.create_index("created_at")
        print("✅ Trade indexes created")
    except Exception as e:
        print(f"⚠️  Trade indexes: {e}")
    
    try:
        await db.chat_messages.create_index([("user_id", 1), ("created_at", -1)])
        print("✅ Chat indexes created")
    except Exception as e:
        print(f"⚠️  Chat indexes: {e}")
    
    try:
        await db.kyc_submissions.create_index("user_id")
        print("✅ KYC indexes created")
    except Exception as e:
        print(f"⚠️  KYC indexes: {e}")
    
    try:
        await db.payment_submissions.create_index([("user_id", 1), ("status", 1)])
        print("✅ Payment indexes created")
    except Exception as e:
        print(f"⚠️  Payment indexes: {e}")
    
    # Get stats
    print("\n📊 Database Statistics:")
    users_count = await db.users.count_documents({})
    admins_count = await db.admins.count_documents({})
    trades_count = await db.trades.count_documents({})
    
    print(f"   Users: {users_count}")
    print(f"   Admins: {admins_count}")
    print(f"   Trades: {trades_count}")
    
    print("\n✅ Database initialization complete!")
    print("\n🎯 Admin Login Credentials:")
    print("   URL: http://YOUR_IP/admin")
    print("   Code: ?X!Z*")
    print("   Username: TempWork")
    print("   Password: TempW_115500_e")
    
    client.close()

if __name__ == "__main__":
    asyncio.run(initialize_database())
