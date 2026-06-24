# FaceCatch — Garry's Mod Face Tracker / 面部捕捉

[English](#english) | [中文](#中文)

---

<a id="english"></a>

## English

Real-time facial capture for Garry's Mod, powered by Google MediaPipe Face Landmarker. Capture your webcam, run face detection, and stream blendshapes, head pose, and mouth shape data to Garry's Mod over a local WebSocket.

### Features

- **Local WebSocket server** — listens on `ws://127.0.0.1:8667`, zero network exposure
- **MediaPipe Face Landmarker** — 52 blendshapes, head pose (pitch/yaw/roll via solvePnP), and AIUEO mouth geometry
- **Tomorin / MMD model support** — optimized viseme mapping for Japanese-style models
- **Multiplayer** — other players can see your facial expressions in real time
- **Toolgun** — drive NPCs, ragdolls, or any model entity with your face
- **Auto camera detection** — probes DirectShow devices, prefers Iriun Webcam
- **One-click launcher** — a Windows GUI that installs Python, dependencies, the model, and the GMod addon automatically

### Two Ways to Use / 两种使用方式

#### Option A: One-Click Launcher (Recommended)

Download `FaceCatch.exe` from the [Releases](../../releases) page and run it. The launcher will:

1. Download and install Python 3.12 (if missing)
2. Create an isolated virtual environment
3. Install all Python dependencies (using a China mirror for speed)
4. Install the GMod addon and GWSockets DLLs
5. Let you start face tracking and GMod with one click

> **Note:** If you get a "fast fail exception" crash, install the [Visual C++ 2015-2022 Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) and click "Repair" in the launcher.

#### Option B: Manual Setup

1. Install [Python 3.12](https://www.python.org/downloads/release/python-3120/)

2. Create and activate a virtual environment:

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   ```

3. Install dependencies:

   ```powershell
   pip install -r requirements.txt
   ```

4. Download the [MediaPipe Face Landmarker model](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task) and place it as `face_landmarker.task` in the same folder as `gmod_facetracker.py`

5. Run:

   ```powershell
   .\start_facecatch.ps1
   ```

   Or directly:

   ```powershell
   .\.venv\Scripts\python.exe -u .\gmod_facetracker.py
   ```

### GMod Addon Installation

If you used the launcher, the addon is installed automatically. For manual installation, copy the `gmod_addon/facecatch` folder to:

```
<GarrysMod>/garrysmod/addons/facecatch
```

You also need the [GWSockets](https://github.com/Facepunch/garrysmod/tree/master/garrysmod/lua/bin) module (`gmcl_gwsockets_win64.dll`) in `<GarrysMod>/garrysmod/lua/bin/`. The launcher ships with 32-bit and 64-bit versions.

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `FACETRACKER_SHOW_PREVIEW` | `1` | Show OpenCV preview window. Set to `0` to disable |
| `FACETRACKER_CAMERA_NAME` | `Iriun Webcam` | Preferred camera device name |
| `FACETRACKER_CAMERA_INDEX` | `1` | Preferred camera index |

### Data Format

Each frame is a JSON object:

```json
{
  "blendshapes": [0.0, 0.12, 0.87, "..."],
  "head_pose": { "pitch": -3.5, "yaw": 8.1, "roll": 1.2 },
  "mouth_metrics": {
    "mouthOpenGeo": 0.42,
    "mouthWideGeo": 0.36,
    "mouthNarrowGeo": 0.14,
    "mouthRoundGeo": 0.28,
    "mouthCloseGeo": 0.09
  }
}
```

### Troubleshooting

<details>
<summary><b>Crash: "Fast fail exception" / process terminates immediately</b></summary>

This is caused by a numpy 2.x ABI incompatibility with MediaPipe's native extensions. The launcher now pins `numpy==1.26.4` and force-reinstalls it. If you set up manually, make sure your `requirements.txt` has `numpy==1.26.4`. Also install the [VC++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe).
</details>

<details>
<summary><b>"Could not open any camera device"</b></summary>

- Make sure your webcam is plugged in / Iriun is running
- Set `$env:FACETRACKER_CAMERA_INDEX = "0"` and retry
- Close other apps using the camera (Zoom, Discord, Camera app)
</details>

<details>
<summary><b>GMod can't connect to the server</b></summary>

- Verify the Python server printed `Serving at ws://127.0.0.1:8667`
- Check that GWSockets DLL is installed in `garrysmod/lua/bin/`
- Make sure the Lua client connects to `ws://127.0.0.1:8667`
</details>

<details>
<summary><b>Head nodding is inverted</b></summary>

This has been fixed in the latest version. If you still see inverted pitch, run "Repair" in the launcher to update the script, or set `facecatch_head_pitch_scale -1` in the GMod console.
</details>

### Building the Launcher

The launcher is a .NET 9 Windows Forms app:

```powershell
cd launcher\FaceCatchLauncher
dotnet publish -c Release
```

The output is a self-contained single-file `FaceCatch.exe` (~53 MB). You need to place `gmcl_gwsockets_win32.dll` and `gmcl_gwsockets_win64.dll` in `launcher/FaceCatchLauncher/Assets/` before building — these are not included in the repo.

### Project Structure

```
facecatch/
├── gmod_facetracker.py      # Python face tracking server
├── requirements.txt         # Python dependencies (numpy pinned to 1.26.4)
├── start_facecatch.ps1      # PowerShell launch script
├── face_landmarker.task     # Model file (download separately)
├── gmod_addon/facecatch/    # Garry's Mod Lua addon
│   └── lua/
│       ├── autorun/client/  # Client-side tracking & rendering
│       ├── autorun/server/  # Multiplayer relay
│       └── weapons/.../     # Toolgun stool
└── launcher/                # C# WinForms one-click installer
    └── FaceCatchLauncher/
        ├── Program.cs       # Launcher source
        └── FaceCatchLauncher.csproj
```

### Credits

Created by **Kobeblyat** — [Bilibili](https://space.bilibili.com/3546897006463032)

- [MediaPipe](https://developers.google.com/mediapipe) by Google — face landmark detection
- [OpenCV](https://opencv.org/) — camera capture and image processing
- [GWSockets](https://github.com/Facepunch/garrysmod) — WebSocket module for GMod

### License

MIT — see [LICENSE](LICENSE).

---

<a id="中文"></a>

## 中文

给 Garry's Mod 用的实时面部捕捉工具，基于 Google MediaPipe Face Landmarker。读取摄像头画面，做人脸检测，把 blendshapes、头部姿态和嘴型数据通过本地 WebSocket 推送给 GMod 客户端。

### 功能

- **本地 WebSocket 服务** — 监听 `ws://127.0.0.1:8667`，不对外暴露网络
- **MediaPipe Face Landmarker** — 52 个 blendshapes、头部姿态（pitch/yaw/roll，基于 solvePnP）、AIUEO 嘴型几何
- **Tomorin / MMD 模型支持** — 针对日式模型优化了 viseme 映射
- **多人联机** — 其他玩家可以实时看到你的面部表情
- **工具枪** — 用你的脸驱动 NPC、布娃娃或任意模型实体
- **摄像头自动检测** — 自动探测 DirectShow 设备，优先使用 Iriun Webcam
- **一键启动器** — Windows GUI 程序，自动安装 Python、依赖、模型和 GMod 插件

### 两种使用方式

#### 方式一：一键启动器（推荐）

从 [Releases](../../releases) 页面下载 `FaceCatch.exe` 直接运行。启动器会自动：

1. 下载安装 Python 3.12（如果没有）
2. 创建独立虚拟环境
3. 安装所有 Python 依赖（使用国内镜像加速）
4. 安装 GMod 插件和 GWSockets DLL
5. 一键启动面捕和 GMod

> **提示：** 如果遇到"快速异常检测失效"崩溃，安装 [Visual C++ 2015-2022 运行时库](https://aka.ms/vs/17/release/vc_redist.x64.exe)，然后在启动器里点"一键安装 / 修复"。

#### 方式二：手动安装

1. 安装 [Python 3.12](https://www.python.org/downloads/release/python-3120/)

2. 创建并激活虚拟环境：

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   ```

3. 安装依赖：

   ```powershell
   pip install -r requirements.txt
   ```

4. 下载 [MediaPipe Face Landmarker 模型](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task)，命名为 `face_landmarker.task`，放到 `gmod_facetracker.py` 同目录

5. 运行：

   ```powershell
   .\start_facecatch.ps1
   ```

   或直接：

   ```powershell
   .\.venv\Scripts\python.exe -u .\gmod_facetracker.py
   ```

### GMod 插件安装

如果用启动器安装，插件会自动装好。手动安装的话，把 `gmod_addon/facecatch` 文件夹复制到：

```
<GarrysMod>/garrysmod/addons/facecatch
```

还需要安装 [GWSockets](https://github.com/Facepunch/garrysmod/tree/master/garrysmod/lua/bin) 模块（`gmcl_gwsockets_win64.dll`）到 `<GarrysMod>/garrysmod/lua/bin/`。启动器自带 32 位和 64 位版本。

### 环境变量

| 变量名 | 默认值 | 说明 |
| --- | --- | --- |
| `FACETRACKER_SHOW_PREVIEW` | `1` | 是否显示 OpenCV 预览窗口，设为 `0` 关闭 |
| `FACETRACKER_CAMERA_NAME` | `Iriun Webcam` | 优先匹配的摄像头设备名 |
| `FACETRACKER_CAMERA_INDEX` | `1` | 优先尝试的摄像头索引 |

### 数据格式

每帧推送一个 JSON 对象：

```json
{
  "blendshapes": [0.0, 0.12, 0.87, "..."],
  "head_pose": { "pitch": -3.5, "yaw": 8.1, "roll": 1.2 },
  "mouth_metrics": {
    "mouthOpenGeo": 0.42,
    "mouthWideGeo": 0.36,
    "mouthNarrowGeo": 0.14,
    "mouthRoundGeo": 0.28,
    "mouthCloseGeo": 0.09
  }
}
```

### 常见问题

<details>
<summary><b>崩溃：提示"快速异常检测失效"或进程立即终止</b></summary>

这是因为 numpy 2.x 与 MediaPipe 原生扩展的 ABI 不兼容。启动器现在已锁定 `numpy==1.26.4` 并强制重装。手动安装的话请确保 `requirements.txt` 里是 `numpy==1.26.4`。同时请安装 [VC++ 运行时库](https://aka.ms/vs/17/release/vc_redist.x64.exe)。
</details>

<details>
<summary><b>提示 "Could not open any camera device"</b></summary>

- 确认摄像头已连接 / Iriun 已启动
- 设置 `$env:FACETRACKER_CAMERA_INDEX = "0"` 重试
- 关闭占用摄像头的软件（Zoom、Discord、相机应用等）
</details>

<details>
<summary><b>GMod 连不上服务</b></summary>

- 确认 Python 服务端已输出 `Serving at ws://127.0.0.1:8667`
- 检查 GWSockets DLL 是否装在 `garrysmod/lua/bin/`
- 确认 Lua 客户端连接的是 `ws://127.0.0.1:8667`
</details>

<details>
<summary><b>上下点头方向反了</b></summary>

最新版已修复。如果还是反的，在启动器里点"修复"更新脚本，或在 GMod 控制台设置 `facecatch_head_pitch_scale -1`。
</details>

### 编译启动器

启动器是 .NET 9 Windows Forms 程序：

```powershell
cd launcher\FaceCatchLauncher
dotnet publish -c Release
```

输出是自包含单文件 `FaceCatch.exe`（约 53 MB）。编译前需要把 `gmcl_gwsockets_win32.dll` 和 `gmcl_gwsockets_win64.dll` 放到 `launcher/FaceCatchLauncher/Assets/` 目录——这两个文件不包含在仓库里。

### 项目结构

```
facecatch/
├── gmod_facetracker.py      # Python 面部追踪服务端
├── requirements.txt         # Python 依赖（numpy 锁定 1.26.4）
├── start_facecatch.ps1      # PowerShell 启动脚本
├── face_landmarker.task     # 模型文件（需单独下载）
├── gmod_addon/facecatch/    # Garry's Mod Lua 插件
│   └── lua/
│       ├── autorun/client/  # 客户端追踪与渲染
│       ├── autorun/server/  # 多人中继
│       └── weapons/.../     # 工具枪
└── launcher/                # C# WinForms 一键安装器
    └── FaceCatchLauncher/
        ├── Program.cs       # 启动器源码
        └── FaceCatchLauncher.csproj
```

### 鸣谢

作者：**Kobeblyat** — [Bilibili](https://space.bilibili.com/3546897006463032)

- [MediaPipe](https://developers.google.com/mediapipe) by Google — 人脸关键点检测
- [OpenCV](https://opencv.org/) — 摄像头采集与图像处理
- [GWSockets](https://github.com/Facepunch/garrysmod) — GMod WebSocket 模块

### 开源协议

MIT — 见 [LICENSE](LICENSE)。
