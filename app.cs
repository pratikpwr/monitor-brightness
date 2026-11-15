// Monitor Brightness - tray app for external monitor brightness over DDC/CI.
// Compiled into MonitorBrightness.exe by install.ps1 with the C# compiler that ships with Windows
// (.NET Framework csc, C# 5: no $"", ?., nameof, => members). Built together with ui.cs and ddc.cs.
//
//   Tray icon : left-click opens the brightness flyout, right-click for presets, auto-start and Exit.
//   Hotkeys   : Ctrl+Alt+B (open/close), Ctrl+Alt+PageUp / PageDown (+/- Step %).
//   Launching it again while it runs just opens the flyout.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Monitor Brightness")]
[assembly: AssemblyProduct("Monitor Brightness")]
[assembly: AssemblyDescription("Control external monitor brightness (DDC/CI)")]
[assembly: AssemblyCompany("pratikpwr")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

static class Program {
    public const string ShowEventName = @"Local\MonitorBrightnessShow";
    public const string ExitEventName = @"Local\MonitorBrightnessExit";   // set by install.ps1 to stop the app
    const string MutexName = @"Local\MonitorBrightnessTray";

    [STAThread]
    static int Main() {
        var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        var exitEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ExitEventName);
        bool createdNew;
        using (var mutex = new Mutex(true, MutexName, out createdNew)) {
            if (!createdNew) {
                // Already running: let it take focus (we were started by the user) and ask it to show the flyout.
                Native.AllowAnyForeground();
                showEvent.Set();
                return 0;
            }
            Native.EnableDpiAwareness();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e) { Log.Write("unhandled: " + e.Exception); };
            AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e) { Log.Write("fatal: " + e.ExceptionObject); };
            try {
                using (new TrayApp(showEvent, exitEvent)) {
                    Log.Write("started " + Assembly.GetExecutingAssembly().GetName().Version);
                    Application.Run();
                }
            } catch (Exception ex) {
                Log.Write("fatal: " + ex);
                return 1;
            } finally {
                mutex.ReleaseMutex();
                Log.Write("stopped");
            }
        }
        return 0;
    }
}

static class Log {
    static readonly string Dir = Path.GetDirectoryName(Application.ExecutablePath);
    static readonly string FilePath = Path.Combine(Dir, "tray.log");
    public static readonly bool Debug = File.Exists(Path.Combine(Dir, "debug.flag"));

    public static void Write(string msg) {
        try {
            var fi = new FileInfo(FilePath);
            if (fi.Exists && fi.Length > 256 * 1024) fi.Delete();   // keep the log small
            File.AppendAllText(FilePath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "  " + msg + Environment.NewLine);
        } catch { }
    }
    public static void Trace(string msg) { if (Debug) Write(msg); }
}

// All external monitors that answer DDC/CI. Re-read on each use so sleep / reconnect never leaves stale handles.
sealed class Monitors : IDisposable {
    List<Ddc.PHYSICAL_MONITOR> all;
    List<IntPtr> handles = new List<IntPtr>();

    public void Refresh() {
        Release();
        all = Ddc.All();
        handles = all.Select(m => m.hPhysicalMonitor).Where(h => Ddc.Get(h) >= 0).ToList();
    }
    public int Get() { return handles.Count > 0 ? Ddc.Get(handles[0]) : -1; }
    public bool Set(int percent) {
        bool ok = false;
        foreach (var h in handles) if (Ddc.Set(h, percent)) ok = true;
        return ok;
    }
    void Release() {
        if (all != null) { try { Ddc.Release(all); } catch { } all = null; }
        handles = new List<IntPtr>();
    }
    public void Dispose() { Release(); }
}

sealed class TrayApp : IDisposable {
    const int Step = 10;                    // Ctrl+Alt+PageUp / PageDown step, in %
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string RunValue = "MonitorBrightness";

    readonly EventWaitHandle showEvent, exitEvent;
    readonly Monitors mon = new Monitors();
    readonly NotifyIcon tray = new NotifyIcon();
    readonly BrightnessFlyout flyout = new BrightnessFlyout();
    readonly HotkeyWindow hk = new HotkeyWindow();
    readonly System.Windows.Forms.Timer applyTimer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer hideTimer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer pollTimer = new System.Windows.Forms.Timer();
    ToolStripMenuItem autoStartItem;
    Icon trayIcon;

    int pending = -1;                       // latest slider value not yet written to the monitor
    int lastSet = -1, lastSetAt;            // last value written, to step from without a slow read-back
    string mode = "";                       // "slider" = opened to use, "osd" = shown briefly by a step hotkey
    int hiddenAt = Environment.TickCount - 10000;   // "long ago", so the first tray click always works

    public TrayApp(EventWaitHandle showEvent, EventWaitHandle exitEvent) {
        this.showEvent = showEvent;
        this.exitEvent = exitEvent;

        // ---- flyout ----
        flyout.MonitorName = GetMonitorName();
        applyTimer.Interval = 120;          // DDC/CI writes are slow: apply the newest slider value on a timer
        applyTimer.Tick += delegate { if (pending >= 0) { int v = pending; pending = -1; SetLevel(v); } else applyTimer.Stop(); };
        flyout.ValueChanged += delegate { pending = flyout.Value; applyTimer.Start(); };

        hideTimer.Interval = 1500;
        hideTimer.Tick += delegate { hideTimer.Stop(); if (!Native.IsForeground(flyout.Handle)) HideFlyout(); };
        flyout.Activated += delegate { if (Native.IsForeground(flyout.Handle)) { hideTimer.Stop(); mode = "slider"; } };
        flyout.Deactivate += delegate { Log.Trace("deactivate"); HideFlyout(); };
        flyout.EscapePressed += delegate { HideFlyout(); };
        flyout.FormClosing += delegate(object s, FormClosingEventArgs e) {
            if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; HideFlyout(); }
        };
        flyout.Prime();

        // ---- tray icon and menu ----
        trayIcon = MakeTrayIcon();
        tray.Icon = trayIcon;
        tray.Text = "Monitor brightness";
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open brightness  (Ctrl+Alt+B)", null, delegate { ShowSlider(); });
        menu.Items.Add(new ToolStripSeparator());
        foreach (int p in BrightnessFlyout.Presets) {
            int preset = p;
            menu.Items.Add(preset + "%", null, delegate {
                mon.Refresh();
                int v = SetLevel(preset);
                flyout.SetValue(v);
            });
        }
        menu.Items.Add(new ToolStripSeparator());
        autoStartItem = new ToolStripMenuItem("Start with Windows", null, delegate { SetAutoStart(!autoStartItem.Checked); });
        menu.Items.Add(autoStartItem);
        menu.Items.Add("Exit", null, delegate { Application.Exit(); });
        menu.Opening += delegate { autoStartItem.Checked = IsAutoStart(); };
        tray.ContextMenuStrip = menu;
        // Pressing on the tray icon already hid the flyout (it lost focus); don't reopen it on mouse-up.
        tray.MouseClick += delegate(object s, MouseEventArgs e) {
            // Unsigned: TickCount goes negative after 24.9 days of uptime and wraps after 49.7.
            if (e.Button == MouseButtons.Left && unchecked((uint)(Environment.TickCount - hiddenAt)) > 400u) ToggleSlider();
        };

        // ---- global hotkeys (NOREPEAT: holding a key would queue slow DDC/CI writes and overshoot) ----
        const uint ALT = 0x1, CTRL = 0x2, NOREPEAT = 0x4000;
        var failed = new List<string>();
        if (!hk.Register(1, CTRL | ALT | NOREPEAT, 0x42)) failed.Add("Ctrl+Alt+B");
        if (!hk.Register(2, CTRL | ALT | NOREPEAT, 0x21)) failed.Add("Ctrl+Alt+PageUp");
        if (!hk.Register(3, CTRL | ALT | NOREPEAT, 0x22)) failed.Add("Ctrl+Alt+PageDown");
        hk.Pressed += delegate(object s, HotkeyArgs e) {
            Log.Trace("hotkey " + e.Id);
            if (e.Id == 1) ToggleSlider();
            else if (e.Id == 2) StepBrightness(Step);
            else if (e.Id == 3) StepBrightness(-Step);
        };

        // ---- second launch -> show flyout; installer -> exit ----
        pollTimer.Interval = 300;
        pollTimer.Tick += delegate {
            if (this.exitEvent.WaitOne(0)) { Application.Exit(); return; }
            if (this.showEvent.WaitOne(0)) ShowSlider();
        };
        pollTimer.Start();

        // Follow light/dark taskbar changes for the tray icon.
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

        try { mon.Refresh(); SetTip(mon.Get()); } catch (Exception ex) { Log.Write("init monitors: " + ex.Message); }
        tray.Visible = true;
        if (failed.Count > 0) {
            string msg = "Another app is already using: " + string.Join(", ", failed);
            Log.Write(msg);
            tray.ShowBalloonTip(5000, "Monitor brightness", msg, ToolTipIcon.Warning);
        }
    }

    // ---------------------------------------------------------------- brightness
    int SetLevel(int v) {
        v = Math.Max(0, Math.Min(100, v));
        if (mon.Set(v)) { lastSet = v; lastSetAt = Environment.TickCount; SetTip(v); }
        return v;
    }

    void SetTip(int v) { tray.Text = v >= 0 ? "Monitor brightness: " + v + "%" : "Monitor brightness (DDC/CI not available)"; }

    void ShowSlider() {
        try {
            hideTimer.Stop();
            mon.Refresh();
            int v = mon.Get();
            if (v < 0) {
                tray.ShowBalloonTip(4000, "Monitor brightness",
                    "No monitor answered DDC/CI. Turn DDC/CI on in the monitor's own menu.", ToolTipIcon.Warning);
                return;
            }
            flyout.SetValue(v);
            SetTip(v);
            mode = "slider";
            flyout.ShowAt(true);
            bool fg = Native.IsForeground(flyout.Handle);
            Log.Trace("show slider, foreground=" + fg);
            // If Windows refused focus, the flyout can't close on "click elsewhere", so close it after a while.
            if (!fg) { hideTimer.Interval = 8000; hideTimer.Start(); }
        } catch (Exception ex) { Log.Write("show: " + ex); }
    }

    void ToggleSlider() {
        Log.Trace("toggle: visible=" + flyout.Visible + " mode=" + mode);
        if (flyout.Visible && mode == "slider") HideFlyout(); else ShowSlider();
    }

    void HideFlyout() {
        hideTimer.Stop();
        if (flyout.Visible) { hiddenAt = Environment.TickCount; flyout.Hide(); }
        mode = "";
    }

    void StepBrightness(int delta) {
        try {
            if (pending >= 0) { SetLevel(pending); pending = -1; }
            if (!flyout.Visible) mon.Refresh();
            int cur = (lastSet >= 0 && unchecked((uint)(Environment.TickCount - lastSetAt)) < 5000u) ? lastSet : mon.Get();
            if (cur < 0) { mon.Refresh(); cur = mon.Get(); }
            if (cur < 0) return;
            int v = SetLevel(cur + delta);
            flyout.SetValue(v);
            if (!flyout.Visible) { mode = "osd"; flyout.ShowAt(false); }
            if (mode == "osd") { hideTimer.Stop(); hideTimer.Interval = 1500; hideTimer.Start(); }
        } catch (Exception ex) { Log.Write("step: " + ex); }
    }

    // ---------------------------------------------------------------- start with Windows (per-user Run key)
    static string RunCommand() { return "\"" + Application.ExecutablePath + "\""; }

    // Windows' own on/off switch for Run entries (Settings > Apps > Startup, Task Manager):
    // a binary value whose first byte is odd (0x03) when the user switched the entry off.
    const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

    static bool IsAutoStart() {
        try {
            using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) {
                var v = k == null ? null : k.GetValue(RunValue) as string;
                if (v == null || v.IndexOf(Application.ExecutablePath, StringComparison.OrdinalIgnoreCase) < 0) return false;
            }
            using (var k = Registry.CurrentUser.OpenSubKey(ApprovedKey)) {
                var b = k == null ? null : k.GetValue(RunValue) as byte[];
                if (b != null && b.Length > 0 && (b[0] & 1) == 1) return false;   // switched off in Settings
            }
            return true;
        } catch { return false; }
    }

    static void SetAutoStart(bool on) {
        try {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey)) {
                if (on) k.SetValue(RunValue, RunCommand());
                else k.DeleteValue(RunValue, false);
            }
            // Clear Windows' "switched off" marker so turning it on here really turns it on.
            using (var k = Registry.CurrentUser.OpenSubKey(ApprovedKey, true)) {
                if (k != null) k.DeleteValue(RunValue, false);
            }
        } catch (Exception ex) { Log.Write("autostart: " + ex.Message); }
    }

    // ---------------------------------------------------------------- monitor name, tray icon
    static string Decode(object arr) {
        var a = arr as ushort[];
        if (a == null) return "";
        return new string(a.Where(c => c != 0).Select(c => (char)c).ToArray()).Trim();
    }

    // Friendly name of the external monitor (built-in laptop panels are the ones with WMI brightness).
    static string GetMonitorName() {
        try {
            var internalPanels = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try {
                using (var s = new ManagementObjectSearcher(@"root\wmi", "SELECT InstanceName FROM WmiMonitorBrightness"))
                using (var results = s.Get())
                    foreach (ManagementObject o in results) using (o) internalPanels.Add((string)o["InstanceName"]);
            } catch { }   // desktops without a built-in panel throw "not supported"
            var brands = new Dictionary<string, string> {
                { "ACR", "Acer" }, { "DEL", "Dell" }, { "SAM", "Samsung" }, { "GSM", "LG" }, { "AUS", "ASUS" },
                { "LEN", "Lenovo" }, { "HWP", "HP" }, { "BNQ", "BenQ" }, { "AOC", "AOC" }, { "PHL", "Philips" },
                { "MSI", "MSI" }, { "VSC", "ViewSonic" }, { "GBT", "Gigabyte" }, { "HKC", "HKC" }, { "IVM", "iiyama" }
            };
            using (var s = new ManagementObjectSearcher(@"root\wmi", "SELECT * FROM WmiMonitorID"))
            using (var results = s.Get())
                foreach (ManagementObject o in results) using (o) {
                    if (internalPanels.Contains((string)o["InstanceName"])) continue;
                    string maker = Decode(o["ManufacturerName"]), model = Decode(o["UserFriendlyName"]);
                    string brand;
                    if (!brands.TryGetValue(maker, out brand)) brand = maker;
                    string name = (brand + " " + model).Trim();
                    if (name.Length > 0) return name;
                }
        } catch (Exception ex) { Log.Write("monitor name: " + ex.Message); }
        return "External monitor";
    }

    static bool LightTaskbar() {
        try {
            using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
                object v = k == null ? null : k.GetValue("SystemUsesLightTheme");
                return v is int && (int)v == 1;
            }
        } catch { return false; }
    }

    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);

    // A sun, white on a dark taskbar and black on a light one, drawn at the tray's icon size.
    static Icon MakeTrayIcon() {
        int size = Math.Max(16, SystemInformation.SmallIconSize.Width);
        Color color = LightTaskbar() ? Color.Black : Color.White;
        using (var bmp = new Bitmap(size, size))
        using (var g = Graphics.FromImage(bmp))
        using (var brush = new SolidBrush(color))
        using (var pen = new Pen(color, Math.Max(1.5f, size / 10f))) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
            float c = size / 2f, k = size / 32f;
            g.FillEllipse(brush, c - 7 * k, c - 7 * k, 14 * k, 14 * k);
            for (int i = 0; i < 8; i++) {
                double a = i * Math.PI / 4;
                g.DrawLine(pen, c + 10.5f * k * (float)Math.Cos(a), c + 10.5f * k * (float)Math.Sin(a),
                                c + 14f * k * (float)Math.Cos(a), c + 14f * k * (float)Math.Sin(a));
            }
            IntPtr h = bmp.GetHicon();
            var icon = (Icon)Icon.FromHandle(h).Clone();   // clone owns its own handle
            DestroyIcon(h);
            return icon;
        }
    }

    void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) {
        if (e.Category != UserPreferenceCategory.General) return;
        var old = trayIcon;
        trayIcon = MakeTrayIcon();
        tray.Icon = trayIcon;
        if (old != null) old.Dispose();
    }

    public void Dispose() {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        pollTimer.Stop(); applyTimer.Stop(); hideTimer.Stop();
        tray.Visible = false;
        tray.Dispose();
        hk.Dispose();
        flyout.Dispose();
        mon.Dispose();
        if (trayIcon != null) trayIcon.Dispose();
    }
}
