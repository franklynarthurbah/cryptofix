#!/usr/bin/env python3
"""
Fix MongoDB ObjectId serialization in server.py
"""

import re

# Read the server.py file
with open('/home/claude/cryptovault-fixed-final/backend/server.py', 'r') as f:
    content = f.read()

# Patterns to fix - wrap MongoDB document returns with serialize functions
fixes = [
    # Fix: return {"users": users, ...}
    (r'return \{"users": users,', 'return {"users": serialize_docs(users),'),
    
    # Fix: return {"trades": trades, ...}
    (r'return \{"trades": trades,', 'return {"trades": serialize_docs(trades),'),
    
    # Fix: return {"mining_sessions": mining}
    (r'return \{"trades": serialize_docs\(trades\), "mining_sessions": mining\}',
     'return {"trades": serialize_docs(trades), "mining_sessions": serialize_docs(mining)}'),
    
    # Fix: return {"submissions": submissions, ...}
    (r'return \{"submissions": submissions,', 'return {"submissions": serialize_docs(submissions),'),
    
    # Fix: return {"messages": messages}
    (r'return \{"messages": messages\}', 'return {"messages": serialize_docs(messages)}'),
    
    # Fix: return {"chats": chats_list, ...}
    (r'return \{"chats": chats_list,', 'return {"chats": chats_list,'),  # chats_list is already processed
    
    # Fix: return {"payments": payments, ...}
    (r'return \{"payments": payments,', 'return {"payments": serialize_docs(payments),'),
    
    # Fix: return {"leaderboard": entries}
    (r'return \{"leaderboard": entries\}', 'return {"leaderboard": serialize_docs(entries)}'),
    
    # Fix: return {"transactions": transactions, ...}
    (r'return \{"transactions": transactions,', 'return {"transactions": transactions,'),  # Already processed in code
    
    # Fix individual document returns
    (r'submission\["user"\] = \{"email":', 'submission["user"] = {"email":'),  # Keep as is
]

for pattern, replacement in fixes:
    content = re.sub(pattern, replacement, content)

# Additional fix: Make sure user documents don't have _id and password_hash
# This is already handled, but let's be explicit

# Write back
with open('/home/claude/cryptovault-fixed-final/backend/server.py', 'w') as f:
    f.write(content)

print("✅ MongoDB serialization fixes applied!")
