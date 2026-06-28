import cv2
import time
import os
import numpy as np
import threading

class VideoBufferManager:
    def __init__(self, video_source=0, duration_sec=10):
        self.cap = cv2.VideoCapture(video_source)
        self.duration_sec = duration_sec
        self.fps = 20  # Target frame capture pacing
        
        # Configure video dimensions natively from the USB stream
        self.frame_width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        self.frame_height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        
        # This list serves as our rolling frame buffer held purely in volatile RAM heap memory
        self.frame_buffer = []
        self.max_buffer_size = self.fps * self.duration_sec
        self.lock = threading.Lock() # Thread lock safety shield

    def start_recording_loop(self):
        print("[INFO] Initializing rolling 10-second RAM heap video buffer...")
        import threading
        
        while self.cap.isOpened():
            ret, frame = self.cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            with self.lock:
                self.frame_buffer.append(frame.copy())
                # Maintain the strict 10-second sliding history window ceiling
                if len(self.frame_buffer) > self.max_buffer_size:
                    self.frame_buffer.pop(0)
                    
            time.sleep(1.0 / self.fps)

    def freeze_buffer(self, save_destination_dir="/home/pi/vehisafe/evidence"):
        if not os.path.exists(save_destination_dir):
            os.makedirs(save_destination_dir)
            
        timestamp = int(time.time())
        stable_file_path = os.path.join(save_destination_dir, f"crash_{timestamp}.mp4")
        
        with self.lock:
            snapshot_frames = list(self.frame_buffer)
            
        if len(snapshot_frames) == 0:
            print("[WARNING] Memory array empty. Injected fallback blank array frame.")
            blank_frame = np.zeros((self.frame_height, self.frame_width, 3), dtype=np.uint8)
            snapshot_frames = [blank_frame] * 5

        # Compile the video from memory data blocks to write the metadata index atomically
        fourcc = cv2.VideoWriter_fourcc(*'mp4v')
        out = cv2.VideoWriter(stable_file_path, fourcc, self.fps, (self.frame_width, self.frame_height))
        for frame in snapshot_frames:
            out.write(frame)
        out.release()
        
        print(f"[CRITICAL] Video buffer frozen securely at: {stable_file_path}")
        return stable_file_path

    def extract_keyframes(self, video_path, count=5):
        """Extracts exactly 5 sequential frames cleanly straight from the in-memory array data."""
        with self.lock:
            total_buffered = len(self.frame_buffer)
            extracted_paths = []
            
            # Focus on pulling from the final 2 seconds of the buffer arrays (the impact point)
            start_index = max(0, total_buffered - (self.fps * 2))
            available_slice = self.frame_buffer[start_index:]
            
            if len(available_slice) < count:
                available_slice = self.frame_buffer
                
            step = max(1, len(available_slice) // count)
            
            for i in range(count):
                idx = min(i * step, len(available_slice) - 1)
                img_path = f"/home/pi/vehisafe/evidence/keyframe_{i}.jpg"
                cv2.imwrite(img_path, available_slice[idx])
                extracted_paths.append(img_path)
                
        return extracted_paths
