import cv2
import time
import os
import numpy as np
import threading
import subprocess
import shutil

class VideoBufferManager:
    def __init__(self, video_source=0, duration_sec=15):
        self.cap = cv2.VideoCapture(video_source)
        self.duration_sec = duration_sec
        self.fps = 10  # Target frame capture pacing (10 FPS reduces file size significantly)
        
        # Explicitly configure Lenovo 300 UHD
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
        
        # Verify active dimensions
        self.frame_width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.frame_height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        print(f"[INFO] Camera source {video_source} initialized at: {self.frame_width}x{self.frame_height}")
        
        # rolling frame buffer in RAM
        self.frame_buffer = []
        self.max_buffer_size = self.fps * self.duration_sec
        self.lock = threading.Lock()  # Thread lock safety

    def start_recording_loop(self):
        print(f"[INFO] Initializing rolling {self.duration_sec}-second RAM heap video buffer at {self.fps} FPS...")
        while self.cap.isOpened():
            ret, frame = self.cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            with self.lock:
                self.frame_buffer.append(frame.copy())
                # Maintain the strict sliding history window size
                if len(self.frame_buffer) > self.max_buffer_size:
                    self.frame_buffer.pop(0)
                    
            time.sleep(1.0 / self.fps)

    def freeze_buffer(self, save_destination_dir="/home/pi/vehisafe/evidence"):
        if not os.path.exists(save_destination_dir):
            try:
                os.makedirs(save_destination_dir, exist_ok=True)
            except Exception:
                # Fallback to local script folder
                save_destination_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "evidence")
                os.makedirs(save_destination_dir, exist_ok=True)
            
        timestamp = int(time.time())
        stable_file_path = os.path.join(save_destination_dir, f"crash_{timestamp}.mp4")
        
        with self.lock:
            snapshot_frames = list(self.frame_buffer)
            
        if len(snapshot_frames) == 0 or snapshot_frames[0] is None or snapshot_frames[0].shape[0] == 0 or snapshot_frames[0].shape[1] == 0:
            print("[WARNING] Memory array empty or invalid frame size. Injected fallback blank frames.")
            w = self.frame_width if self.frame_width > 0 else 640
            h = self.frame_height if self.frame_height > 0 else 480
            blank_frame = np.zeros((h, w, 3), dtype=np.uint8)
            snapshot_frames = [blank_frame] * 5

        # Get actual dimensions from the first frame
        height, width = snapshot_frames[0].shape[:2]
        if height == 0 or width == 0:
            height = 480
            width = 640
        
        try:
            print(f"[INFO] Compiling raw frames to MP4 ({width}x{height}) without compression...")
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            out = cv2.VideoWriter(stable_file_path, fourcc, self.fps, (width, height))
            for frame in snapshot_frames:
                out.write(frame)
            out.release()
            
            if os.path.exists(stable_file_path) and os.path.getsize(stable_file_path) > 0:
                print(f"[SUCCESS] Raw MP4 video created: {stable_file_path} (Size: {os.path.getsize(stable_file_path)/1024:.1f} KB)")
                
                # Compress and transcode to mobile-friendly H.264 using FFmpeg (makes video playable on iOS/Android and reduces size by 90%)
                h264_file_path = stable_file_path.replace(".mp4", "_h264.mp4")
                try:
                    print(f"[FFMPEG] Transcoding raw video to compressed H.264: {h264_file_path} ...")
                    cmd = [
                        "ffmpeg", "-y", "-i", stable_file_path,
                        "-vcodec", "libx264", "-pix_fmt", "yuv420p",
                        "-profile:v", "baseline", "-level", "3.0",
                        h264_file_path
                    ]
                    import subprocess
                    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=12)
                    
                    if os.path.exists(h264_file_path) and os.path.getsize(h264_file_path) > 0:
                        os.replace(h264_file_path, stable_file_path)
                        print(f"[FFMPEG SUCCESS] Transcoded and compressed video: {stable_file_path} (New Size: {os.path.getsize(stable_file_path)/1024:.1f} KB)")
                except Exception as fe:
                    print(f"[FFMPEG WARNING] Transcoding failed: {fe}. Using original raw video.")
                    if os.path.exists(h264_file_path):
                        try: os.remove(h264_file_path)
                        except: pass
                        
                return stable_file_path
        except Exception as e:
            print(f"[ERROR] Failed to compile raw MP4 video: {e}")

        # Ultimate fallback (empty placeholder)
        with open(stable_file_path, 'wb') as f:
            f.write(b'\x00' * 100)
        print("[ERROR] All video compile paths failed. Created dummy placeholder video.")
        return stable_file_path

    def extract_keyframes(self, video_path, count=5):
        """Extracts exactly 5 sequential frames from the in-memory array data."""
        evidence_dir = os.path.dirname(video_path) if video_path else "/home/pi/vehisafe/evidence"
        if not os.path.exists(evidence_dir):
            try:
                os.makedirs(evidence_dir, exist_ok=True)
            except Exception:
                evidence_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "evidence")
                os.makedirs(evidence_dir, exist_ok=True)

        with self.lock:
            total_buffered = len(self.frame_buffer)
            extracted_paths = []
            
            # Focus on pulling from the final 2 seconds of the buffer arrays (the impact point)
            start_index = max(0, total_buffered - (self.fps * 2))
            available_slice = self.frame_buffer[start_index:]
            
            if len(available_slice) < count:
                available_slice = self.frame_buffer
                
            if len(available_slice) == 0:
                print("[WARNING] Frame buffer empty for keyframes. Injecting blank fallback keyframes.")
                w = self.frame_width if self.frame_width > 0 else 640
                h = self.frame_height if self.frame_height > 0 else 480
                blank_frame = np.zeros((h, w, 3), dtype=np.uint8)
                available_slice = [blank_frame] * count
                
            step = max(1, len(available_slice) // count)
            
            for i in range(count):
                idx = min(i * step, len(available_slice) - 1)
                img_path = os.path.join(evidence_dir, f"keyframe_{i}.jpg")
                
                # Make sure parent dir exists
                os.makedirs(os.path.dirname(img_path), exist_ok=True)
                
                frame = available_slice[idx]
                if frame is None or frame.shape[0] == 0 or frame.shape[1] == 0:
                    frame = np.zeros((480, 640, 3), dtype=np.uint8)
                
                # Resize keyframes to 640x480 to speed up uploads
                resized_kf = cv2.resize(frame, (640, 480))
                cv2.imwrite(img_path, resized_kf)
                extracted_paths.append(img_path)
                
        return extracted_paths
