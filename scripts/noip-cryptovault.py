#!/usr/bin/env python3
"""
No-IP Dynamic DNS Updater for CryptoVault
Updates cryptovault.hopto.org to point to 164.92.138.206
"""

import requests
import time
import logging
from datetime import datetime

# No-IP Configuration
NOIP_USERNAME = "your-noip-username"  # CHANGE THIS
NOIP_PASSWORD = "your-noip-password"  # CHANGE THIS
HOSTNAME = "cryptovault.hopto.org"
UPDATE_INTERVAL = 300  # 5 minutes
EXPECTED_IP = "164.92.138.206"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/noip-cryptovault.log'),
        logging.StreamHandler()
    ]
)

def get_current_ip():
    """Get current public IP address"""
    try:
        response = requests.get('https://api.ipify.org?format=json', timeout=10)
        return response.json()['ip']
    except Exception as e:
        logging.error(f"Failed to get IP: {e}")
        return None

def update_noip(ip_address):
    """Update No-IP hostname with current IP"""
    try:
        url = f"https://dynupdate.no-ip.com/nic/update?hostname={HOSTNAME}&myip={ip_address}"
        response = requests.get(
            url,
            auth=(NOIP_USERNAME, NOIP_PASSWORD),
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.text.strip()
            if result.startswith('good') or result.startswith('nochg'):
                logging.info(f"✓ Updated {HOSTNAME} -> {ip_address} ({result})")
                return True
            else:
                logging.warning(f"Unexpected response: {result}")
                return False
        else:
            logging.error(f"HTTP {response.status_code}: {response.text}")
            return False
            
    except Exception as e:
        logging.error(f"Update failed: {e}")
        return False

def check_dns_resolution():
    """Check if hostname resolves to correct IP"""
    try:
        import socket
        resolved_ip = socket.gethostbyname(HOSTNAME)
        if resolved_ip == EXPECTED_IP:
            logging.info(f"✓ DNS correct: {HOSTNAME} -> {resolved_ip}")
            return True
        else:
            logging.warning(f"DNS mismatch: {HOSTNAME} -> {resolved_ip} (expected {EXPECTED_IP})")
            return False
    except Exception as e:
        logging.error(f"DNS check failed: {e}")
        return False

def main():
    """Main update loop"""
    logging.info(f"🚀 Starting No-IP updater for {HOSTNAME}")
    logging.info(f"Target IP: {EXPECTED_IP}")
    last_ip = None
    
    # Initial update
    current_ip = get_current_ip()
    if current_ip:
        logging.info(f"Current public IP: {current_ip}")
        if current_ip == EXPECTED_IP:
            update_noip(current_ip)
            last_ip = current_ip
        else:
            logging.warning(f"IP mismatch! Current: {current_ip}, Expected: {EXPECTED_IP}")
    
    while True:
        try:
            current_ip = get_current_ip()
            
            if current_ip and current_ip != last_ip:
                logging.info(f"IP changed: {last_ip} -> {current_ip}")
                if update_noip(current_ip):
                    last_ip = current_ip
            
            # Periodic DNS check
            check_dns_resolution()
            
            time.sleep(UPDATE_INTERVAL)
            
        except KeyboardInterrupt:
            logging.info("Shutting down...")
            break
        except Exception as e:
            logging.error(f"Main loop error: {e}")
            time.sleep(60)

if __name__ == '__main__':
    main()
