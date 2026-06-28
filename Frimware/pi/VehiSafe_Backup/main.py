import threading
import time
import os
from http.server import SimpleHTTPRequestHandler, HTTPServer
import urllib.parse
import cv2  # Added explicitly for whiteout handling
from video_buffer import VideoBufferManager
from ai_engine import OptimizedAIEngine

# Initialize manager (Note: You can pass downsampled resolution configs if supported)
buffer_manager = VideoBufferManager(video_source=0)
ai_engine = OptimizedAIEngine()

# Tell the server to look directly at our evidence directory path
EVIDENCE_DIR = "/home/pi/vehisafe/evidence"

class PiServerHandler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        # Safely map all requested file paths directly inside the EVIDENCE_DIR
        parsed_path = urllib.parse.urlparse(path)
        return os.path.join(EVIDENCE_DIR, parsed_path.path.lstrip('/'))

    def end_headers(self):
        # Inject CORS headers for both POST endpoints and GET media streams (essential for Flutter)
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

    def do_POST(self):
        parsed_path = urllib.parse.urlparse(self.path)
        
        if parsed_path.path == "/trigger_crash":
            print("\n[MASTER NETWORK INTERRUPT] Crash request captured over the wireless subnet link!")
            
            frozen_clip = buffer_manager.freeze_buffer(save_destination_dir=EVIDENCE_DIR)
            keyframes = buffer_manager.extract_keyframes(frozen_clip)
            
            start_ai_time = time.time()
            ai_bonuses = ai_engine.calculate_severity_bonuses(keyframes)
            execution_duration = time.time() - start_ai_time
            
            file_name = os.path.basename(frozen_clip)
            # Construct updated live local wireless video URL string using the router subnet IP
            video_url = f"http://192.168.202.90:8080/{file_name}"
            
            print(f"[SUCCESS] Severity scoring finalized. Video available at: {video_url}")
            
            # Formulate JSON payload returning both the bonus points and the direct playback URL link
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            response_json = f'{{"status":"success","ai_bonus":{ai_bonuses},"video_link":"{video_url}","processing_time_sec":{execution_duration:.2f}}}'
            self.wfile.write(response_json.encode('utf-8'))
            return

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        
        # --- Camera Live Setup Webpage ---
        if parsed_path.path == "/setup":
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>VehiSafe Camera Alignment & Setup</title>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body {
                        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                        background-color: #121212;
                        color: #ffffff;
                        text-align: center;
                        margin: 0;
                        padding: 20px;
                    }
                    h1 { color: #ff3b30; margin-bottom: 5px; font-weight: 800; font-size: 22px; }
                    p { color: #aaaaaa; margin-top: 5px; font-size: 13px; }
                    .video-container {
                        position: relative;
                        display: inline-block;
                        margin: 20px auto;
                        border: 3px solid #ff3b30;
                        border-radius: 12px;
                        overflow: hidden;
                        box-shadow: 0 8px 24px rgba(255, 59, 48, 0.2);
                        max-width: 100%;
                        background-color: #000;
                        width: 640px; /* Locked down to 640 for cheap hardware aspect ratios */
                        height: 480px;
                    }
                    img {
                        display: block;
                        width: 100%;
                        height: 100%;
                        object-fit: contain;
                    }
                    /* Alignment Grid Overlays */
                    .grid-line-h {
                        position: absolute;
                        left: 0;
                        width: 100%;
                        height: 1px;
                        background-color: rgba(0, 255, 0, 0.5);
                        pointer-events: none;
                    }
                    .grid-line-v {
                        position: absolute;
                        top: 0;
                        height: 100%;
                        width: 1px;
                        background-color: rgba(0, 255, 0, 0.5);
                        pointer-events: none;
                    }
                    .center-circle {
                        position: absolute;
                        top: 50%;
                        left: 50%;
                        width: 40px;
                        height: 40px;
                        border: 2px dashed #00ff00;
                        border-radius: 50%;
                        transform: translate(-50%, -50%);
                        pointer-events: none;
                    }
                    .instructions {
                        max-width: 600px;
                        margin: 20px auto;
                        background-color: #1c1c1e;
                        padding: 15px;
                        border-radius: 10px;
                        text-align: left;
                        border: 1px solid #2c2c2e;
                    }
                    .instructions h3 { color: #00ff00; margin-top: 0; font-size: 15px; }
                    .instructions li {
                        margin-bottom: 8px;
                        font-size: 13px;
                        color: #e5e5ea;
                    }
                </style>
            </head>
            <body>
                <h1>VEHISAFE CAMERA ALIGNMENT</h1>
                <p>Adjust camera angle so the horizon aligns with the center horizontal green guideline.</p>
                
                <div class="video-container">
                    <img src="/live_feed" alt="Live Camera Stream">
                    <div class="grid-line-h" style="top: 33.3%;"></div>
                    <div class="grid-line-h" style="top: 50%;"></div>
                    <div class="grid-line-h" style="top: 66.6%;"></div>
                    <div class="grid-line-v" style="left: 33.3%;"></div>
                    <div class="grid-line-v" style="left: 50%;"></div>
                    <div class="grid-line-v" style="left: 66.6%;"></div>
                    <div class="center-circle"></div>
                </div>
                
                <div class="instructions">
                    <h3>Setup Checklist (Optimized for 640x480):</h3>
                    <ul>
                        <li><strong>Horizon Alignment</strong>: Ensure the road horizon is aligned near the middle horizontal line.</li>
                        <li><strong>Hood View</strong>: The bottom third of the frame should capture a small portion of your vehicle's hood as a spatial reference.</li>
                        <li><strong>Stability</strong>: Securely tighten the camera mount to prevent vibration artifacts during edge processing.</li>
                        <li><strong>Lighting Check</strong>: If screen flags a whiteout error, try angling the lens slightly downward towards the road to avoid direct solar overexposure.</li>
                    </ul>
                </div>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
            return

        # --- MJPEG Live Stream Endpoint with Whiteout Management ---
        elif parsed_path.path == "/live_feed":
            self.send_response(200)
            self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
            self.end_headers()
            
            print("[LIVE STREAM] Client connected to live 640x480 camera feed.")
            try:
                while True:
                    frame = None
                    if hasattr(buffer_manager, 'frame_buffer') and len(buffer_manager.frame_buffer) > 0:
                        lock = getattr(buffer_manager, 'lock', None)
                        if lock:
                            with lock:
                                frame = buffer_manager.frame_buffer[-1].copy()
                        else:
                            frame = buffer_manager.frame_buffer[-1].copy()
                    
                    if frame is not None:
                        # Ensure frame sizing is matched explicitly to avoid streaming artifacts
                        if frame.shape[1] != 640 or frame.shape[0] != 480:
                            frame = cv2.resize(frame, (640, 480))

                        # --- Hardware Whiteout Detection ---
                        # Calculate mean channel value. BGR average pixel intensity.
                        avg_channels = cv2.mean(frame)[:3]
                        overall_brightness = sum(avg_channels) / 3.0
                        
                        # If average intensity is above 248, it is a washed-out/blank frame
                        if overall_brightness > 248.0:
                            print("[WARNING] Cheap Camera sensor overexposed or glitched (Whiteout detected).")
                            # Write warning text straight on the video so you can diagnose visually
                            cv2.putText(frame, "HARDWARE OVEREXPOSURE / WHITEOUT", (20, 240), 
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                        
                        success, encoded_image = cv2.imencode('.jpg', frame)
                        if success:
                            jpeg_bytes = encoded_image.tobytes()
                            self.wfile.write(b"--frame\r\n")
                            self.wfile.write(b"Content-Type: image/jpeg\r\n")
                            self.wfile.write(f"Content-Length: {len(jpeg_bytes)}\r\n\r\n".encode())
                            self.wfile.write(jpeg_bytes)
                            self.wfile.write(b"\r\n")
                    
                    # Stream at a reliable ~20 FPS. Cheap sensors choke if requested faster.
                    time.sleep(0.05)
            except Exception as e:
                print(f"[LIVE STREAM] Client disconnected or stream error: {e}")
            return

        # --- Evidence File Serving (GET with HTTP 206 Range Request Support) ---
        file_path = self.translate_path(self.path)
        if os.path.exists(file_path) and os.path.isfile(file_path):
            file_size = os.path.getsize(file_path)
            range_header = self.headers.get('Range')
            
            start_byte = 0
            end_byte = file_size - 1
            is_range = False

            # Parse HTTP Range header if present
            if range_header and range_header.startswith('bytes='):
                is_range = True
                try:
                    ranges = range_header.split('=')[1].split('-')
                    if ranges[0]:
                        start_byte = int(ranges[0])
                    if len(ranges) > 1 and ranges[1]:
                        end_byte = int(ranges[1])
                except ValueError:
                    pass

            if start_byte >= file_size:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{file_size}')
                self.end_headers()
                return

            if end_byte >= file_size:
                end_byte = file_size - 1

            content_length = end_byte - start_byte + 1

            # Respond with 206 (Partial Content) if a Range request, otherwise 200
            if is_range:
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start_byte}-{end_byte}/{file_size}')
            else:
                self.send_response(200)

            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(content_length))
            if file_path.endswith('.mp4'):
                self.send_header('Content-type', 'video/mp4')
            elif file_path.endswith('.jpg'):
                self.send_header('Content-type', 'image/jpeg')
            self.end_headers()

            # Stream the file in 8KB memory-safe chunks
            try:
                with open(file_path, 'rb') as f:
                    f.seek(start_byte)
                    bytes_to_send = content_length
                    while bytes_to_send > 0:
                        chunk_size = min(8192, bytes_to_send)
                        chunk = f.read(chunk_size)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        bytes_to_send -= len(chunk)
            except (ConnectionResetError, BrokenPipeError):
                # Safely ignore player cancellations when buffering seeks
                pass
            return
        else:
            # Fallback to standard handler if file isn't directly matched
            super().do_GET()

def run_pi_master_server():
    server_address = ('', 8080)
    httpd = HTTPServer(server_address, PiServerHandler)
    print("[ONLINE] Master Server ready. Video streaming enabled on port 8080...")
    httpd.serve_forever()

if __name__ == "__main__":
    # Ensure evidence directory exists
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    
    buffer_thread = threading.Thread(target=buffer_manager.start_recording_loop)
    buffer_thread.daemon = True
    buffer_thread.start()
    
    run_pi_master_server()
