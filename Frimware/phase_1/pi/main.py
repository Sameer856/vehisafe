import threading
import time
import os
import sys
import math
import json
import urllib.request
import urllib.parse
import http.client
import hashlib
import random
import re
import xml.etree.ElementTree as ET
from http.server import SimpleHTTPRequestHandler, HTTPServer
import cv2
from video_buffer import VideoBufferManager
from ai_engine import OptimizedAIEngine

# ========================================================
# SYSTEM CONFIGURATION
# ========================================================
DEVICE_ID = "VH001"
FIREBASE_DB_URL = "https://vehisafe-alert-default-rtdb.firebaseio.com"
FIREBASE_STORAGE_BUCKET = "vehisafe-alert.firebasestorage.app"

GPS_PORT = "/dev/serial0"  # Set to your serial port (e.g. /dev/serial0, /dev/ttyS0, /dev/ttyUSB0)
EVIDENCE_DIR = "/home/pi/vehisafe/evidence"
if not os.path.exists("/home/pi") or not os.access("/home/pi", os.W_OK):
    EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "evidence")

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

# Create directories
os.makedirs(EVIDENCE_DIR, exist_ok=True)

# Initialize Camera and AI Engine
buffer_manager = VideoBufferManager(video_source=0, duration_sec=10)
ai_engine = OptimizedAIEngine()

# Shared Telemetry State
telemetry_lock = threading.Lock()
i2c_lock = threading.Lock()
current_lat = 0.0
current_lng = 0.0
current_speed = 0.0
current_sats = 0
current_gps_status = "No Signal"
last_gps_msg_time = 0.0

# Sensor States
accel_x, accel_y, accel_z = 0.0, 0.0, 1.0
mag_heading = 0
baro_pressure, baro_temp = 1013.2, 25.0
crash_triggered_flag = False
last_crash_trigger_time = 0.0

# GPIO Configuration
GPIO_ENABLED = False
try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(25, GPIO.IN, pull_up_down=GPIO.PUD_UP) # Config Button
    GPIO_ENABLED = True
    print("[INFO] RPi.GPIO initialized on GPIO 25.")
except Exception as e:
    print(f"[WARNING] GPIO not initialized: {e}. Physical buttons disabled.")

# ========================================================
# LOCAL CONFIGURATION HELPERS
# ========================================================
def load_local_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "contact1": "",
        "contact2": "",
        "contact3": "",
        "vehicle": "",
        "custom_msg": "Emergency Alert: Vehicle experienced a crash.",
        "configured": False
    }

def save_local_config(config_data):
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config_data, f)
        return True
    except Exception as e:
        print(f"[ERROR] Failed to save config: {e}")
        return False

# Load setup configurations
system_config = load_local_config()

# ========================================================
# I2C SENSOR READERS
# ========================================================
class ICM20948Reader:
    def __init__(self, bus_id=1, address=0x68):
        self.bus_id = bus_id
        self.address = address
        self.active = False
        self.imu = None
        try:
            from icm20948 import ICM20948
            try:
                # Try default address
                self.imu = ICM20948(i2c_addr=address)
                # Test read to verify physical connection
                _ = self.imu.read_accelerometer_gyro_data()
                self.active = True
                print(f"[INFO] I2C ICM-20948 initialized successfully on address {hex(address)}.")
            except Exception as e_addr:
                fallback_addr = 0x69 if address == 0x68 else 0x68
                print(f"[INFO] ICM-20948 not found on {hex(address)}: {e_addr}. Trying fallback address {hex(fallback_addr)}...")
                self.imu = ICM20948(i2c_addr=fallback_addr)
                _ = self.imu.read_accelerometer_gyro_data()
                self.address = fallback_addr
                self.active = True
                print(f"[INFO] I2C ICM-20948 initialized successfully on fallback address {hex(fallback_addr)}.")
        except Exception as e:
            print(f"[WARNING] ICM-20948 sensor initialization failed or not detected: {e}. Emulating sensor data.")

    def read_accelerometer(self):
        if not self.active or self.imu is None:
            # Emulate stable values (flat on table = 1G on Z)
            import random
            return (random.random() - 0.5) * 0.05, (random.random() - 0.5) * 0.05, 1.0 + (random.random() - 0.5) * 0.05
        with i2c_lock:
            try:
                # Pimoroni returns ax, ay, az, gx, gy, gz. Accel values are in G.
                ax, ay, az, _, _, _ = self.imu.read_accelerometer_gyro_data()
                return ax, ay, az
            except Exception as e:
                print(f"[ERROR] ICM-20948 accelerometer read error: {e}")
                return 0.0, 0.0, 1.0

    def read_heading(self):
        if not self.active or self.imu is None:
            import random
            return random.randint(0, 359)
        with i2c_lock:
            try:
                # Pimoroni returns mx, my, mz in microteslas (uT)
                mx, my, mz = self.imu.read_magnetometer_data()
                heading = math.atan2(my, mx) * 180 / math.pi
                if heading < 0:
                    heading += 360
                return int(heading)
            except Exception as e:
                print(f"[ERROR] ICM-20948 magnetometer/heading read error: {e}")
                return 0

class BMP280Reader:
    def __init__(self, bus_id=1, address=0x76):
        self.bus_id = bus_id
        self.address = address
        self.bus = None
        self.active = False
        try:
            import smbus2 as smbus
            self.bus = smbus.SMBus(bus_id)
            chip_id = self.bus.read_byte_data(self.address, 0xD0)
            if chip_id in [0x58, 0x56, 0x57, 0x60]:
                self.active = True
                # Wake up BMP280: write 0x27 (oversampling x1 for temp/press, Normal Mode) to ctrl_meas (0xF4)
                self.bus.write_byte_data(self.address, 0xF4, 0x27)
                # Read 24 bytes of calibration coefficients starting from 0x88
                calib = self.bus.read_i2c_block_data(self.address, 0x88, 24)
                import struct
                self.dig_T1, self.dig_T2, self.dig_T3, \
                self.dig_P1, self.dig_P2, self.dig_P3, self.dig_P4, self.dig_P5, \
                self.dig_P6, self.dig_P7, self.dig_P8, self.dig_P9 = struct.unpack("<HhhHhhhhhhhh", bytearray(calib))
                print(f"[INFO] I2C BMP280/288 initialized. Chip ID: {hex(chip_id)} (Normal Mode set + Calibrated).")
        except Exception:
            try:
                import smbus
                self.address = 0x77
                self.bus = smbus.SMBus(bus_id)
                chip_id = self.bus.read_byte_data(self.address, 0xD0)
                self.active = True
                # Wake up BMP280: write 0x27 to ctrl_meas (0xF4)
                self.bus.write_byte_data(self.address, 0xF4, 0x27)
                # Read 24 bytes of calibration coefficients
                calib = self.bus.read_i2c_block_data(self.address, 0x88, 24)
                import struct
                self.dig_T1, self.dig_T2, self.dig_T3, \
                self.dig_P1, self.dig_P2, self.dig_P3, self.dig_P4, self.dig_P5, \
                self.dig_P6, self.dig_P7, self.dig_P8, self.dig_P9 = struct.unpack("<HhhHhhhhhhhh", bytearray(calib))
                print(f"[INFO] I2C BMP280/288 initialized on 0x77. Chip ID: {hex(chip_id)} (Normal Mode set + Calibrated).")
            except Exception as e:
                print(f"[WARNING] BMP280/288 Barometer not detected: {e}. Emulating barometer.")

    def read_pressure_temp(self):
        if not self.active or self.bus is None:
            import random
            return round(1013.25 + (random.random() - 0.5) * 4.0, 2), round(25.0 + (random.random() - 0.5) * 2.0, 2)
            
        with i2c_lock:
            try:
                # Read 6 bytes of data starting from 0xF7 (pressure and temperature registers)
                data = self.bus.read_i2c_block_data(self.address, 0xF7, 6)
                
                # Combine bytes to form 20-bit raw values
                adc_P = (data[0] << 12) + (data[1] << 4) + (data[2] >> 4)
                adc_T = (data[3] << 12) + (data[4] << 4) + (data[5] >> 4)
                
                # 1. Calculate compensated temperature
                var1 = (adc_T / 16384.0 - self.dig_T1 / 1024.0) * self.dig_T2
                var2 = ((adc_T / 131072.0 - self.dig_T1 / 8192.0) * 
                        (adc_T / 131072.0 - self.dig_T1 / 8192.0)) * self.dig_T3
                t_fine = var1 + var2
                temp = t_fine / 5120.0
                
                # 2. Calculate compensated pressure
                var3 = (t_fine / 2.0) - 64000.0
                var4 = var3 * var3 * self.dig_P6 / 32768.0
                var4 = var4 + var3 * self.dig_P5 * 2.0
                var4 = (var4 / 4.0) + (self.dig_P4 * 65536.0)
                var3 = (self.dig_P3 * var3 * var3 / 524288.0 + self.dig_P2 * var3) / 524288.0
                var3 = (1.0 + var3 / 32768.0) * self.dig_P1
                
                if var3 == 0.0:
                    press = 1013.25
                else:
                    p = 1048576.0 - adc_P
                    p = ((p - (var4 / 4096.0)) * 6250.0) / var3
                    var3 = self.dig_P9 * p * p / 2147483648.0
                    var4 = p * self.dig_P8 / 32768.0
                    press = (p + (var3 + var4 + self.dig_P7) / 16.0) / 100.0
                
                # Fallbacks in case of bad conversion values
                if not (10.0 <= temp <= 80.0): temp = 25.0
                if not (900.0 <= press <= 1100.0): press = 1013.25
                
                return round(press, 1), round(temp, 1)
            except Exception as e:
                print(f"[ERROR] BMP280 read/compensation error: {e}")
                return 1013.2, 25.0

# Instantiate readers
icm_reader = ICM20948Reader()
mpu_reader = icm_reader
gy_reader = icm_reader
bmp_reader = BMP280Reader()

# ========================================================
# GPS NMEA SERIAL DECODER
# ========================================================
class GPSReaderThread(threading.Thread):
    def __init__(self, port, baud=9600):
        super().__init__()
        self.daemon = True
        self.port = port
        self.baud = baud
        self.ser = None
        self.active = False
        try:
            import serial
            self.ser = serial.Serial(port, baud, timeout=1)
            self.active = True
            print(f"[INFO] GPS serial receiver opened on {port}")
        except Exception as e:
            print(f"[WARNING] GPS serial initialization failed: {e}. Emulating GPS coordinates.")

    def run(self):
        global current_lat, current_lng, current_speed, current_sats, current_gps_status, last_gps_msg_time
        buffer = bytearray()
        last_gps_msg_time = time.time()
        
        while True:
            if not self.active or self.ser is None:
                with telemetry_lock:
                    current_lat = 0.0
                    current_lng = 0.0
                    current_speed = 0.0
                    current_sats = 0
                    current_gps_status = "No Signal"
                time.sleep(2)
                continue
                
            try:
                # Check for heartbeat decay (if no serial data for > 5 seconds, reset status)
                if time.time() - last_gps_msg_time > 5.0:
                    with telemetry_lock:
                        if current_gps_status != "No Signal":
                            current_gps_status = "No Signal"
                            current_sats = 0
                            print("[GPS WARNING] GPS Signal Lost (No serial data received).")
                            
                # Read non-blocking from serial queue
                if self.ser.in_waiting > 0:
                    char = self.ser.read(1)
                    if char:
                        last_gps_msg_time = time.time()
                        buffer.extend(char)
                        
                        # Prevent memory build-up from bad/garbage lines (NMEA is max 82 chars)
                        if len(buffer) > 120:
                            buffer.clear()
                        elif char == b'\n':
                            line = buffer.decode('ascii', errors='ignore').strip()
                            buffer.clear()
                            
                            if line:
                                # Find first '$' to handle any leading noise/corruption bytes
                                dollar_idx = line.find('$')
                                if dollar_idx != -1:
                                    line = line[dollar_idx:]
                                    
                                if line.startswith('$GPRMC') or line.startswith('$GNRMC'):
                                    parts = line.split(',')
                                    if len(parts) > 9:
                                        status = parts[2]
                                        if status == 'A':
                                            lat_val = float(parts[3][:2]) + float(parts[3][2:]) / 60.0
                                            if parts[4] == 'S': lat_val = -lat_val
                                            
                                            lng_val = float(parts[5][:3]) + float(parts[5][3:]) / 60.0
                                            if parts[6] == 'W': lng_val = -lng_val
                                            
                                            speed_knots = float(parts[7]) if parts[7] else 0.0
                                            
                                            with telemetry_lock:
                                                old_status = current_gps_status
                                                current_lat = round(lat_val, 6)
                                                current_lng = round(lng_val, 6)
                                                current_speed = round(speed_knots * 1.852, 1)
                                                current_gps_status = "GPS Locked"
                                            if old_status != "GPS Locked":
                                                print(f"[GPS INFO] GPS Lock Acquired! Lat: {current_lat}, Lng: {current_lng}")
                                        else:
                                            with telemetry_lock:
                                                old_status = current_gps_status
                                                current_gps_status = "GPS Connected (No Fix)"
                                            if old_status != "GPS Connected (No Fix)":
                                                print("[GPS INFO] GPS Connected. Searching for satellite lock...")
                                elif line.startswith('$GPGGA') or line.startswith('$GNGGA'):
                                    parts = line.split(',')
                                    if len(parts) > 7:
                                        sats_count = int(parts[7]) if parts[7] else 0
                                        with telemetry_lock:
                                            old_status = current_gps_status
                                            current_sats = sats_count
                                            # If we are receiving GGA sentences, the GPS is connected
                                            if current_gps_status == "No Signal":
                                                current_gps_status = "GPS Connected (No Fix)"
                                        if old_status == "No Signal":
                                            print("[GPS INFO] GPS Connected. Searching for satellite lock...")
                else:
                    time.sleep(0.01)  # Minimal sleep to prevent CPU pegging
            except Exception as e:
                print(f"[GPS PARSER ERROR] {e}")
                buffer.clear()
                time.sleep(0.1)

# Start GPS Thread
gps_thread = GPSReaderThread(GPS_PORT)
gps_thread.start()

# ========================================================
# FIREBASE REST API INTEGRATIONS
# ========================================================
def upload_file_to_firebase_storage(local_path, file_mime_type):
    filename = os.path.basename(local_path)
    # URL Format for anonymous public upload
    url = f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o?uploadType=media&name={filename}"
    try:
        with open(local_path, 'rb') as f:
            file_data = f.read()
    except Exception as e:
        print(f"[FIREBASE STORAGE ERROR] Failed to read local file {filename}: {e}")
        return f"http://192.168.100.198:8080/{filename}"

    max_retries = 3
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, data=file_data, method="POST")
            req.add_header("Content-Type", file_mime_type)
            with urllib.request.urlopen(req, timeout=45) as res:
                res.read()
                # Construct direct readable public URL
                public_url = f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o/{filename}?alt=media"
                print(f"[FIREBASE STORAGE] Successfully uploaded: {filename}")
                return public_url
        except Exception as e:
            print(f"[FIREBASE STORAGE ERROR] Attempt {attempt+1}/{max_retries} failed for {filename}: {e}")
            if attempt < max_retries - 1:
                time.sleep(3)  # Wait for connection/congestion to clear

    # Fallback if all retries fail
    print(f"[FIREBASE STORAGE ERROR] All upload attempts failed for {filename}. Falling back to local URL.")
    return f"http://192.168.100.198:8080/{filename}"

_rtdb_client_local = threading.local()

def update_firebase_rtdb(path, data_dict, max_retries=3, timeout=20):
    url_parts = urllib.parse.urlparse(FIREBASE_DB_URL)
    host = url_parts.netloc
    url_path = f"/{path.lstrip('/')}.json"
    
    try:
        payload = json.dumps(data_dict).encode('utf-8')
    except Exception as e:
        print(f"[FIREBASE RTDB ERROR] Failed to serialize payload for {path}: {e}")
        return False

    for attempt in range(max_retries):
        try:
            # Retrieve or initialize a persistent HTTPSConnection for this thread
            conn = getattr(_rtdb_client_local, 'conn', None)
            if conn is None:
                conn = http.client.HTTPSConnection(host, timeout=timeout)
                _rtdb_client_local.conn = conn
            
            # Send PUT request using HTTP keep-alive
            conn.request("PUT", url_path, body=payload, headers={
                "Content-Type": "application/json",
                "Connection": "keep-alive"
            })
            res = conn.getresponse()
            res.read()  # Read response body to release/reuse connection
            
            if res.status in (200, 201, 204):
                print(f"[FIREBASE RTDB] Successfully updated path: {path}")
                return True
            else:
                print(f"[FIREBASE RTDB ERROR] Status {res.status} writing to {path}")
        except Exception as e:
            print(f"[FIREBASE RTDB ERROR] Attempt {attempt+1}/{max_retries} failed to write to {path}: {e}")
            # Reset connection on failure so the next attempt opens a new socket
            if getattr(_rtdb_client_local, 'conn', None) is not None:
                try:
                    _rtdb_client_local.conn.close()
                except Exception:
                    pass
                _rtdb_client_local.conn = None
            if attempt < max_retries - 1:
                time.sleep(2)

    print(f"[FIREBASE RTDB ERROR] All write attempts failed for path: {path}")
    return False

def read_firebase_rtdb(path, timeout=5):
    url_parts = urllib.parse.urlparse(FIREBASE_DB_URL)
    host = url_parts.netloc
    url_path = f"/{path.lstrip('/')}.json"
    
    try:
        conn = getattr(_rtdb_client_local, 'read_conn', None)
        if conn is None:
            conn = http.client.HTTPSConnection(host, timeout=timeout)
            _rtdb_client_local.read_conn = conn
            
        conn.request("GET", url_path, headers={
            "Connection": "keep-alive"
        })
        res = conn.getresponse()
        data = res.read()
        
        if res.status == 200:
            return json.loads(data.decode('utf-8'))
        else:
            print(f"[FIREBASE RTDB READ ERROR] Status {res.status} reading from {path}")
    except Exception as e:
        # Reset read connection on failure
        if getattr(_rtdb_client_local, 'read_conn', None) is not None:
            try:
                _rtdb_client_local.read_conn.close()
            except Exception:
                pass
            _rtdb_client_local.read_conn = None
    return None

def check_remote_commands_and_config():
    # 1. Check for remote config updates
    try:
        remote_config = read_firebase_rtdb(f"device_config/{DEVICE_ID}", timeout=5)
        if remote_config and isinstance(remote_config, dict):
            local_config = load_local_config()
            keys_to_compare = ["contact1", "contact2", "contact3", "vehicle", "custom_msg"]
            changed = False
            for k in keys_to_compare:
                if remote_config.get(k) != local_config.get(k):
                    changed = True
                    break
            if remote_config.get("configured") != local_config.get("configured"):
                changed = True
                
            if changed:
                print(f"[CLOUD CONFIG] Remote config changes detected. Updating local config.")
                new_config = {
                    "contact1": remote_config.get("contact1", ""),
                    "contact2": remote_config.get("contact2", ""),
                    "contact3": remote_config.get("contact3", ""),
                    "vehicle": remote_config.get("vehicle", ""),
                    "custom_msg": remote_config.get("custom_msg", "Emergency Alert: Vehicle experienced a crash."),
                    "configured": remote_config.get("configured", True)
                }
                save_local_config(new_config)
                global system_config
                system_config = new_config
    except Exception as ex:
        print(f"[CLOUD CONFIG ERROR] Failed to sync remote config: {ex}")

    # 2. Check for simulation commands
    try:
        trigger = read_firebase_rtdb(f"simulate_trigger/{DEVICE_ID}", timeout=5)
        if trigger and isinstance(trigger, dict):
            severity = trigger.get("severity", "HIGH")
            print(f"[CLOUD TRIGGER] Simulation trigger detected: {severity}. Clearing from cloud and executing...")
            # Clear simulation trigger on Firebase immediately by writing null
            update_firebase_rtdb(f"simulate_trigger/{DEVICE_ID}", None, max_retries=2, timeout=5)
            # Execute crash alert in a new thread
            threading.Thread(target=execute_crash_alert, args=(severity,)).start()
    except Exception as ex:
        print(f"[CLOUD TRIGGER ERROR] Failed to process remote trigger: {ex}")

# ========================================================
# MODEM SMS UTILITIES
# ========================================================
MODEM_IP = "192.168.100.1"

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
    
    is_dst = now.tm_isdst
    offset_seconds = - (time.altzone if is_dst else time.timezone)
    offset_hours = offset_seconds / 3600.0
    
    if offset_hours >= 0:
        timezone_str = f"%2B{offset_hours:g}"
    else:
        timezone_str = f"{offset_hours:g}"
        
    return f"{year},{month},{day},{hour},{minute},{second},{timezone_str}"

def get_modem_auth_params(url):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as res:
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
        print(f"[MODEM SMS ERROR] Failed to fetch auth challenge: {e}")
    return None, None, None

def make_digest_auth_header(method, username, password, realm, nonce, qop, uri_path, nc_int=1):
    HA1 = hashlib.md5(f"{username}:{realm}:{password}".encode('utf-8')).hexdigest()
    HA2 = hashlib.md5(f"{method}:{uri_path}".encode('utf-8')).hexdigest()
    
    rand_part = random.randint(0, 100000)
    time_part = int(time.time() * 1000)
    salt = f"{rand_part}{time_part}"
    cnonce = hashlib.md5(salt.encode('utf-8')).hexdigest()[:16]
    
    nc = f"{nc_int:08x}"
    response_hash = hashlib.md5(f"{HA1}:{nonce}:{nc}:{cnonce}:{qop}:{HA2}".encode('utf-8')).hexdigest()
    
    auth_header = (
        f'Digest username="{username}", realm="{realm}", nonce="{nonce}", '
        f'uri="{uri_path}", response="{response_hash}", qop={qop}, nc={nc}, cnonce="{cnonce}"'
    )
    return auth_header, response_hash, cnonce

def send_real_sms_via_modem(phone_number, message_text):
    print(f"[MODEM SMS] Dispatching SMS to {phone_number}...")
    probe_url = f"http://{MODEM_IP}/login.cgi"
    realm, nonce, qop = get_modem_auth_params(probe_url)
    if not nonce:
        print("[MODEM SMS ERROR] Authentication nonce not found. Modem might be offline.")
        return False
        
    # 2. Perform Login Session handshake GET request
    print("[MODEM SMS] Performing session login...")
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
            res.read()  # establish session
    except Exception as e:
        print(f"[MODEM SMS ERROR] Login session handshake failed: {e}")
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
    
    try:
        req = urllib.request.Request(post_url, data=xml_data.encode('utf-8'), method="POST")
        req.add_header("Authorization", auth_header_val)
        req.add_header("Content-Type", "application/xml")
        with urllib.request.urlopen(req, timeout=5) as res:
            response_body = res.read().decode('utf-8', errors='ignore')
            
            root = ET.fromstring(response_body)
            status_elem = root.find(".//sms_cmd_status_result")
            status = status_elem.text if status_elem is not None else None
            
            if status == "3":
                print(f"[MODEM SMS] Dispatch successful to {phone_number}!")
                return True
            else:
                print(f"[MODEM SMS ERROR] Send failed to {phone_number}. Status result code: {status}")
                print(f"[MODEM SMS DEBUG] Raw response from modem: {response_body}")
                return False
    except Exception as e:
        print(f"[MODEM SMS ERROR] Failed to send request: {e}")
        return False

# ========================================================
# CRASH TRIGGER HANDLER (AI EVAL & CLOUD POST)
# ========================================================
def background_cloud_upload_thread(timestamp, severity_level, base_score, ai_bonus, final_score, lat, lng, speed, sats, video_file, keyframe_paths):
    video_cloud_url = ""
    keyframe_urls = []
    
    # 4. Upload video to Firebase Storage
    if video_file:
        try:
            print("[CLOUD SYNC] Starting Firebase Cloud Video Upload in background...")
            video_cloud_url = upload_file_to_firebase_storage(video_file, "video/mp4")
        except Exception as e:
            print(f"[CRASH ALERT WARNING] Firebase video upload failed: {e}")
            
    # 5. Upload keyframes
    if keyframe_paths:
        try:
            print("[CLOUD SYNC] Starting Firebase Cloud Keyframes Upload in background...")
            for kf in keyframe_paths:
                kf_url = upload_file_to_firebase_storage(kf, "image/jpeg")
                keyframe_urls.append(kf_url)
        except Exception as e:
            print(f"[CRASH ALERT WARNING] Firebase keyframes upload failed: {e}")
            
    # 6. Post Alert Record to Firebase Realtime Database
    alert_payload = {
        "timestamp": timestamp,
        "deviceId": DEVICE_ID,
        "latitude": lat,
        "longitude": lng,
        "speed_kmh": speed,
        "satellites": sats,
        "severityLevel": severity_level,
        "baseScore": base_score,
        "aiBonus": ai_bonus,
        "finalScore": final_score,
        "videoUrl": video_cloud_url,
        "keyframes": keyframe_urls,
        "sensors": {
            "accel_x": round(accel_x, 2),
            "accel_y": round(accel_y, 2),
            "accel_z": round(accel_z, 2),
            "compass_heading": mag_heading,
            "baro_pressure_hpa": baro_pressure,
            "baro_temp_c": baro_temp
        }
    }
    
    try:
        update_firebase_rtdb(f"alerts/{DEVICE_ID}", alert_payload)
    except Exception as e:
        print(f"[CRASH ALERT WARNING] Firebase Realtime Database update failed: {e}")

def execute_crash_alert(severity_level):
    global last_crash_trigger_time
    now = time.time()
    if now - last_crash_trigger_time < 60.0:
        return # Debounce repeat impacts (prevents loop triggers from phone countdown completion)
    last_crash_trigger_time = now
    
    print(f"\n[CRITICAL TRIGGER] Crash sequence armed. Severity Level: {severity_level}!")
    
    # Capture telemetry snapshot
    with telemetry_lock:
        lat = current_lat
        lng = current_lng
        speed = current_speed
        sats = current_sats
        gps_status = current_gps_status

    # Get local config
    config = load_local_config()
    
    # Update Firebase device status immediately to "Alert" state so the cloud app gets notified instantly
    try:
        quick_status_payload = {
            "deviceId": DEVICE_ID,
            "isConnected": True,
            "lastSeen": int(now),
            "currentMode": "Alert",
            "crash_triggered": True,
            "gpsStatus": gps_status,
            "latitude": lat,
            "longitude": lng,
            "satellites": sats,
            "speed": speed,
            "sensors": {
                "accel_x": round(accel_x, 2),
                "accel_y": round(accel_y, 2),
                "accel_z": round(accel_z, 2),
                "heading": mag_heading,
                "pressure_hpa": baro_pressure,
                "temperature_c": baro_temp
            }
        }
        threading.Thread(
            target=update_firebase_rtdb,
            args=(f"device_status/{DEVICE_ID}", quick_status_payload),
            kwargs={"max_retries": 1, "timeout": 5}
        ).start()
    except Exception as e:
        print(f"[CRASH ALERT WARNING] Immediate status alert post failed: {e}")
    
    video_file = None
    keyframe_paths = []
    ai_bonus = 0.0
    
    # 1. Compile 15s video from RAM buffer
    try:
        video_file = buffer_manager.freeze_buffer(save_destination_dir=EVIDENCE_DIR)
    except Exception as e:
        print(f"[CRASH ALERT WARNING] Video freeze failed: {e}")
        
    # 2. Extract keyframes for AI processing
    if video_file:
        try:
            keyframe_paths = buffer_manager.extract_keyframes(video_file)
        except Exception as e:
            print(f"[CRASH ALERT WARNING] Keyframe extraction failed: {e}")
            
    # 3. Calculate AI severity points
    if keyframe_paths:
        try:
            start_ai = time.time()
            ai_bonus = ai_engine.calculate_severity_bonuses(keyframe_paths)
            ai_duration = time.time() - start_ai
        except Exception as e:
            print(f"[CRASH ALERT WARNING] AI processing failed: {e}")
            
    base_score = 3.5 if severity_level == 'LOW' else (6.2 if severity_level == 'MEDIUM' else 8.5)
    final_score = base_score + ai_bonus
    
    # Deterministic public video URL template (so SMS has it immediately)
    predicted_video_url = ""
    if video_file:
        filename = os.path.basename(video_file)
        predicted_video_url = f"https://firebasestorage.googleapis.com/v0/b/{FIREBASE_STORAGE_BUCKET}/o/{filename}?alt=media"
    
    # Start background cloud syncing and DB posting to keep execution non-blocking
    sync_thread = threading.Thread(
        target=background_cloud_upload_thread,
        args=(int(now), severity_level, base_score, ai_bonus, final_score, lat, lng, speed, sats, video_file, keyframe_paths)
    )
    sync_thread.daemon = True
    sync_thread.start()

    # 7. Real SMS alerts via USB Modem (with fallback print simulation)
    print("\n--- [DISPATCHING REAL SMS ALERTS] ---")
    raw_contacts = [config.get("contact1", ""), config.get("contact2", ""), config.get("contact3", "")]
    contacts = [c.strip() for c in raw_contacts if c and c.strip()]
    if not contacts:
        print("[MODEM SMS WARNING] No contacts configured in config.json. Falling back to test number +919655613211.")
        contacts = ["+919655613211"]
    else:
        print(f"[MODEM SMS INFO] Active emergency alert contacts: {contacts}")
        
    # Read custom message template from config
    custom_msg = config.get("custom_msg", "Emergency Alert: Vehicle experienced a crash.")
    if not custom_msg:
        custom_msg = "Emergency Alert: Vehicle experienced a crash."
        
    sms_message = (
        f"VehiSafe ALERT: {custom_msg}\n"
        f"Severity: {severity_level} (Score: {final_score:.1f})\n"
        f"Speed: {speed} km/h\n"
        f"Map: https://maps.google.com/?q={lat},{lng}\n"
        f"Video Link: {predicted_video_url if predicted_video_url else 'Video Offline'}"
    )
    for c in contacts:
        if c:
            try:
                success = send_real_sms_via_modem(c, sms_message)
                if not success:
                    print(f"[SMS SIMULATION FALLBACK] Dispatching payload to {c}:\n{sms_message}\n")
            except Exception as e:
                print(f"[MODEM SMS ERROR] Dispatch to {c} failed with exception: {e}")
                print(f"[SMS SIMULATION FALLBACK] Dispatching payload to {c}:\n{sms_message}\n")
    print("---------------------------------------\n")

# ========================================================
# CLOUD TELEMETRY WRITER
# ========================================================
def telemetry_sync_loop():
    while True:
        with telemetry_lock:
            lat = current_lat
            lng = current_lng
            speed = current_speed
            sats = current_sats
            gps_status = current_gps_status
            
        is_alert_active = (time.time() - last_crash_trigger_time < 15.0)
        status_payload = {
            "deviceId": DEVICE_ID,
            "isConnected": True,
            "lastSeen": int(time.time()),
            "currentMode": "Alert" if is_alert_active else "Armed & Monitoring",
            "crash_triggered": is_alert_active,
            "gpsStatus": gps_status,
            "latitude": lat,
            "longitude": lng,
            "satellites": sats,
            "speed": speed,
            "sensors": {
                "accel_x": round(accel_x, 2),
                "accel_y": round(accel_y, 2),
                "accel_z": round(accel_z, 2),
                "heading": mag_heading,
                "pressure_hpa": baro_pressure,
                "temperature_c": baro_temp
            }
        }
        
        # Write to status path in Firebase Realtime Database with 1 retry and 5s timeout to avoid blocking
        update_firebase_rtdb(f"device_status/{DEVICE_ID}", status_payload, max_retries=1, timeout=5)
        
        # Query remote configuration and commands (simulation triggers)
        try:
            check_remote_commands_and_config()
        except Exception as e:
            print(f"[ERROR] check_remote_commands_and_config failed: {e}")
            
        time.sleep(5)

# Start background sync thread
sync_thread = threading.Thread(target=telemetry_sync_loop)
sync_thread.daemon = True
sync_thread.start()

# ========================================================
# PHYSICAL HARDWARE MONITOR THREAD (ACCELEROMETER TRIGGERS)
# ========================================================
def hardware_monitor_loop():
    global accel_x, accel_y, accel_z, mag_heading, baro_pressure, baro_temp
    print("[INFO] Hardware sensor monitor loop started.")
    
    # Start a slow thread to read Magnetometer and Barometer (runs at 10 Hz)
    def slow_sensor_loop():
        global mag_heading, baro_pressure, baro_temp
        last_printed_press = 1013.25
        while True:
            try:
                mag_heading = gy_reader.read_heading()
                p, t = bmp_reader.read_pressure_temp()
                baro_pressure, baro_temp = p, t
                
                # If pressure shifts significantly (e.g. > 0.4 hPa), print immediately for fast feedback!
                if abs(p - last_printed_press) > 0.4:
                    print(f"[BARO MONITOR] Dynamic pressure change: {p:.1f} hPa | Temp: {t:.1f}°C")
                    last_printed_press = p
            except Exception as e:
                print(f"[ERROR] Slow sensor read error: {e}")
            time.sleep(0.1)
            
    slow_thread = threading.Thread(target=slow_sensor_loop)
    slow_thread.daemon = True
    slow_thread.start()

    # The main hardware monitor loop now acts as a high-frequency (100 Hz) accelerometer scanner
    while True:
        try:
            # 1. Read Accelerometer (very fast read)
            ax, ay, az = mpu_reader.read_accelerometer()
            accel_x, accel_y, accel_z = ax, ay, az
            
            # Calculate total G-force
            g_force = math.sqrt(ax**2 + ay**2 + az**2)
            
            # 2. Monitor high G-forces (useful for user feedback during testing/shaking)
            if g_force > 1.8:
                print(f"[ACCEL MONITOR] High G-Force detected: {g_force:.2f}G")
            
            # 3. Automatic crash threshold trigger (> 2.5G magnitude)
            if g_force > 2.5:
                print(f"[ACCEL TRIGGER] G-force spike detected: {g_force:.2f}G!")
                threading.Thread(target=execute_crash_alert, args=('HIGH',)).start()
        except Exception as e:
            print(f"[ERROR] Accelerometer read error: {e}")
            
        # 4. Check physical BCM GPIO buttons if enabled
        if GPIO_ENABLED:
            if GPIO.input(25) == GPIO.LOW: # Physical Config Mode Hold
                print("[BUTTON] Configuration Toggle Pressed, holding...")
                press_start = time.time()
                triggered = False
                while GPIO.input(25) == GPIO.LOW:
                    time.sleep(0.1)
                    if time.time() - press_start >= 10.0:
                        triggered = True
                        break
                
                if triggered:
                    print("[BUTTON] Config button held for 10s! Activating configuration mode...")
                    config = load_local_config()
                    config["configured"] = False
                    save_local_config(config)
                
        # Sleep for 10ms (100 Hz sampling rate) to capture fast shake/crash transients
        time.sleep(0.01)

# Start hardware monitoring thread
hw_thread = threading.Thread(target=hardware_monitor_loop)
hw_thread.daemon = True
hw_thread.start()

# ========================================================
# HTTP WEB SERVER
# ========================================================
class PiServerHandler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Serve static evidence files directly
        parsed_path = urllib.parse.urlparse(path)
        return os.path.join(EVIDENCE_DIR, parsed_path.path.lstrip('/'))

    def end_headers(self):
        # Inject CORS headers for Flutter compatibility
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def do_POST(self):
        parsed_path = urllib.parse.urlparse(self.path)
        
        # Flutter configuration saving endpoint
        if parsed_path.path == "/save":
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            params = urllib.parse.parse_qs(post_data)
            
            contact1 = params.get('contact1', [''])[0]
            contact2 = params.get('contact2', [''])[0]
            contact3 = params.get('contact3', [''])[0]
            vehicle = params.get('vehicle', [''])[0]
            custom_msg = params.get('custom_msg', [''])[0]
            
            print(f"[HTTP] Received Save Configuration request:")
            print(f"       Contact 1: {contact1}, Contact 2: {contact2}, Vehicle: {vehicle}")
            
            config_payload = {
                "contact1": contact1,
                "contact2": contact2,
                "contact3": contact3,
                "vehicle": vehicle,
                "custom_msg": custom_msg,
                "configured": True
            }
            save_local_config(config_payload)
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"CONFIG SAVED")
            return

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        
        # 1. Telemetry API endpoint for local polling
        if parsed_path.path == "/status":
            with telemetry_lock:
                lat = current_lat
                lng = current_lng
                speed = current_speed
                sats = current_sats
                gps_status = current_gps_status
                
            config = load_local_config()
            status_json = {
                "connected": True,
                "latitude": lat,
                "longitude": lng,
                "gps_status": gps_status,
                "satellites": sats,
                "speed_kmh": speed,
                "mode": "Armed & Monitoring" if config.get("configured") else "Configuration",
                "crash_triggered": (time.time() - last_crash_trigger_time < 3.0),
                "sensors": {
                    "accel_x": round(accel_x, 2),
                    "accel_y": round(accel_y, 2),
                    "accel_z": round(accel_z, 2),
                    "compass_heading": mag_heading,
                    "baro_pressure_hpa": baro_pressure,
                    "baro_temp_c": baro_temp
                }
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(status_json).encode('utf-8'))
            return
            
        # 2. Simulation Trigger Endpoint
        elif parsed_path.path == "/simulate":
            query = urllib.parse.parse_qs(parsed_path.query)
            severity = query.get('severity', ['HIGH'])[0]
            print(f"[HTTP] Triggering simulation severity: {severity}")
            threading.Thread(target=execute_crash_alert, args=(severity,)).start()
            
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b"SIMULATION SENT")
            return
            
        # 3. Live video MJPEG streaming
        elif parsed_path.path == "/live_feed":
            self.send_response(200)
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
            self.end_headers()
            
            try:
                while True:
                    frame = None
                    if hasattr(buffer_manager, 'frame_buffer') and len(buffer_manager.frame_buffer) > 0:
                        with buffer_manager.lock:
                            frame = buffer_manager.frame_buffer[-1].copy()
                            
                    if frame is not None:
                        # Downsample from 1080p to 640x480 for smooth Wi-Fi stream
                        if frame.shape[1] != 640 or frame.shape[0] != 480:
                            frame = cv2.resize(frame, (640, 480))
                            
                        # High light overexposure / whiteout warning
                        avg_brightness = cv2.mean(frame)[:3]
                        if sum(avg_brightness)/3.0 > 248.0:
                            cv2.putText(frame, "WHITEOUT / OVEREXPOSURE WARNING", (20, 240),
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                                        
                        success, encoded_img = cv2.imencode('.jpg', frame)
                        if success:
                            jpg_bytes = encoded_img.tobytes()
                            self.wfile.write(b"--frame\r\n")
                            self.wfile.write(b"Content-Type: image/jpeg\r\n")
                            self.wfile.write(f"Content-Length: {len(jpg_bytes)}\r\n\r\n".encode())
                            self.wfile.write(jpg_bytes)
                            self.wfile.write(b"\r\n")
                    time.sleep(0.05)
            except Exception as e:
                print(f"[HTTP] Client disconnected from stream: {e}")
            return
            
        # Serve keyframes or raw video fallback download
        super().do_GET()

def run_pi_server():
    server_address = ('', 8080)
    httpd = HTTPServer(server_address, PiServerHandler)
    print("[ONLINE] Standalone Server active on port 8080...")
    httpd.serve_forever()

# ========================================================
# CONSOLE DEBUG UTILITIES
# ========================================================
def debug_print_loop():
    print("[INFO] Continuous debug print loop active (2s interval).")
    while True:
        with telemetry_lock:
            gps_info = f"GPS: {current_gps_status} (Lat: {current_lat}, Lng: {current_lng}, Speed: {current_speed} km/h, Sats: {current_sats})"
        print(f"[DEBUG] Accel: X={accel_x:.3f}G, Y={accel_y:.3f}G, Z={accel_z:.3f}G | Heading: {mag_heading}° | Baro: Pressure={baro_pressure:.1f} hPa, Temp={baro_temp:.1f}C | {gps_info}")
        time.sleep(2)

def cli_command_listener():
    # Delay startup message slightly so it doesn't get buried under server startup logs
    time.sleep(1.0)
    print("\n[CLI] Interactive console commands active. Type 'help' to see available commands.\n")
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break  # EOF reached (e.g. running detached/service)
            cmd = line.strip().lower()
            if not cmd:
                continue
            
            if cmd == "help":
                print("\nAvailable commands:")
                print("  sensors / debug : Print current sensor readings once")
                print("  simulate [level]: Trigger a simulated crash (level: LOW, MEDIUM, HIGH)")
                print("  config          : Print current configuration")
                print("  help            : Show this message\n")
            elif cmd in ["sensors", "debug"]:
                with telemetry_lock:
                    gps_info = f"GPS: {current_gps_status} | Lat: {current_lat}, Lng: {current_lng}, Speed: {current_speed} km/h, Sats: {current_sats}"
                print("\n--- [CURRENT SENSOR READINGS] ---")
                print(f"Accelerometer  : X={accel_x:.3f}G, Y={accel_y:.3f}G, Z={accel_z:.3f}G")
                print(f"Compass/Heading: {mag_heading}°")
                print(f"Barometer      : Pressure={baro_pressure:.1f} hPa, Temp={baro_temp:.1f}°C")
                print(gps_info)
                print("---------------------------------\n")
            elif cmd.startswith("simulate"):
                parts = cmd.split()
                level = "HIGH"
                if len(parts) > 1:
                    level = parts[1].upper()
                    if level not in ["LOW", "MEDIUM", "HIGH"]:
                        level = "HIGH"
                print(f"[CLI] Triggering simulated crash with severity {level}")
                threading.Thread(target=execute_crash_alert, args=(level,)).start()
            elif cmd == "config":
                config = load_local_config()
                print("\n--- [LOCAL CONFIGURATION] ---")
                print(json.dumps(config, indent=2))
                print("-----------------------------\n")
            else:
                print(f"[CLI] Unknown command: '{cmd}'. Type 'help' for commands.")
        except Exception:
            break

if __name__ == "__main__":
    # Start Camera Recording Loop Thread
    rec_thread = threading.Thread(target=buffer_manager.start_recording_loop)
    rec_thread.daemon = True
    rec_thread.start()
    
    # Start Interactive CLI Listener Thread
    cli_thread = threading.Thread(target=cli_command_listener)
    cli_thread.daemon = True
    cli_thread.start()
    
    # Start Continuous Debug Printing Thread if --debug or -d flag is provided
    if "--debug" in sys.argv or "-d" in sys.argv:
        dbg_thread = threading.Thread(target=debug_print_loop)
        dbg_thread.daemon = True
        dbg_thread.start()
        
    # Start Web Server (blocks main thread)
    run_pi_server()
