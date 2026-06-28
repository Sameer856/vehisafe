import numpy as np
import cv2
import os

# Robust import check for different TensorFlow Lite runtimes
tflite = None
for import_name in ['ai_edge_litert.interpreter', 'tflite_runtime.interpreter', 'tensorflow.lite']:
    try:
        tflite = __import__(import_name, fromlist=['Interpreter'])
        print(f"[INFO] Successfully imported TF Lite interpreter from '{import_name}'")
        break
    except ImportError:
        continue

class OptimizedAIEngine:
    def __init__(self, model_path="/home/pi/vehisafe/models/coco_ssd_mobilenet_quant.tflite"):
        self.model_path = model_path
        self.mock_mode = True
        
        if tflite is not None and os.path.exists(model_path):
            try:
                # Configure 4 threads to push the math processing across all CPU cores
                self.interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
                self.interpreter.allocate_tensors()
                self.input_details = self.interpreter.get_input_details()
                self.output_details = self.interpreter.get_output_details()
                self.input_height = self.input_details[0]['shape'][1]
                self.input_width = self.input_details[0]['shape'][2]
                self.mock_mode = False
                print(f"[INFO] AI Engine successfully loaded model: {model_path}")
            except Exception as e:
                print(f"[WARNING] Error initializing interpreter: {e}. Falling back to Simulation Mode.")
        else:
            if tflite is None:
                print("[WARNING] TF Lite runtime libraries not found. AI Engine will run in Simulation Mode.")
            else:
                print(f"[WARNING] Model file not found at {model_path}. AI Engine will run in Simulation Mode.")

    def analyze_frame(self, image_path):
        if self.mock_mode:
            # In simulation mode, return mock classifications for demonstration
            import random
            detected = []
            if random.random() > 0.4:
                detected.append(2)  # COCO ID 2: Car
            if random.random() > 0.7:
                detected.append(3)  # COCO ID 3: Motorbike
            if random.random() > 0.9:
                detected.append(10) # COCO ID 10: Fire / Smoke placeholder
            return detected

        try:
            raw_img = cv2.imread(image_path)
            if raw_img is None:
                return []
            resized_img = cv2.resize(raw_img, (self.input_width, self.input_height))
            input_data = np.expand_dims(resized_img, axis=0)
            
            if self.input_details[0]['dtype'] == np.uint8:
                input_data = input_data.astype(np.uint8)
            else:
                input_data = (input_data.astype(np.float32) / 127.5) - 1.0

            self.interpreter.set_tensor(self.input_details[0]['index'], input_data)
            self.interpreter.invoke()

            classes = self.interpreter.get_tensor(self.output_details[1]['index'])[0]
            scores = self.interpreter.get_tensor(self.output_details[2]['index'])[0]
            num_detections = int(self.interpreter.get_tensor(self.output_details[3]['index'])[0])

            detected_labels = []
            for i in range(num_detections):
                if scores[i] > 0.45:  # Confidence validation threshold
                    detected_labels.append(int(classes[i]))
            return detected_labels
        except Exception as e:
            print(f"[ERROR] AI analysis failed on {image_path}: {e}")
            return []

    def calculate_severity_bonuses(self, frame_paths):
        vehicle_class_ids = [2, 3, 4, 6, 8]  # COCO indices for Car, Truck, Bus, Motorbike, Bicycle
        fire_class_id = 10                  # Custom/COCO placeholder for fire/smoke indices
        
        max_vehicles_seen = 0
        fire_detected = False

        for path in frame_paths:
            labels = self.analyze_frame(path)
            vehicles_in_frame = sum(1 for label in labels if label in vehicle_class_ids)
            if vehicles_in_frame > max_vehicles_seen:
                max_vehicles_seen = vehicles_in_frame
            if fire_class_id in labels:
                fire_detected = True

        ai_bonus_points = 0
        if max_vehicles_seen > 1:
            ai_bonus_points += 15
            print("[AI EVALUATION] Multiple vehicles detected (+15 Severity Bonus)")
        if fire_detected:
            ai_bonus_points += 10
            print("[AI EVALUATION] Visible fire ignition/smoke detected (+10 Severity Bonus)")
            
        return ai_bonus_points
