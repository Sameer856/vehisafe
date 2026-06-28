import numpy as np
import cv2
import ai_edge_litert.interpreter as tflite

class OptimizedAIEngine:
    def __init__(self, model_path="/home/pi/vehisafe/models/coco_ssd_mobilenet_quant.tflite"):
        # Explicitly configure 4 threads to push the math processing across all 4 CPU cores
        self.interpreter = tflite.Interpreter(model_path=model_path, num_threads=4)
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()
        self.input_height = self.input_details[0]['shape'][1]
        self.input_width = self.input_details[0]['shape'][2]

    def analyze_frame(self, image_path):
        raw_img = cv2.imread(image_path)
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
            if scores[i] > 0.45:  # Confidence validation ceiling
                detected_labels.append(int(classes[i]))
        return detected_labels

    def calculate_severity_bonuses(self, frame_paths):
        vehicle_class_ids = [2, 3, 4, 6, 8]  # COCO indices for Car, Truck, Bus, Motorbike
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
            print("[AI EVALUATION] Visible fire bay ignition detected (+10 Severity Bonus)")
            
        return ai_bonus_points
