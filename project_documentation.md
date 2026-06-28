# VehiSafe: Crash Detection & Telemetry System
## Project Documentation

VehiSafe is an end-to-end, high-performance IoT crash detection and emergency response system. It integrates high-frequency sensor processing, local edge computer vision (TensorFlow Lite), cloud synchronization, and a mobile dashboard to automate vehicular rescue dispatches.

---

## 1. System Architecture Overview

```mermaid
graph TD
    %% Hardware Components
    subgraph Hardware Layer (On-Vehicle IoT)
        ICM[ICM-20948 9-Axis IMU & Compass] -->|I2C| Pi[Raspberry Pi / main.py]
        BMP[BMP280 Barometer] -->|I2C| Pi
        CAM[Lenovo 300 Cam] -->|USB/10 FPS| Pi
        GPS_Pi[GPS Module /dev/serial0] -->|Serial/NMEA| Pi
        
        %% USB Modem
        Modem[Lapcare WiFi 6 4G USB Modem LDF72]
        Pi -->|Tethered / Wi-Fi Client| Modem
    end

    %% Cloud Integration
    subgraph Cloud Layer (Google Firebase)
        RTDB[(Firebase Realtime DB)]
        Storage[(Firebase Storage)]
    end

    %% App Integration
    subgraph Mobile Layer (Flutter App)
        App[VehiSafe App]
        BG[Foreground Isolate Service]
    end

    %% Communication Flows
    Pi -->|Upload mp4 & keyframes| Storage
    Pi -->|Telemetry & Alerts JSON| RTDB
    Modem -->|4G LTE cellular transit| RTDB
    Modem -->|4G LTE cellular transit| Storage
    
    BG -->|2s HTTP Polling| Pi
    BG -->|Fallback Polling| RTDB
    App -->|Biometrics / local_auth| Security[Secure Disarm]
    App -->|Wi-Fi Client| Modem
    App -->|Local Live Stream| Pi
```

When a vehicle experiences an impact exceeding **2.5G**:
1. The **Raspberry Pi** freezes its 15-second rolling RAM buffer, packages it into a video file, extracts keyframes, and invokes an on-device **TensorFlow Lite model** to analyze crash severity (calculating collision context and fire indicators).
2. The compiled video and keyframes are uploaded to **Firebase Storage** over the internet connection provided by the **Lapcare WiFi 6 4G USB Modem LDF72**. A structured report is saved in the **Firebase Realtime Database (RTDB)**.
3. The **Lapcare Wi-Fi 6 4G USB Modem LDF72** acts as the central communication gateway. It provides both:
   - A cellular 4G uplink for the Raspberry Pi to sync reports with Google Firebase.
   - A local Wi-Fi hotspot enabling the Raspberry Pi and the **VehiSafe Flutter Mobile App** to communicate locally.
4. The **Flutter Application** (backed by a persistent foreground background service) detects the crash status, rings the user's phone, launches a disarm countdown, and lets the user cancel the alert using FaceID/Fingerprint or PIN to prevent false alarms.
5. In case the countdown finishes without cancellation, the emergency alert is synced to Firebase and can be dispatched to emergency contacts via simulated SMS or a cloud gateway (e.g. Twilio/Firebase Functions).

---

## 2. Hardware Layer

### A. Raspberry Pi Service (`Hardware/phase_1/pi/`)
The Raspberry Pi serves as the central processing unit of the system, handling sensor ingestion, video loop indexing, AI processing, and local status serving.

* **Sensor Reader (`main.py`)**: Interfacing with sensors on the I2C bus:
  - **ICM-20948**: 9-axis IMU combining accelerometer (scale set to `+/- 2G` with a threshold trigger of `> 2.5G` magnitude vector ($G = \sqrt{X^2 + Y^2 + Z^2}$)), gyroscope, and magnetometer (determining the vehicle's heading).
  - **BMP280**: Ingests atmospheric pressure and ambient temperature.
* **Rolling Heap Video Buffer ([video_buffer.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/video_buffer.py))**:
  - Maintains a constant sliding frame window of **15 seconds** in RAM at **10 FPS** to avoid heavy microSD card write fatigue.
  - On crash triggers, freezes the array, writes a raw `mp4` video to `/home/pi/vehisafe/evidence/`, and extracts **5 critical keyframes** from the final 2 seconds of the impact.
* **TFLite AI Engine ([ai_engine.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/ai_engine.py))**:
  - Dynamically loads `coco_ssd_mobilenet_quant.tflite` utilizing **4 threads** to distribute heavy math arrays across all quad-core threads.
  - Runs classification on the 5 keyframes to search for vehicles (COCO IDs: Car, Truck, Bus, Motorbike) and fire/smoke signatures.
  - **Severity Logic**: Adds a severity score bonus of `+15` points if multiple vehicles are detected, and `+10` points if fire/smoke is classified.

---

### B. Network & Communication Gateway (Lapcare LDF72 USB Modem)
The Bharat Pi ESP32 and A7672S serial-AT cellular modules are retired. All network connectivity is consolidated into the **Lapcare WiFi 6 4G USB Modem LDF72**.

* **Modem Configuration**:
  - The LDF72 is plugged into a USB port on the Raspberry Pi or the vehicle's accessory power supply.
  - It houses a standard 4G LTE SIM card providing persistent mobile internet access.
  - It broadcasts a high-speed Wi-Fi 6 hotspot (SSID: `Lapcare_4G_XXXX` or custom configured).
* **Local Network Topology**:
  - **Raspberry Pi**: Connects to the Lapcare modem's Wi-Fi network (configured in `/etc/wpa_supplicant/wpa_supplicant.conf` or via NetworkManager) or uses USB network tethering (RNDIS interface) for direct wired networking.
  - **Flutter Mobile App**: Joins the same Lapcare Wi-Fi hotspot.
  - This local network enables high-bandwidth communication (e.g., streaming raw video feeds and telemetry logs) between the phone and the Raspberry Pi local REST API without consuming mobile data.
* **USB Modem SMS API Integration**:
  - **Authentication**: The modem utilizes custom HTTP Digest Authentication on all CGI API requests (with default credentials `admin`/`admin`), requesting authorization challenges via a `WWW-Authenticate` response header even on `200 OK` responses.
  - **XML Dispatch Payload**: SMS dispatches are sent by POSTing to `/xml_action.cgi?method=set&module=duster&file=message`. The XML contains the recipient's number, UCS-2 hex-encoded message body, and a structured local timestamp with GMT offsets.
  - **Fallback Dispatch**: If the modem is offline, the system falls back to logging simulated SMS outputs, preventing blocking issues.

---

## 3. Flutter Mobile Application

The VehiSafe application is built using Flutter and follows a feature-oriented directory structure.

```
lib/
├── core/
│   ├── constants/       # App styling configurations
│   ├── models/          # Telemetry, config, and event models
│   ├── providers/       # State providers & Riverpod managers
│   ├── router/          # GoRouter navigation paths
│   ├── services/        # Storage, notification, biometrics services
│   └── theme/           # Unified dark & light styling themes
└── features/
    ├── alert/           # SOS screens, PIN cancellations
    ├── dashboard/       # System health metrics & home
    ├── history/         # Incident logs
    ├── monitoring/      # Live sensor tracking & camera feed
    ├── onboarding/      # SoftAP hardware setup sequence
    └── settings/        # Configuration management
```

### A. Core Services & State Management
* **State Management (Riverpod)**:
  - [appSettingsProvider](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/core/providers/app_providers.dart#L90): Oversees local settings like developer mode, onboarding status, and cryptographically hashes the disarm PIN using SHA-256.
  - [activeAlertStateProvider](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/core/providers/app_providers.dart#L458): Global notifier tracking active crash status, disarm countdown numbers, GPS coordinate arrays, and Firebase media attachment links.
* **Foreground Service ([background_service.dart](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/core/services/background_service.dart))**:
  - Leverages `flutter_background_service` to run a continuous isolate in the background.
  - Initiates a background polling thread (every **2 seconds**) to contact the Raspberry Pi `/status` REST endpoint. If unreachable, it falls back to polling the Firebase Realtime Database.
  - Shows persistent user notification headers detailing GPS accuracy, lock status, speed, and satellites.
  - Coordinates countdown alerts, ringing local alarms, and triggering emergency sequences.

---

### B. Core Screens & UI Modules
1. **Onboarding Screen (`onboarding_screen.dart`)**:
   Guides the user through initial parameters (Emergency Contacts, Security PIN, and vehicle details). It prompts the user to join the Lapcare Wi-Fi Hotspot and POSTs the settings payload directly to the Raspberry Pi API `/save` endpoint.
2. **Dashboard / Home Screen (`home_screen.dart`)**:
   Represents the central control panel. It renders connection status indicators (Local Pi via Lapcare Wi-Fi vs. Firebase Cloud), quick action switches to simulate or trigger crash sequences, and telemetry cards.
3. **Monitoring Portal (`monitoring_screen.dart`)**:
   Renders a live MJPEG stream from the Pi camera (`/live_feed`), along with real-time tracking graphs for G-Force, barometric pressure, compass headings, and an analog speedometer dial.
4. **History Log (`history_screen.dart`)**:
   Pulls historical lists of alerts from the local Hive database. Clicking an incident reveals sensor snapshots, coordinates, contacts notified, and opens the evidence MP4 stream.
5. **Alert Sequence Screen (`alert_screen.dart`)**:
   A full-screen overlay that pops up when a crash is detected. It sounds an alarm, pulses a red background, and runs a countdown timer.
6. **PIN / Biometric Cancellation Screen (`pin_cancellation_screen.dart`)**:
   Provides safety checks to abort a false alarm. It prompts for the SHA-256 PIN or requests a Fingerprint/FaceID biometric scan via the [BiometricService](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/core/services/biometric_service.dart).

---

## 4. API & Endpoints Reference

### Raspberry Pi Server (Port `8080`)
| Endpoint | Method | Response / Payload | Purpose |
| :--- | :--- | :--- | :--- |
| `/status` | `GET` | JSON containing GPS, speed, sensors, crash flag | Real-time status polling for the app |
| `/live_feed` | `GET` | MJPEG video frame stream | Video monitoring dashboard |
| `/simulate` | `GET` | Text: `"SIMULATION SENT"` | Triggers simulated crash sequence with a specific severity |
| `/save` | `POST` | Text: `"CONFIG SAVED"` | Saves configuration to `config.json` |

---

## 5. Cloud Schemas & Database Structure

### Firebase Realtime Database
```json
{
  "device_status": {
    "VH001": {
      "deviceId": "VH001",
      "isConnected": true,
      "lastSeen": 1718642398,
      "currentMode": "Armed & Monitoring",
      "gpsStatus": "GPS Locked",
      "latitude": 12.971598,
      "longitude": 77.594562,
      "satellites": 9,
      "speed": 0.0,
      "sensors": {
        "accel_x": 0.02,
        "accel_y": -0.01,
        "accel_z": 0.99,
        "heading": 184,
        "pressure_hpa": 1013.25,
        "temperature_c": 25.4
      }
    }
  },
  "alerts": {
    "VH001": {
      "timestamp": 1718642405,
      "deviceId": "VH001",
      "latitude": 12.971598,
      "longitude": 77.594562,
      "speed_kmh": 45.2,
      "severityLevel": "HIGH",
      "baseScore": 8.5,
      "aiBonus": 15.0,
      "finalScore": 23.5,
      "videoUrl": "https://firebasestorage.googleapis.com/.../crash_1718642405.mp4",
      "keyframes": [
        "https://firebasestorage.googleapis.com/.../keyframe_0.jpg",
        "https://firebasestorage.googleapis.com/.../keyframe_1.jpg"
      ]
    }
  }
}
```

---

## 6. Python Services Code Deep-Dive

This section covers a detailed engineering review of the Python codebase running on the vehicle's Raspberry Pi compute node.

### A. Multi-Threading & Peripherals Controller ([main.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/main.py))

`main.py` is the centralized daemon process coordinating hardware sensors, camera buffers, cellular cloud sync, and local network APIs. To maintain real-time responsiveness and avoid UI latency, it employs a multi-threaded architecture with **6 concurrent execution threads**:

1. **Main Service Thread**: Spawns other threads, registers the camera loop, and acts as the blocking event loop for the local Web Server.
2. **Local HTTP Web Server Thread**: Serves REST APIs (`/status`, `/live_feed`, `/simulate`, `/save`) on port `8080`. Serves live camera streaming and processes configuration payloads.
3. **Camera Frame Recording Thread (`rec_thread`)**: Pulls video inputs from the camera source at 10 FPS, updating the RAM sliding array.
4. **GPS Serial Reader Thread (`gps_thread`)**: Decodes raw serial data on `/dev/serial0` at 9600 baud.
5. **Firebase Cloud Telemetry Sync Thread (`sync_thread`)**: Syncs vehicle coordinates and sensor state to Firebase Realtime Database status nodes every 5 seconds.
6. **Hardware Monitoring & Sensor Thread (`hw_thread`)**: Loops at 10Hz, checking dynamic sensor values and G-forces. On impact, spawns an asynchronous crash worker thread to handle notifications.

#### Thread Safety & Synchronization Locks
Because multiple threads read and write variables simultaneously, `main.py` relies on mutex locks to prevent race conditions:
* `telemetry_lock`: A `threading.Lock()` protecting variables shared between the GPS parser serial loop, the I2C sensor updater loop, the HTTP status reporter, and the Firebase sync worker.
* `buffer_manager.lock`: A `threading.Lock()` inside `VideoBufferManager` ensuring the camera frame recorder loop does not alter the RAM heap array while the crash encoder thread is writing the frozen frame array to disk.

#### I2C Sensor Reader Implementations
`main.py` defines three distinct hardware parser wrappers, each operating with a fallback simulation loop if hardware connections are lost:

1. **ICM20948 IMU & Compass Reader (`ICM20948Reader`)**:
   - Initializes communications via the Pimoroni `icm20948` library (address `0x68`, with fallback to `0x69`).
   - Reads 3-axis accelerometer values (returned directly in G) and 3-axis magnetometer values (returned in microteslas).
   - Computes the compass angle heading using standard trigonometry:
     $$\text{heading} = \arctan2(Y, X) \times \frac{180}{\pi}$$
   - Wraps negative results to return a clean `0` to `359` heading integer.
   - If the sensor is not detected or the library is not installed, it runs a simulation/emulation fallback generating stable gravity values (`accel_z = 1.0G` flat, with minor random noise) and randomized heading values to allow off-vehicle testing.

3. **BMP280 Barometer Reader (`BMP280Reader`)**:
   - Verifies communication at address `0x76` (or fallback `0x77`) by checking register `0xD0` for active chip IDs (`0x58`, `0x56`, `0x57`, `0x60`).
   - Reads registers `0xF7` through `0xFC` to capture atmospheric pressure and ambient temperature.
   - Converts raw ADC values to Celsius and Hectopascals (hPa). If disconnected, it emulates pressure centered at sea-level averages (`1013.2 hPa`).

#### GPS NMEA Decoder (`GPSReaderThread`)
* Runs a persistent background loop monitoring the `/dev/serial0` serial queue.
* Employs non-blocking character-by-character checks to parse sentences, preventing buffer memory leaks by flushing the byte queue if lines exceed 120 characters without a line break.
* Extracts GPS parameters from standard NMEA strings:
  - **`$GPRMC` / `$GNRMC`**: Parses status ('A' = Active, 'V' = Void), converts coordinate latitude/longitude strings to decimal degrees, and translates speed from knots to km/h (multiplying by `1.852`).
  - **`$GPGGA` / `$GNGGA`**: Extracts active satellite counts.
* Tracks a **Heartbeat Decay Timeout**: If serial data transmission stops for more than 5 seconds, it resets status registers to `"No Signal"` and clears sat counts, warning the system of GPS failures.

---

### B. rolling Camera Buffer Manager ([video_buffer.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/video_buffer.py))

The `VideoBufferManager` class handles high-speed video capture and compiles video files:

* **Camera Ingestion Pipeline**:
  - Initializes `cv2.VideoCapture` targeting source `0`.
  - Configures capture dimensions (1080p resolution: `1920x1080`) to capture fine details (e.g., license plates).
  - Constrains capture loops to **10 FPS** via `time.sleep()`. This pacing matches the RAM limit and keeps evidence files small (under 1.5MB) for quick uploads over 4G cellular links.
* **RAM Sliding Heap**:
  - Appends OpenCV image frames to a standard Python list.
  - Maintains a maximum buffer size ($15 \text{ seconds} \times 10 \text{ FPS} = 150 \text{ frames}$).
  - Pops the oldest index (`self.frame_buffer.pop(0)`) when the maximum limit is reached.
* **Uncompressed MP4 Compiler (`freeze_buffer`)**:
  - Clones the frame list inside a thread-safe mutex block to allow the camera loop to continue recording without interruptions.
  - Instantiates `cv2.VideoWriter` targeting the local evidence path (`/home/pi/vehisafe/evidence/crash_[timestamp].mp4`) using the raw fourcc format `'mp4v'`.
  - Sequentially writes the cached frames and releases resources.
  - If the frame buffer is empty, it writes a fallback video with blank frames to ensure the cloud upload pipeline does not crash.
* **Impact Keyframe Extraction (`extract_keyframes`)**:
  - Extracts exactly **5 keyframes** from the final 2 seconds of the buffer (the impact window).
  - Downsamples frames from 1080p to `640x480` to speed up cellular uploads.
  - Saves frames as `keyframe_[0-4].jpg` in the evidence directory.

---

### C. TensorFlow Lite AI Severity Classifier ([ai_engine.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/ai_engine.py))

`OptimizedAIEngine` loads a Quantized Coco SSD MobileNet model to score accident severity.

* **Dynamic Runtime Import**:
  - To ensure cross-platform compatibility, it checks and imports the first available TF Lite runtime module:
    1. `ai_edge_litert.interpreter` (Latest Google AI Edge)
    2. `tflite_runtime.interpreter` (Raspberry Pi standalone runtime)
    3. `tensorflow.lite` (Full TensorFlow library)
* **Interpreter Optimization**:
  - Loads `coco_ssd_mobilenet_quant.tflite` from disk.
  - Configures **4 execution threads** to distribute operations across all Raspberry Pi CPU cores, reducing inference time to under 80ms per frame.
  - Allocates input/output tensors and extracts shape constraints.
* **Input Pre-processing**:
  - Reads keyframe images and resizes them to match the model's expected dimensions (typically `300x300`).
  - Checks model data types. If using float models, it normalizes pixels from `0-255` integers to floating-point values between `-1.0` and `1.0`:
    $$\text{normalized} = \frac{\text{pixel}}{127.5} - 1.0$$
* **Post-processing and Class Scoring**:
  - Invokes the interpreter and reads the output boxes, classes, and confidence score arrays.
  - Filters results with a confidence threshold of `> 0.45` to eliminate false positives.
  - **Dynamic Severity Bonuses (`calculate_severity_bonuses`)**:
    - Scans detections across all 5 keyframes.
    - Counts vehicle indices (COCO IDs: Car [2], Motorbike [3], Bus [6], Truck [8]).
    - Scans for fire/smoke indices (ID [10]).
    - Computes and returns severity bonuses: **+15** points if multiple vehicles are detected, and **+10** points if fire/smoke is classified.

