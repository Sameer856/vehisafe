import urllib.request
import urllib.parse
import hashlib
import random
import time
import re
import xml.etree.ElementTree as ET

MODEM_IP = "192.168.100.1"

def get_md5(data):
    return hashlib.md5(data.encode('utf-8')).hexdigest()

def make_digest_auth_header(method, username, password, realm, nonce, qop, uri_path, nc_int=1):
    HA1 = get_md5(f"{username}:{realm}:{password}")
    HA2 = get_md5(f"{method}:{uri_path}")
    
    rand_part = random.randint(0, 100000)
    time_part = int(time.time() * 1000)
    salt = f"{rand_part}{time_part}"
    cnonce = get_md5(salt)[:16]
    
    nc = f"{nc_int:08x}"
    response_hash = get_md5(f"{HA1}:{nonce}:{nc}:{cnonce}:{qop}:{HA2}")
    
    auth_header = (
        f'Digest username="{username}", realm="{realm}", nonce="{nonce}", '
        f'uri="{uri_path}", response="{response_hash}", qop={qop}, nc={nc}, cnonce="{cnonce}"'
    )
    return auth_header, response_hash, cnonce

def get_auth_params(url):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as res:
            auth_header = res.getheader("WWW-Authenticate")
            if auth_header:
                realm_match = re.search(r'realm="([^"]+)"', auth_header)
                nonce_match = re.search(r'nonce="([^"]+)"', auth_header)
                qop_match = re.search(r'qop="([^"]+)"', auth_header)
                
                realm = realm_match.group(1) if realm_match else "Highwmg"
                nonce = nonce_match.group(1) if nonce_match else ""
                qop = qop_match.group(1) if qop_match else "auth"
                return realm, nonce, qop
    except Exception as e:
        print("[ERROR] Could not fetch authentication parameters from modem:", e)
    return None, None, None

def uni_encode(s):
    return ''.join(f"{ord(c):04x}" for c in s)

def get_sms_time():
    now = time.localtime()
    year = str(now.tm_year)[2:]
    month = str(now.tm_mon)
    day = str(now.tm_mday)
    hour = str(now.tm_hour)
    minute = str(now.tm_min)
    second = str(now.tm_sec)
    
    # Calculate timezone offset in hours
    is_dst = now.tm_isdst
    offset_seconds = - (time.altzone if is_dst else time.timezone)
    offset_hours = offset_seconds / 3600.0
    
    if offset_hours >= 0:
        timezone_str = f"%2B{offset_hours:g}"
    else:
        timezone_str = f"{offset_hours:g}"
        
    return f"{year},{month},{day},{hour},{minute},{second},{timezone_str}"

def send_sms(phone_number, message_text):
    print(f"Connecting to modem at {MODEM_IP}...")
    probe_url = f"http://{MODEM_IP}/login.cgi"
    realm, nonce, qop = get_auth_params(probe_url)
    if not nonce:
        print("[ERROR] Failed. Is your Mac connected to the Lapcare Modem Wi-Fi?")
        return False
    
    # 2. Perform Login Request
    print("Performing login request...")
    auth_header_val, digest_res, cnonce = make_digest_auth_header(
        "GET", "admin", "admin", realm, nonce, qop, "/cgi/protected.cgi", nc_int=1
    )
    login_url = (
        f"http://{MODEM_IP}/login.cgi?Action=Digest"
        f"&username=admin&realm={realm}&nonce={nonce}"
        f"&response={digest_res}&qop={qop}&cnonce={cnonce}&temp=asr"
    )
    
    try:
        req = urllib.request.Request(login_url)
        req.add_header("Authorization", auth_header_val)
        with urllib.request.urlopen(req, timeout=5) as res:
            res.read()
    except Exception as e:
        print("[ERROR] Login request failed:", e)
        return False
        
    # 3. Post SMS
    sms_time = get_sms_time()
    encoded_message = uni_encode(message_text)
    
    xml_data = (
        '<?xml version="1.0" encoding="US-ASCII"?>\n'
        '<RGW>\n'
        '  <message>\n'
        '    <flag>\n'
        '      <message_flag>SEND_SMS</message_flag>\n'
        '    </flag>\n'
        '    <send_save_message>\n'
        f'      <contacts>{phone_number}</contacts>\n'
        f'      <content>{encoded_message}</content>\n'
        '      <encode_type>UNICODE</encode_type>\n'
        f'      <sms_time>{sms_time}</sms_time>\n'
        '    </send_save_message>\n'
        '  </message>\n'
        '</RGW>'
    )
    
    post_url = f"http://{MODEM_IP}/xml_action.cgi?method=set&module=duster&file=message"
    auth_header_val, _, _ = make_digest_auth_header(
        "POST", "admin", "admin", realm, nonce, qop, "/cgi/xml_action.cgi", nc_int=2
    )
    
    print(f"Sending message to {phone_number}...")
    try:
        req = urllib.request.Request(post_url, data=xml_data.encode('utf-8'), method="POST")
        req.add_header("Authorization", auth_header_val)
        req.add_header("Content-Type", "application/xml")
        with urllib.request.urlopen(req, timeout=10) as res:
            response_body = res.read().decode('utf-8', errors='ignore')
            
            # Parse XML response
            root = ET.fromstring(response_body)
            status_elem = root.find(".//sms_cmd_status_result")
            status = status_elem.text if status_elem is not None else None
            
            if status == "3":
                print("=========================================")
                print("[SUCCESS] SMS sent successfully!")
                print("=========================================")
                return True
            else:
                print(f"[ERROR] Failed to send SMS. Status result code: {status}")
                return False
    except Exception as e:
        print("[ERROR] HTTP post request failed:", e)
        return False

if __name__ == "__main__":
    import sys
    
    # Default parameters
    target_number = "+919655613211"
    test_message = "VehiSafe alert system test from Mac computer!"
    
    # Allow command line overrides
    if len(sys.argv) > 1:
        target_number = sys.argv[1]
    if len(sys.argv) > 2:
        test_message = " ".join(sys.argv[2:])
        
    print(f"Target Number: {target_number}")
    print(f"Message: {test_message}")
    send_sms(target_number, test_message)
