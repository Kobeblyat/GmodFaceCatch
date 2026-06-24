
import asyncio
import functools
import time
import json
import os
import queue
import math
import subprocess

from websockets.exceptions import ConnectionClosed
from websockets.asyncio.server import serve, ServerConnection

import cv2
import numpy as np

import mediapipe as mp
import aioprocessing


BaseOptions = mp.tasks.BaseOptions
FaceLandmarker = mp.tasks.vision.FaceLandmarker
FaceLandmarkerOptions = mp.tasks.vision.FaceLandmarkerOptions
FaceLandmarkerResult = mp.tasks.vision.FaceLandmarkerResult
VisionRunningMode = mp.tasks.vision.RunningMode

# You must supply your own face landmarker model for this to work.
# You can get one online pretty easily from Google's mediapipe website
MODEL_PATH = 'face_landmarker.task'

# Use IPv4 loopback explicitly so the GMod websocket client and Python server
# don't disagree on localhost resolution.
SOCKET_HOST = "127.0.0.1"

# You must specify the same socket port in the GMod socket file
SOCKET_PORT = "8667"

# How often we stream the data through websockets
# Setting this too high results in backpressure, as
# client websocket cannot receive it as fast as the server
# can send it out
SENDING_FREQUENCY = 2000  # Hz

# Best-effort realtime capture settings. 640x480 MJPG is a practical target for
# many USB webcams when aiming for 60 FPS without overloading CPU-side inference.
TARGET_CAMERA_FPS = 60
CAMERA_WIDTH = 640
CAMERA_HEIGHT = 480
CAMERA_DEVICE_INDEX = 1
CAMERA_BACKEND = cv2.CAP_DSHOW
PREVIEW_WINDOW_NAME = 'Webcam'
SHOW_PREVIEW = os.environ.get("FACETRACKER_SHOW_PREVIEW", "1") != "0"
MAX_CAMERA_INDEX = 6
CAMERA_READ_WARMUP_FRAMES = 8
CAMERA_VALIDATE_FRAMES = 5
MIN_ACCEPTABLE_CAMERA_FPS = 5.0
PREFERRED_CAMERA_NAME = os.environ.get("FACETRACKER_CAMERA_NAME", "Iriun Webcam")
IRIUN_EXECUTABLE = r"F:\Iriun Webcam\IriunWebcam.exe"
IRIUN_STARTUP_DELAY_SECONDS = 2.5
INFERENCE_WIDTH = 320
INFERENCE_HEIGHT = 240
TARGET_INFERENCE_FPS = 60
INFERENCE_INTERVAL_SECONDS = 1.0 / TARGET_INFERENCE_FPS
HEAD_POSE_AXIS_DEADZONES = {
    "pitch": 2.8,
    "yaw": 1.8,
    "roll": 2.4,
}
HEAD_POSE_AXIS_MAX_STEPS = {
    "pitch": 4.0,
    "yaw": 5.5,
    "roll": 4.5,
}
HEAD_POSE_AXIS_RESPONSES = {
    "pitch": 0.34,
    "yaw": 0.42,
    "roll": 0.36,
}


def parse_int_env(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


PREFERRED_CAMERA_INDEX = parse_int_env("FACETRACKER_CAMERA_INDEX", CAMERA_DEVICE_INDEX)


HEAD_POSE_LANDMARKS = {
    "nose_tip": 1,
    "chin": 152,
    "right_eye_outer": 33,
    "left_eye_outer": 263,
    "mouth_left": 61,
    "mouth_right": 291,
}

MOUTH_METRIC_LANDMARKS = {
    "upper_inner": 13,
    "lower_inner": 14,
    "left_corner": 61,
    "right_corner": 291,
    "left_eye_outer": 33,
    "right_eye_outer": 263,
}

HEAD_POSE_MODEL_POINTS = np.array([
    (0.0, 0.0, 0.0),
    (0.0, -330.0, -65.0),
    (-225.0, 170.0, -135.0),
    (225.0, 170.0, -135.0),
    (-150.0, -150.0, -125.0),
    (150.0, -150.0, -125.0),
], dtype=np.float64)


def rotation_matrix_to_euler_angles(rotation_matrix):
    sy = math.sqrt(rotation_matrix[0, 0] * rotation_matrix[0, 0] + rotation_matrix[1, 0] * rotation_matrix[1, 0])
    singular = sy < 1e-6

    if not singular:
        pitch = math.atan2(rotation_matrix[2, 1], rotation_matrix[2, 2])
        yaw = math.atan2(-rotation_matrix[2, 0], sy)
        roll = math.atan2(rotation_matrix[1, 0], rotation_matrix[0, 0])
    else:
        pitch = math.atan2(-rotation_matrix[1, 2], rotation_matrix[1, 1])
        yaw = math.atan2(-rotation_matrix[2, 0], sy)
        roll = 0

    return tuple(math.degrees(angle) for angle in (pitch, yaw, roll))


def estimate_head_pose(face_landmarks, image_shape):
    if not face_landmarks:
        return None

    image_height, image_width = image_shape[:2]
    image_points = np.array([
        (face_landmarks[HEAD_POSE_LANDMARKS["nose_tip"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["nose_tip"]].y * image_height),
        (face_landmarks[HEAD_POSE_LANDMARKS["chin"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["chin"]].y * image_height),
        (face_landmarks[HEAD_POSE_LANDMARKS["right_eye_outer"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["right_eye_outer"]].y * image_height),
        (face_landmarks[HEAD_POSE_LANDMARKS["left_eye_outer"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["left_eye_outer"]].y * image_height),
        (face_landmarks[HEAD_POSE_LANDMARKS["mouth_left"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["mouth_left"]].y * image_height),
        (face_landmarks[HEAD_POSE_LANDMARKS["mouth_right"]].x * image_width,
         face_landmarks[HEAD_POSE_LANDMARKS["mouth_right"]].y * image_height),
    ], dtype=np.float64)

    focal_length = image_width
    camera_matrix = np.array([
        [focal_length, 0, image_width / 2],
        [0, focal_length, image_height / 2],
        [0, 0, 1],
    ], dtype=np.float64)
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)

    success, rotation_vector, _ = cv2.solvePnP(
        HEAD_POSE_MODEL_POINTS,
        image_points,
        camera_matrix,
        dist_coeffs,
        flags=cv2.SOLVEPNP_ITERATIVE,
    )
    if not success:
        return None

    rotation_matrix, _ = cv2.Rodrigues(rotation_vector)
    pitch, yaw, roll = rotation_matrix_to_euler_angles(rotation_matrix)
    # PnP 模型坐标系 y 轴向上为正，与图像坐标系相反，pitch 需要取反以匹配真实抬头/低头方向
    pitch = -pitch

    left_eye = landmark_point(face_landmarks, HEAD_POSE_LANDMARKS["left_eye_outer"])
    right_eye = landmark_point(face_landmarks, HEAD_POSE_LANDMARKS["right_eye_outer"])
    nose_tip = landmark_point(face_landmarks, HEAD_POSE_LANDMARKS["nose_tip"])
    eye_center = (left_eye + right_eye) * 0.5
    eye_span = float(np.linalg.norm(left_eye - right_eye))

    if eye_span > 1e-6:
        yaw_2d = ((nose_tip[0] - eye_center[0]) / (eye_span * 0.5)) * 34.0
        roll_2d = math.degrees(math.atan2(right_eye[1] - left_eye[1], right_eye[0] - left_eye[0]))
        yaw = yaw * 0.45 + max(-35.0, min(35.0, yaw_2d)) * 0.55
        roll = roll * 0.35 + max(-20.0, min(20.0, roll_2d)) * 0.65

    pitch = max(-28.0, min(28.0, pitch))
    yaw = max(-38.0, min(38.0, yaw))
    roll = max(-22.0, min(22.0, roll))

    return {
        "pitch": float(pitch),
        "yaw": float(yaw),
        "roll": float(roll),
    }


class HeadPoseStabilizer:
    def __init__(self):
        self.pose = None

    def update(self, raw_pose):
        if raw_pose is None:
            return dict(self.pose) if self.pose is not None else None

        if self.pose is None:
            self.pose = {
                "pitch": float(raw_pose.get("pitch", 0.0)),
                "yaw": float(raw_pose.get("yaw", 0.0)),
                "roll": float(raw_pose.get("roll", 0.0)),
            }
            return dict(self.pose)

        stabilized = {}
        for axis in ("pitch", "yaw", "roll"):
            previous = float(self.pose.get(axis, 0.0))
            current = float(raw_pose.get(axis, previous))
            delta = current - previous
            deadzone = HEAD_POSE_AXIS_DEADZONES[axis]

            if abs(delta) <= deadzone:
                stabilized[axis] = previous
                continue

            effective_delta = delta - math.copysign(deadzone, delta)
            max_step = HEAD_POSE_AXIS_MAX_STEPS[axis]
            effective_delta = max(-max_step, min(max_step, effective_delta))
            response = HEAD_POSE_AXIS_RESPONSES[axis]
            stabilized[axis] = previous + effective_delta * response

        self.pose = stabilized
        return dict(self.pose)


def clamp01(value):
    return float(max(0.0, min(1.0, value)))


def landmark_point(face_landmarks, landmark_index):
    landmark = face_landmarks[landmark_index]
    return np.array((landmark.x, landmark.y), dtype=np.float64)


def distance_between(face_landmarks, first, second):
    return float(np.linalg.norm(landmark_point(face_landmarks, first) - landmark_point(face_landmarks, second)))


def estimate_mouth_metrics(face_landmarks):
    if not face_landmarks:
        return None

    eye_distance = distance_between(
        face_landmarks,
        MOUTH_METRIC_LANDMARKS["left_eye_outer"],
        MOUTH_METRIC_LANDMARKS["right_eye_outer"],
    )
    if eye_distance <= 1e-6:
        return None

    mouth_width = distance_between(
        face_landmarks,
        MOUTH_METRIC_LANDMARKS["left_corner"],
        MOUTH_METRIC_LANDMARKS["right_corner"],
    ) / eye_distance
    mouth_height = distance_between(
        face_landmarks,
        MOUTH_METRIC_LANDMARKS["upper_inner"],
        MOUTH_METRIC_LANDMARKS["lower_inner"],
    ) / eye_distance
    mouth_roundness = mouth_height / max(mouth_width, 1e-6)

    return {
        "mouthOpenGeo": clamp01((mouth_height - 0.04) / 0.26),
        "mouthWideGeo": clamp01((mouth_width - 0.42) / 0.34),
        "mouthNarrowGeo": clamp01((0.72 - mouth_width) / 0.22),
        "mouthRoundGeo": clamp01((mouth_roundness - 0.16) / 0.26),
        "mouthCloseGeo": clamp01((0.10 - mouth_height) / 0.08),
    }


def run_powershell(command):
    if os.name != "nt":
        return ""

    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-Command", command],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""

    return (result.stdout or "").strip()


def list_windows_camera_names():
    output = run_powershell(
        "Get-CimInstance Win32_PnPEntity | "
        "Where-Object { $_.PNPClass -eq 'Camera' -or $_.Name -match 'camera|cam|webcam|iriun' } | "
        "Select-Object -ExpandProperty Name | ConvertTo-Json -Compress"
    )
    if not output:
        return []

    try:
        names = json.loads(output)
    except json.JSONDecodeError:
        return []

    if isinstance(names, str):
        return [names]

    return [str(name) for name in names]


def ensure_preferred_camera_ready(camera_names):
    if os.name != "nt":
        return

    preferred_found = any(PREFERRED_CAMERA_NAME.lower() in name.lower() for name in camera_names)
    if preferred_found or not os.path.isfile(IRIUN_EXECUTABLE):
        return

    try:
        subprocess.Popen(
            [IRIUN_EXECUTABLE],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(f"Started preferred camera helper: {IRIUN_EXECUTABLE}")
        time.sleep(IRIUN_STARTUP_DELAY_SECONDS)
    except OSError:
        pass


def get_camera_probe_order(camera_names):
    probe_order = []

    if PREFERRED_CAMERA_INDEX >= 0:
        probe_order.append(PREFERRED_CAMERA_INDEX)

    if any(PREFERRED_CAMERA_NAME.lower() in name.lower() for name in camera_names):
        probe_order.extend([CAMERA_DEVICE_INDEX, 0, 2, 3])

    probe_order.extend(range(MAX_CAMERA_INDEX + 1))

    deduped = []
    seen = set()
    for index in probe_order:
        if index in seen or index < 0:
            continue
        seen.add(index)
        deduped.append(index)

    return deduped


def open_capture_for_index(index):
    backends = [CAMERA_BACKEND, cv2.CAP_ANY]

    for backend in backends:
        cap = cv2.VideoCapture(index, backend)
        if not cap or not cap.isOpened():
            if cap:
                cap.release()
            continue

        configure_capture(cap)

        first_frame = None
        validation_frames = 0
        validation_started = time.perf_counter()
        for _ in range(CAMERA_READ_WARMUP_FRAMES):
            ok, frame = cap.read()
            if ok and frame is not None:
                first_frame = frame
                validation_frames += 1
                if validation_frames >= CAMERA_VALIDATE_FRAMES:
                    break

        if first_frame is None:
            cap.release()
            continue

        validation_elapsed = max(time.perf_counter() - validation_started, 1e-6)
        measured_fps = validation_frames / validation_elapsed
        if measured_fps < MIN_ACCEPTABLE_CAMERA_FPS:
            backend_name = "CAP_DSHOW" if backend == cv2.CAP_DSHOW else str(backend)
            print(
                f"Rejected camera index {index} with backend {backend_name}: "
                f"capture too slow ({measured_fps:.2f} FPS)"
            )
            cap.release()
            continue

        return cap, backend, first_frame

    return None, None, None


def select_capture_device():
    camera_names = list_windows_camera_names()
    if camera_names:
        print("Detected Windows camera devices: " + ", ".join(camera_names))

    ensure_preferred_camera_ready(camera_names)

    for index in get_camera_probe_order(camera_names):
        cap, backend, first_frame = open_capture_for_index(index)
        if cap is not None:
            backend_name = "CAP_DSHOW" if backend == cv2.CAP_DSHOW else str(backend)
            print(f"Using camera index {index} with backend {backend_name}")
            return cap, index, first_frame

    raise RuntimeError("Could not open any camera device")


def prepare_inference_frame(frame):
    inference_frame = cv2.resize(frame, (INFERENCE_WIDTH, INFERENCE_HEIGHT), interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(inference_frame, cv2.COLOR_BGR2RGB)


def configure_capture(cap):
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, TARGET_CAMERA_FPS)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)


def annotate_preview(frame, camera_fps, inference_fps, head_pose, camera_index):
    cv2.putText(
        frame,
        f"Camera {camera_index}  Cam FPS: {camera_fps:.1f}  Infer FPS: {inference_fps:.1f}",
        (10, 24),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (0, 255, 0),
        2,
        cv2.LINE_AA,
    )

    if head_pose:
        cv2.putText(
            frame,
            f"Pitch {head_pose['pitch']:+.1f}  Yaw {head_pose['yaw']:+.1f}  Roll {head_pose['roll']:+.1f}",
            (10, 50),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 220, 255),
            2,
            cv2.LINE_AA,
        )

    return frame


class FaceTracker:
    def __init__(self):
        self.result = None
        self.landmarker = FaceLandmarker
        self.pending = False
        self.result_version = 0
        self.last_submit_time = 0.0
        self.inference_fps = 0.0
        self.inference_frames = 0
        self.inference_window_started = time.perf_counter()
        self.build()

    def build(self):
        def update_result(result, output_image: mp.Image, timestamp_ms: int):
            self.result = result
            self.pending = False
            self.result_version += 1
            self.inference_frames += 1

            now = time.perf_counter()
            elapsed = now - self.inference_window_started
            if elapsed >= 0.5:
                self.inference_fps = self.inference_frames / elapsed
                self.inference_frames = 0
                self.inference_window_started = now

        options = FaceLandmarkerOptions(
            base_options=BaseOptions(
                model_asset_path=MODEL_PATH),
            running_mode=VisionRunningMode.LIVE_STREAM,
            result_callback=update_result,
            num_faces=1,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=False,
        )

        self.landmarker = self.landmarker.create_from_options(options)

    def detect_async(self, frame):
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame)
        self.pending = True
        self.last_submit_time = time.perf_counter()

        self.landmarker.detect_async(
            image=mp_image, timestamp_ms=time.monotonic_ns() // 1_000_000)

    def maybe_detect_async(self, frame):
        now = time.perf_counter()
        if self.pending or (now - self.last_submit_time) < INFERENCE_INTERVAL_SECONDS:
            return False

        self.detect_async(frame)
        return True

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.landmarker.close()
        return True


async def echo(websocket: ServerConnection, data_queue: aioprocessing.AioQueue):
    await websocket.send("Initializing streaming")
    print("Client connected")
    while True:
        try:
            data = await data_queue.coro_get()
            await websocket.send(json.dumps(data))
        except ConnectionClosed:
            print("Client disconnected")
            break
        except Exception as e:
            print(f"Echo exception: {type(e)}: {e.args}")


def capture_face(data_queue: aioprocessing.AioQueue):
    print("Getting video")
    try:
        cap, selected_camera_index, pending_frame = select_capture_device()
    except RuntimeError as exc:
        print(exc)
        return

    camera_fps = 0.0
    camera_frames = 0
    camera_window_started = time.perf_counter()
    latest_payload = None
    latest_blendshapes = None
    latest_head_pose = None
    latest_mouth_metrics = None
    last_processed_result_version = -1
    head_pose_stabilizer = HeadPoseStabilizer()

    with FaceTracker() as t:
        while True:
            if pending_frame is not None:
                image = pending_frame
                pending_frame = None
                ret = True
            else:
                ret, image = cap.read()

            if not ret:
                print("Error: failed to capture frame")
                continue

            inference_frame = prepare_inference_frame(image)
            t.maybe_detect_async(inference_frame)

            try:
                if t.result and t.result_version != last_processed_result_version:
                    last_processed_result_version = t.result_version
                    if t.result.face_blendshapes and t.result.face_blendshapes[0] != []:
                        latest_blendshapes = [category.score for category in t.result.face_blendshapes[0]]
                        latest_head_pose = head_pose_stabilizer.update(
                            estimate_head_pose(t.result.face_landmarks[0], inference_frame.shape)
                        )
                        latest_mouth_metrics = estimate_mouth_metrics(t.result.face_landmarks[0])
            except (IndexError, AttributeError):
                pass
            except Exception as e:
                print(f"Processor exception: {type(e)}: {e.args}")

            if latest_blendshapes is not None:
                latest_payload = {
                    "blendshapes": latest_blendshapes,
                    "head_pose": latest_head_pose,
                    "mouth_metrics": latest_mouth_metrics,
                }
                try:
                    data_queue.put_nowait(latest_payload)
                except queue.Full:
                    try:
                        data_queue.get_nowait()
                    except queue.Empty:
                        pass

                    try:
                        data_queue.put_nowait(latest_payload)
                    except queue.Full:
                        pass

            camera_frames += 1
            now = time.perf_counter()
            elapsed = now - camera_window_started
            if elapsed >= 0.5:
                camera_fps = camera_frames / elapsed
                camera_frames = 0
                camera_window_started = now

            if SHOW_PREVIEW:
                preview_head_pose = latest_payload["head_pose"] if latest_payload else None
                preview = annotate_preview(
                    image,
                    camera_fps,
                    t.inference_fps,
                    preview_head_pose,
                    selected_camera_index,
                )
                cv2.imshow(PREVIEW_WINDOW_NAME, preview)

                if cv2.waitKey(1) & 0xFF == ord('q'):
                    break

        cap.release()
        cv2.destroyAllWindows()


async def main():
    data_queue = aioprocessing.AioQueue(maxsize=1)

    sender = functools.partial(echo, data_queue=data_queue)

    sensor = aioprocessing.AioProcess(
        target=capture_face, args=(data_queue,))
    async with serve(handler=sender, host=SOCKET_HOST, port=SOCKET_PORT) as server:
        sensor.start()
        print(f"Serving at ws://{SOCKET_HOST}:{SOCKET_PORT}")
        await server.serve_forever()

    # sensor.join()


if __name__ == '__main__':
    asyncio.run(main())
