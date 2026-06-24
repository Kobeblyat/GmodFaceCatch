using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace FaceCatchLauncher;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var mutex = new Mutex(true, "FaceCatchLauncher.Singleton", out var first);
        if (!first)
        {
            MessageBox.Show("FaceCatch 启动器已经在运行。", "FaceCatch");
            return;
        }
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private const string AuthorUrl = "https://space.bilibili.com/3546897006463032";
    private const string PythonInstallerUrl =
        "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe";

    // 国内 pip 镜像，显著加速 mediapipe / opencv 等大包下载
    private const string PipIndexUrl = "https://pypi.tuna.tsinghua.edu.cn/simple";
    private const string PipIndexArgs = "-i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn";

    private readonly string _runtimeDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FaceCatch");
    private readonly string _pythonDir;
    private readonly string _venvPython;
    private readonly string _pidFile;

    private readonly TextBox _gmodPath = new();
    private readonly NumericUpDown _cameraIndex = new();
    private readonly CheckBox _preview = new();
    private readonly Label _environmentStatus = new();
    private readonly Label _serviceStatus = new();
    private readonly ProgressBar _progress = new();
    private readonly TextBox _log = new();
    private readonly Button _installButton = new();
    private readonly Button _startButton = new();
    private readonly Button _startGameButton = new();
    private readonly Button _stopButton = new();
    private readonly Button _browseButton = new();
    private readonly System.Windows.Forms.Timer _statusTimer = new();
    private Process? _serverProcess;
    private IntPtr _jobHandle = IntPtr.Zero;
    private bool _busy;

    public MainForm()
    {
        _pythonDir = Path.Combine(_runtimeDir, "Python312");
        _venvPython = Path.Combine(_runtimeDir, ".venv", "Scripts", "python.exe");
        _pidFile = Path.Combine(_runtimeDir, "facecatch.pid");

        Text = "FaceCatch 面部捕捉";
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        Width = 760;
        Height = 590;
        MinimumSize = new Size(680, 520);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 9F);

        BuildUi();
        _gmodPath.Text = FindGModPath() ?? "";
        _statusTimer.Interval = 1000;
        _statusTimer.Tick += (_, _) => RefreshStatus();
        _statusTimer.Start();
        Shown += async (_, _) => await DetectAsync();
    }

    private void BuildUi()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(14),
            ColumnCount = 1,
            RowCount = 8,
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(root);

        var title = new Label
        {
            AutoSize = true,
            Text = "FaceCatch",
            Font = new Font("Microsoft YaHei UI", 20F, FontStyle.Bold),
            Margin = new Padding(0, 0, 0, 8),
        };
        root.Controls.Add(title);

        var credit = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 10),
        };
        credit.Controls.Add(new Label
        {
            Text = "创作：",
            AutoSize = true,
            Margin = new Padding(0, 2, 0, 0),
        });
        var authorLink = new LinkLabel
        {
            Text = "Kobeblyat · Bilibili",
            AutoSize = true,
        };
        authorLink.LinkClicked += (_, _) =>
        {
            Process.Start(new ProcessStartInfo(AuthorUrl) { UseShellExecute = true });
        };
        credit.Controls.Add(authorLink);
        root.Controls.Add(credit);

        var pathRow = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 3,
            Margin = new Padding(0, 0, 0, 8),
        };
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        pathRow.Controls.Add(new Label { Text = "GMod 目录：", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        _gmodPath.Dock = DockStyle.Fill;
        pathRow.Controls.Add(_gmodPath, 1, 0);
        _browseButton.Text = "浏览";
        _browseButton.AutoSize = true;
        _browseButton.Click += (_, _) => BrowseGMod();
        pathRow.Controls.Add(_browseButton, 2, 0);
        root.Controls.Add(pathRow);

        var options = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 8),
        };
        options.Controls.Add(new Label { Text = "摄像头编号：", AutoSize = true, Margin = new Padding(0, 6, 2, 0) });
        _cameraIndex.Minimum = 0;
        _cameraIndex.Maximum = 10;
        _cameraIndex.Width = 55;
        options.Controls.Add(_cameraIndex);
        _preview.Text = "显示摄像头预览";
        _preview.Checked = true;
        _preview.AutoSize = true;
        _preview.Margin = new Padding(18, 5, 0, 0);
        options.Controls.Add(_preview);
        root.Controls.Add(options);

        var statusPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2,
            Margin = new Padding(0, 0, 0, 8),
        };
        statusPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        statusPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        _environmentStatus.Text = "环境：正在检测…";
        _environmentStatus.AutoSize = true;
        _serviceStatus.Text = "服务：正在检测…";
        _serviceStatus.AutoSize = true;
        statusPanel.Controls.Add(_environmentStatus, 0, 0);
        statusPanel.Controls.Add(_serviceStatus, 1, 0);
        root.Controls.Add(statusPanel);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            WrapContents = false,
            Margin = new Padding(0, 0, 0, 8),
        };
        ConfigureButton(_installButton, "一键安装 / 修复", async () => await InstallAsync());
        ConfigureButton(_startButton, "启动面捕", async () => await StartAsync());
        ConfigureButton(_startGameButton, "启动面捕 + GMod", async () => await StartFaceCatchAndGameAsync());
        ConfigureButton(_stopButton, "停止面捕", async () => await StopAsync());
        buttons.Controls.AddRange([_installButton, _startButton, _startGameButton, _stopButton]);
        root.Controls.Add(buttons);

        _progress.Dock = DockStyle.Top;
        _progress.Style = ProgressBarStyle.Continuous;
        _progress.Height = 8;
        _progress.Margin = new Padding(0, 0, 0, 8);
        root.Controls.Add(_progress);

        _log.Dock = DockStyle.Fill;
        _log.Multiline = true;
        _log.ReadOnly = true;
        _log.ScrollBars = ScrollBars.Vertical;
        _log.BackColor = Color.FromArgb(25, 25, 25);
        _log.ForeColor = Color.Gainsboro;
        _log.Font = new Font("Consolas", 9F);
        root.Controls.Add(_log);
    }

    private static void ConfigureButton(Button button, string text, Func<Task> action)
    {
        button.Text = text;
        button.AutoSize = true;
        button.Padding = new Padding(8, 3, 8, 3);
        button.Click += async (_, _) => await action();
    }

    private void BrowseGMod()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "选择 GarrysMod 根目录（其中应包含 garrysmod 文件夹）",
            UseDescriptionForTitle = true,
            SelectedPath = _gmodPath.Text,
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _gmodPath.Text = dialog.SelectedPath;
    }

    private async Task DetectAsync()
    {
        if (_busy) return;
        await Task.Run(() =>
        {
            var pythonOk = File.Exists(_venvPython);
            var modelOk = File.Exists(Path.Combine(_runtimeDir, "face_landmarker.task"));
            var scriptOk = File.Exists(Path.Combine(_runtimeDir, "gmod_facetracker.py"));
            var gmodOk = IsGModPath(_gmodPath.Text);
            BeginInvoke(() =>
            {
                _environmentStatus.Text = pythonOk && modelOk && scriptOk && gmodOk
                    ? "环境：✓ 已安装"
                    : "环境：需要安装或修复";
                RefreshStatus();
            });
        });
    }

    private async Task InstallAsync()
    {
        if (!TryBeginBusy()) return;
        try
        {
            if (!IsVCRuntimeInstalled())
            {
                Log("警告：未检测到 Visual C++ 运行时，MediaPipe 可能会崩溃。");
                if (MessageBox.Show(this,
                    "未检测到 Visual C++ 2015-2022 运行时库，MediaPipe 和 OpenCV 依赖它运行。\n" +
                    "缺少它会导致程序启动即崩溃（快速异常检测失效）。\n\n" +
                    "是否现在打开下载页面？",
                    "缺少 VC++ 运行时",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Warning) == DialogResult.Yes)
                {
                    Process.Start(new ProcessStartInfo("https://aka.ms/vs/17/release/vc_redist.x64.exe")
                    { UseShellExecute = true });
                }
            }

            Log("开始检测和安装环境…");
            SetProgress(3);
            Directory.CreateDirectory(_runtimeDir);
            ExtractRuntimeAssets();
            SetProgress(12);

            var basePython = FindPython312();
            if (basePython == null)
            {
                Log("未找到内置 Python 3.12，正在下载安装（仅当前用户）…");
                var installer = Path.Combine(_runtimeDir, "python-3.12.10-amd64.exe");
                await DownloadAsync(PythonInstallerUrl, installer, 12, 38);
                var args =
                    $"/quiet InstallAllUsers=0 PrependPath=0 Include_test=0 Include_launcher=0 " +
                    $"Include_pip=1 TargetDir=\"{_pythonDir}\"";
                await RunProcessAsync(installer, args, _runtimeDir);
                basePython = FindPython312();
                if (basePython == null)
                    throw new InvalidOperationException("Python 3.12 安装失败。");
            }
            else
            {
                Log($"✓ 找到 Python 3.12：{basePython}");
            }

            SetProgress(42);
            if (!File.Exists(_venvPython))
            {
                Log("正在创建独立运行环境…");
                await RunProcessAsync(
                    basePython,
                    $"-m venv \"{Path.Combine(_runtimeDir, ".venv")}\"",
                    _runtimeDir);
            }

            SetProgress(50);
            Log("正在安装/检查面捕依赖，首次执行可能需要几分钟…");
            await RunProcessAsync(_venvPython, $"-m pip install --disable-pip-version-check --upgrade pip {PipIndexArgs}", _runtimeDir);
            await RunProcessAsync(
                _venvPython,
                $"-m pip install --disable-pip-version-check {PipIndexArgs} -r \"{Path.Combine(_runtimeDir, "requirements.txt")}\"",
                _runtimeDir);

            Log("正在锁定 numpy 1.x 以避免 MediaPipe 原生层崩溃…");
            await RunProcessAsync(
                _venvPython,
                $"-m pip install --disable-pip-version-check --force-reinstall --no-deps {PipIndexArgs} \"numpy==1.26.4\"",
                _runtimeDir);
            SetProgress(82);

            Log("正在验证 MediaPipe 和模型…");
            await RunProcessAsync(
                _venvPython,
                "-c \"import mediapipe,cv2,numpy,websockets,aioprocessing; print('FaceCatch dependencies OK')\"",
                _runtimeDir);

            InstallGModAddon();
            SetProgress(100);
            Log("✓ 安装与修复完成");
            _environmentStatus.Text = "环境：✓ 已安装";
        }
        catch (Exception ex)
        {
            Log("安装失败：" + ex.Message);
            MessageBox.Show(this, ex.Message, "FaceCatch 安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            EndBusy();
        }
    }

    private async Task StartAsync()
    {
        if (!TryBeginBusy()) return;
        try
        {
            if (!File.Exists(_venvPython) ||
                !File.Exists(Path.Combine(_runtimeDir, "gmod_facetracker.py")))
            {
                Log("环境未安装，先执行一键安装。");
                EndBusy();
                await InstallAsync();
                if (!File.Exists(_venvPython)) return;
                if (!TryBeginBusy()) return;
            }

            ExtractRuntimeAssets();
            InstallGModAddon();

            if (IsPortListening(8667))
            {
                Log("FaceCatch 已经在 ws://127.0.0.1:8667 运行。");
                return;
            }

            var info = new ProcessStartInfo
            {
                FileName = _venvPython,
                Arguments = "-u gmod_facetracker.py",
                WorkingDirectory = _runtimeDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            info.Environment["FACETRACKER_CAMERA_INDEX"] = ((int)_cameraIndex.Value).ToString();
            info.Environment["FACETRACKER_SHOW_PREVIEW"] = _preview.Checked ? "1" : "0";

            _serverProcess = new Process { StartInfo = info, EnableRaisingEvents = true };
            _serverProcess.OutputDataReceived += (_, e) => { if (e.Data != null) Log(e.Data); };
            _serverProcess.ErrorDataReceived += (_, e) => { if (e.Data != null) Log(e.Data); };
            _serverProcess.Exited += (_, _) =>
            {
                Log("FaceCatch 服务已退出。");
                ReleaseJob();
                try { File.Delete(_pidFile); } catch { }
            };
            if (!_serverProcess.Start()) throw new InvalidOperationException("无法启动 Python 服务。");
            AttachProcessTreeToJob(_serverProcess);
            File.WriteAllText(_pidFile, _serverProcess.Id.ToString());
            _serverProcess.BeginOutputReadLine();
            _serverProcess.BeginErrorReadLine();

            Log($"✓ 已启动 FaceCatch（PID {_serverProcess.Id}）");
            await WaitForPortAsync(8667, TimeSpan.FromSeconds(12));
            if (!IsPortListening(8667))
                throw new InvalidOperationException("服务启动后未能监听 8667 端口，请查看日志。");
        }
        catch (Exception ex)
        {
            Log("启动失败：" + ex.Message);
            MessageBox.Show(this, ex.Message, "FaceCatch 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            EndBusy();
            RefreshStatus();
        }
    }

    private async Task StartFaceCatchAndGameAsync()
    {
        await StartAsync();
        if (!IsPortListening(8667)) return;

        try
        {
            InstallGModAddon();

            var gmodRoot = _gmodPath.Text.Trim();
            var running = Process.GetProcessesByName("gmod").Any();
            if (running)
            {
                Log("GMod 已经在运行；FaceCatch 插件将在下次载入地图或重启游戏后更新。");
                return;
            }

            var win64Exe = Path.Combine(gmodRoot, "bin", "win64", "gmod.exe");
            var launcherExe = Path.Combine(gmodRoot, "gmod.exe");
            var executable = File.Exists(win64Exe) ? win64Exe : launcherExe;
            if (!File.Exists(executable))
                throw new FileNotFoundException("未找到 GMod 启动程序。", executable);

            Process.Start(new ProcessStartInfo
            {
                FileName = executable,
                WorkingDirectory = gmodRoot,
                UseShellExecute = true,
            });
            Log("✓ GMod 已启动");
        }
        catch (Exception ex)
        {
            Log("启动 GMod 失败：" + ex.Message);
            MessageBox.Show(this, ex.Message, "无法启动 GMod", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task StopAsync()
    {
        if (!TryBeginBusy()) return;
        try
        {
            var stopped = false;
            if (_jobHandle != IntPtr.Zero)
            {
                NativeMethods.TerminateJobObject(_jobHandle, 0);
                ReleaseJob();
                stopped = true;
            }

            if (_serverProcess is { HasExited: false })
            {
                _serverProcess.Kill(true);
                await _serverProcess.WaitForExitAsync();
                stopped = true;
            }

            if (!stopped && File.Exists(_pidFile) &&
                int.TryParse(File.ReadAllText(_pidFile).Trim(), out var pid))
            {
                try
                {
                    var process = Process.GetProcessById(pid);
                    process.Kill(true);
                    await process.WaitForExitAsync();
                    stopped = true;
                }
                catch { }
            }

            if (!stopped && IsPortListening(8667))
                stopped = await StopVerifiedPortOwnerAsync();

            try { File.Delete(_pidFile); } catch { }
            Log(stopped ? "✓ FaceCatch 已停止" : "FaceCatch 当前没有由本启动器管理的运行进程。");
        }
        catch (Exception ex)
        {
            Log("停止失败：" + ex.Message);
        }
        finally
        {
            EndBusy();
            RefreshStatus();
        }
    }

    private async Task<bool> StopVerifiedPortOwnerAsync()
    {
        var script =
            "$c=Get-NetTCPConnection -LocalPort 8667 -State Listen -ErrorAction SilentlyContinue;" +
            "if($c){$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$c.OwningProcess);" +
            "if($p.CommandLine -like '*gmod_facetracker.py*'){Write-Output $c.OwningProcess}}";
        var output = await CaptureProcessAsync(
            "powershell",
            $"-NoProfile -ExecutionPolicy Bypass -Command \"{script}\"",
            _runtimeDir);
        if (!int.TryParse(output.Trim(), out var pid)) return false;
        try
        {
            var process = Process.GetProcessById(pid);
            process.Kill(true);
            await process.WaitForExitAsync();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void ExtractRuntimeAssets()
    {
        Directory.CreateDirectory(_runtimeDir);
        ExtractResource("Assets.gmod_facetracker.py", Path.Combine(_runtimeDir, "gmod_facetracker.py"));
        ExtractResource("Assets.face_landmarker.task", Path.Combine(_runtimeDir, "face_landmarker.task"));
        File.WriteAllText(
            Path.Combine(_runtimeDir, "requirements.txt"),
            "aioprocessing==2.0.1\nmediapipe==0.10.35\nnumpy==1.26.4\nopencv-python>=4.10\nwebsockets==16.0\n",
            new UTF8Encoding(false));
    }

    private void InstallGModAddon()
    {
        var root = _gmodPath.Text.Trim();
        if (!IsGModPath(root))
            throw new DirectoryNotFoundException("未找到有效的 GarrysMod 目录，请在顶部选择正确路径。");

        var addon = Path.Combine(root, "garrysmod", "addons", "facecatch");
        var luaBin = Path.Combine(root, "garrysmod", "lua", "bin");
        Directory.CreateDirectory(Path.Combine(addon, "lua", "autorun", "client"));
        Directory.CreateDirectory(Path.Combine(addon, "lua", "autorun", "server"));
        Directory.CreateDirectory(Path.Combine(addon, "lua", "weapons", "gmod_tool", "stools"));
        Directory.CreateDirectory(luaBin);
        ExtractResource("Assets.addon.json", Path.Combine(addon, "addon.json"));
        ExtractResource("Assets.addon_readme.txt", Path.Combine(addon, "README.txt"));
        ExtractResource("Assets.facecatch.lua", Path.Combine(addon, "lua", "autorun", "client", "facecatch.lua"));
        ExtractResource("Assets.facecatch_sv.lua", Path.Combine(addon, "lua", "autorun", "server", "facecatch_sv.lua"));
        ExtractResource("Assets.facecatch_tool.lua", Path.Combine(addon, "lua", "weapons", "gmod_tool", "stools", "facecatch.lua"));
        ExtractResource("Assets.gmcl_gwsockets_win32.dll", Path.Combine(luaBin, "gmcl_gwsockets_win32.dll"));
        ExtractResource("Assets.gmcl_gwsockets_win64.dll", Path.Combine(luaBin, "gmcl_gwsockets_win64.dll"));
        Log("✓ GMod 插件和 32/64 位 GWSockets 已安装");
    }

    private static void ExtractResource(string resourceName, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        using var input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"启动器资源缺失：{resourceName}");
        using var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
        input.CopyTo(output);
    }

    private async Task DownloadAsync(string url, string destination, int startProgress, int endProgress)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;
        await using var input = await response.Content.ReadAsStreamAsync();
        await using var output = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);
        var buffer = new byte[81920];
        long readTotal = 0;
        int read;
        while ((read = await input.ReadAsync(buffer)) > 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, read));
            readTotal += read;
            if (total > 0)
            {
                var fraction = (double)readTotal / total.Value;
                SetProgress(startProgress + (int)((endProgress - startProgress) * fraction));
            }
        }
    }

    private async Task RunProcessAsync(string file, string arguments, string workingDirectory)
    {
        var result = await RunProcessCoreAsync(file, arguments, workingDirectory, captureOnly: false);
        if (result.ExitCode != 0)
            throw new InvalidOperationException($"{Path.GetFileName(file)} 执行失败，退出码 {result.ExitCode}");
    }

    private async Task<string> CaptureProcessAsync(string file, string arguments, string workingDirectory)
    {
        var result = await RunProcessCoreAsync(file, arguments, workingDirectory, captureOnly: true);
        return result.Output;
    }

    private async Task<(int ExitCode, string Output)> RunProcessCoreAsync(
        string file, string arguments, string workingDirectory, bool captureOnly)
    {
        var output = new StringBuilder();
        var info = new ProcessStartInfo
        {
            FileName = file,
            Arguments = arguments,
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        using var process = new Process { StartInfo = info };
        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            output.AppendLine(e.Data);
            if (!captureOnly) Log(e.Data);
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data == null) return;
            output.AppendLine(e.Data);
            if (!captureOnly) Log(e.Data);
        };
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();
        return (process.ExitCode, output.ToString());
    }

    private async Task WaitForPortAsync(int port, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (IsPortListening(port)) return;
            await Task.Delay(250);
        }
    }

    private static bool IsPortListening(int port) =>
        IPGlobalProperties.GetIPGlobalProperties()
            .GetActiveTcpListeners()
            .Any(endpoint => endpoint.Port == port && IPAddress.IsLoopback(endpoint.Address));

    private void RefreshStatus()
    {
        if (IsDisposed) return;
        var running = IsPortListening(8667);
        _serviceStatus.Text = running
            ? "服务：● 正在运行（127.0.0.1:8667）"
            : "服务：○ 已停止";
        _serviceStatus.ForeColor = running ? Color.ForestGreen : SystemColors.ControlText;
        _startButton.Enabled = !_busy && !running;
        _stopButton.Enabled = !_busy && running;
    }

    private void AttachProcessTreeToJob(Process process)
    {
        ReleaseJob();
        var job = NativeMethods.CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero)
            throw new InvalidOperationException("无法创建 FaceCatch 进程组。");

        var info = new NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = NativeMethods.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        var length = Marshal.SizeOf<NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
        var pointer = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, pointer, false);
            if (!NativeMethods.SetInformationJobObject(
                    job,
                    NativeMethods.JobObjectExtendedLimitInformation,
                    pointer,
                    (uint)length))
                throw new InvalidOperationException("无法配置 FaceCatch 进程组。");

            if (!NativeMethods.AssignProcessToJobObject(job, process.Handle))
                throw new InvalidOperationException("无法绑定 FaceCatch 子进程。");

            _jobHandle = job;
            job = IntPtr.Zero;
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
            if (job != IntPtr.Zero) NativeMethods.CloseHandle(job);
        }
    }

    private void ReleaseJob()
    {
        var job = Interlocked.Exchange(ref _jobHandle, IntPtr.Zero);
        if (job != IntPtr.Zero) NativeMethods.CloseHandle(job);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        ReleaseJob();
        base.OnFormClosed(e);
    }

    private bool TryBeginBusy()
    {
        if (_busy) return false;
        _busy = true;
        _installButton.Enabled = false;
        _startButton.Enabled = false;
        _startGameButton.Enabled = false;
        _stopButton.Enabled = false;
        _browseButton.Enabled = false;
        UseWaitCursor = true;
        return true;
    }

    private void EndBusy()
    {
        _busy = false;
        _installButton.Enabled = true;
        _startGameButton.Enabled = true;
        _browseButton.Enabled = true;
        UseWaitCursor = false;
        RefreshStatus();
    }

    private void SetProgress(int value)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => SetProgress(value));
            return;
        }
        _progress.Value = Math.Clamp(value, 0, 100);
    }

    private void Log(string text)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => Log(text));
            return;
        }
        _log.AppendText($"[{DateTime.Now:HH:mm:ss}] {text}{Environment.NewLine}");
        _log.SelectionStart = _log.TextLength;
        _log.ScrollToCaret();
    }

    private static bool IsGModPath(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        Directory.Exists(Path.Combine(path, "garrysmod")) &&
        (File.Exists(Path.Combine(path, "gmod.exe")) ||
         File.Exists(Path.Combine(path, "bin", "win64", "gmod.exe")));

    private string? FindPython312()
    {
        var candidates = new List<string>
        {
            Path.Combine(_pythonDir, "python.exe"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "Python", "Python312", "python.exe"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "Python312", "python.exe"),
        };

        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            try
            {
                using var key = hive.OpenSubKey(@"Software\Python\PythonCore\3.12\InstallPath");
                var root = key?.GetValue(null)?.ToString();
                if (!string.IsNullOrWhiteSpace(root))
                    candidates.Add(Path.Combine(root, "python.exe"));
            }
            catch { }
        }

        return candidates.FirstOrDefault(File.Exists);
    }

    private static bool IsVCRuntimeInstalled()
    {
        var systemDir = Environment.GetFolderPath(Environment.SpecialFolder.System);
        return File.Exists(Path.Combine(systemDir, "vcruntime140.dll")) &&
               File.Exists(Path.Combine(systemDir, "vcruntime140_1.dll"));
    }

    private static string? FindGModPath()
    {
        var candidates = new List<string>();
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
            var steam = key?.GetValue("SteamPath")?.ToString()?.Replace('/', Path.DirectorySeparatorChar);
            if (!string.IsNullOrWhiteSpace(steam))
                candidates.Add(Path.Combine(steam, "steamapps", "common", "GarrysMod"));
        }
        catch { }

        foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady))
        {
            candidates.Add(Path.Combine(drive.RootDirectory.FullName, "steam", "steamapps", "common", "GarrysMod"));
            candidates.Add(Path.Combine(drive.RootDirectory.FullName, "SteamLibrary", "steamapps", "common", "GarrysMod"));
            candidates.Add(Path.Combine(drive.RootDirectory.FullName, "Program Files (x86)", "Steam", "steamapps", "common", "GarrysMod"));
        }
        return candidates.FirstOrDefault(IsGModPath);
    }
}

internal static class NativeMethods
{
    internal const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
    internal const int JobObjectExtendedLimitInformation = 9;

    [StructLayout(LayoutKind.Sequential)]
    internal struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr CreateJobObject(IntPtr jobAttributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetInformationJobObject(
        IntPtr job,
        int infoClass,
        IntPtr info,
        uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TerminateJobObject(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(IntPtr handle);
}
