# VehiSafe: Crash Detection & Telemetry System

VehiSafe is an end-to-end crash detection, analysis, and notification ecosystem designed for vehicles. By connecting on-vehicle IoT hardware (Raspberry Pi paired with a Lapcare WiFi 6 4G USB Modem LDF72) to Google Firebase and a feature-rich Flutter dashboard app, VehiSafe automates accident severity classification and triggers immediate emergency dispatches.

---

## 🚀 Key Features

* **High-Frequency Telemetry Ingestion**: Continuous reading of IMU Accelerometer variables, Barometer altitude, and dynamic compass heading sensors on the Raspberry Pi.
* **Automatic Crash Detection**: G-force monitoring with vector-based impact thresholds (>2.5G).
* **On-Device Computer Vision**: Runs local TensorFlow Lite quantization models (SSD MobileNet) to grade crash severity based on vehicle and fire detections.
* **Lapcare LDF72 4G USB Gateway**: Consolidates network transit. Provides high-speed 4G cellular backhaul for Firebase syncs, and hosts a local Wi-Fi hotspot for app-to-Pi local connectivity.
* **Local WiFi Configuration Portal**: Connects the Flutter app to the Lapcare hotspot to sync settings (emergency contacts, SHA-256 secure disarm PIN, vehicle profile) directly to the Raspberry Pi.
* **Biometric Security Disarm**: Prevents accidental false alarm triggers using FaceID/Fingerprint authentication before the countdown timer expires.

---

## 📖 System Documentation

A comprehensive guide covering the architectural diagram, hardware sensor connections, Python loop manager, Lapcare modem configuration, Flutter app structure, and REST API routes has been created:

👉 **[Read the Full VehiSafe Project Documentation](file:///Users/sameersmacbookair/Documents/VEHISAFC/project_documentation.md)**

---

## 🛠️ Quick Start

### 1. Raspberry Pi Python Services & Sensors Setup
Deploy the Python environment onto your Raspberry Pi:
```bash
cd Hardware/phase_1/pi
pip3 install opencv-python numpy smbus2 icm20948
# Start the monitoring loop and live feed HTTP server
python3 main.py
```
* Python scripts map to:
  - **[main.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/main.py)** (Main sensor reader + local REST APIs)
  - **[video_buffer.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/video_buffer.py)** (RAM Rolling Video Heap)
  - **[ai_engine.py](file:///Users/sameersmacbookair/Documents/VEHISAFC/Hardware/phase_1/pi/ai_engine.py)** (TF Lite Inference engine)

### 2. Lapcare LDF72 Modem Integration
1. Plug the Lapcare USB Dongle LDF72 into the Raspberry Pi or the vehicle's USB power slot.
2. Ensure the Pi's Wi-Fi client is configured to connect automatically to the Lapcare hotspot (typically SSID: `Lapcare_4G_XXXX`).

### 3. Flutter Mobile App
To run the dashboard and configuration application:
```bash
# Get flutter dependencies
flutter pub get
# Launch the app
flutter run
```
* Connect your mobile device to the same Lapcare Wi-Fi hotspot to allow local communication with the Raspberry Pi.
* **Primary Entrypoint**: [main.dart](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/main.dart)
* **Background Isolate**: [background_service.dart](file:///Users/sameersmacbookair/Documents/VEHISAFC/lib/core/services/background_service.dart)

