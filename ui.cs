// UI pieces for the Monitor Brightness tray app. Compiled by Windows PowerShell 5.1 Add-Type (C# 5: no $"", ?., nameof, =>).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

// ---------------------------------------------------------------- native helpers
public static class Native {
    [DllImport("user32.dll")] static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr hmon, int type, out uint dpiX, out uint dpiY);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

    // Per-monitor DPI awareness so the flyout is drawn sharp on every screen. Call before any window exists.
    public static void EnableDpiAwareness() { try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { } }
    public static void AllowAnyForeground() { AllowSetForegroundWindow(-1); }
    public static bool Bring(IntPtr hWnd) { return SetForegroundWindow(hWnd); }
    public static bool IsForeground(IntPtr hWnd) { return GetForegroundWindow() == hWnd; }

    public static int DpiAt(Point p) {
        try {
            POINT pt; pt.X = p.X; pt.Y = p.Y;
            uint x, y;
            if (GetDpiForMonitor(MonitorFromPoint(pt, 2), 0, out x, out y) == 0 && x > 0) return (int)x;
        } catch { }
        return 96;
    }
}

// ---------------------------------------------------------------- global hotkeys
public class HotkeyWindow : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler<HotkeyArgs> Pressed;
    readonly List<int> ids = new List<int>();

    public HotkeyWindow() { CreateHandle(new CreateParams()); }

    public bool Register(int id, uint mods, uint vk) {
        if (!RegisterHotKey(Handle, id, mods, vk)) return false;
        ids.Add(id);
        return true;
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312 && Pressed != null) Pressed(this, new HotkeyArgs(m.WParam.ToInt32()));
        base.WndProc(ref m);
    }

    public void Dispose() {
        foreach (int id in ids) UnregisterHotKey(Handle, id);
        ids.Clear();
        DestroyHandle();
    }
}

public class HotkeyArgs : EventArgs {
    public readonly int Id;
    public HotkeyArgs(int id) { Id = id; }
}

// ---------------------------------------------------------------- Windows 11 colours
public class Theme {
    public bool Dark;
    public Color Surface, Footer, Border, Text, SubText, Track, ThumbOuter, ThumbBorder, Accent, OnAccent,
                 BtnFill, BtnHover, BtnPress, BtnBorder;

    static Color Hex(int rgb) { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }

    public static Theme Load() {
        var t = new Theme();
        t.Dark = true;
        try {
            using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
                object v = k == null ? null : k.GetValue("SystemUsesLightTheme");
                if (v is int) t.Dark = (int)v == 0;
            }
        } catch { }

        // Accent: Windows uses the lighter "Light 2" shade on dark surfaces and "Dark 1" on light ones.
        t.Accent = t.Dark ? Hex(0x60CDFF) : Hex(0x005FB8);
        try {
            using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent")) {
                var pal = k == null ? null : k.GetValue("AccentPalette") as byte[];
                if (pal != null && pal.Length >= 28) {
                    int i = t.Dark ? 1 : 4;
                    t.Accent = Color.FromArgb(pal[i * 4], pal[i * 4 + 1], pal[i * 4 + 2]);
                }
            }
        } catch { }

        if (t.Dark) {
            t.Surface = Hex(0x2C2C2C); t.Footer = Hex(0x202020); t.Border = Hex(0x3F3F3F);
            t.Text = Hex(0xFFFFFF); t.SubText = Hex(0xC8C8C8);
            t.Track = Hex(0x9A9A9A); t.ThumbOuter = Hex(0x454545); t.ThumbBorder = Hex(0x515151);
            t.OnAccent = Hex(0x000000);
            t.BtnFill = Hex(0x373737); t.BtnHover = Hex(0x3D3D3D); t.BtnPress = Hex(0x323232); t.BtnBorder = Hex(0x444444);
        } else {
            t.Surface = Hex(0xF3F3F3); t.Footer = Hex(0xEBEBEB); t.Border = Hex(0xD6D6D6);
            t.Text = Hex(0x1B1B1B); t.SubText = Hex(0x5D5D5D);
            t.Track = Hex(0x868686); t.ThumbOuter = Hex(0xFFFFFF); t.ThumbBorder = Hex(0xD9D9D9);
            t.OnAccent = Hex(0xFFFFFF);
            t.BtnFill = Hex(0xFBFBFB); t.BtnHover = Hex(0xF6F6F6); t.BtnPress = Hex(0xF0F0F0); t.BtnBorder = Hex(0xE0E0E0);
        }
        return t;
    }

    public static GraphicsPath Round(RectangleF r, float radius) {
        var p = new GraphicsPath();
        float d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        if (d <= 0) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}

// ---------------------------------------------------------------- WinUI-style slider
public class FluentSlider : Control {
    int value;
    bool hover, drag;
    public float UiScale = 1f;
    public Theme T = Theme.Load();
    public event EventHandler ValueChanged;   // raised only for changes the user makes

    public FluentSlider() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                 ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        TabStop = true;
    }

    public int Value { get { return value; } }
    public void SetValue(int v) { v = Clamp(v); if (v != value) { value = v; Invalidate(); } }

    void UserSet(int v) {
        v = Clamp(v);
        if (v == value) return;
        value = v;
        Invalidate();
        if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
    }
    static int Clamp(int v) { return Math.Max(0, Math.Min(100, v)); }

    float Radius { get { return 10f * UiScale; } }
    float Left0 { get { return Radius; } }
    float Right0 { get { return Width - Radius; } }
    float ThumbX { get { return Left0 + (Right0 - Left0) * value / 100f; } }
    int FromX(int x) { return (int)Math.Round((x - Left0) / Math.Max(1f, Right0 - Left0) * 100f); }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        float cy = Height / 2f, th = 4f * UiScale, x = ThumbX, r = Radius;

        using (var b = new SolidBrush(T.Track))
        using (var p = Theme.Round(new RectangleF(Left0, cy - th / 2, Right0 - Left0, th), th / 2)) g.FillPath(b, p);
        if (x - Left0 > 0.5f)
            using (var b = new SolidBrush(T.Accent))
            using (var p = Theme.Round(new RectangleF(Left0, cy - th / 2, x - Left0, th), th / 2)) g.FillPath(b, p);

        using (var b = new SolidBrush(T.ThumbOuter)) g.FillEllipse(b, x - r, cy - r, 2 * r, 2 * r);
        using (var pen = new Pen(T.ThumbBorder, Math.Max(1f, UiScale))) g.DrawEllipse(pen, x - r + 0.5f, cy - r + 0.5f, 2 * r - 1, 2 * r - 1);
        float ir = (drag ? 5f : hover ? 7f : 6f) * UiScale;   // inner dot shrinks when pressed, grows on hover (like WinUI)
        using (var b = new SolidBrush(T.Accent)) g.FillEllipse(b, x - ir, cy - ir, 2 * ir, 2 * ir);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) { Focus(); drag = true; Capture = true; UserSet(FromX(e.X)); Invalidate(); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (drag && (e.Button & MouseButtons.Left) != 0) UserSet(FromX(e.X));
        base.OnMouseMove(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        if (drag) { drag = false; Capture = false; Invalidate(); }
        base.OnMouseUp(e);
    }
    // Window hidden mid-drag (focus lost, hotkey): no MouseUp arrives, so end the drag here.
    protected override void OnMouseCaptureChanged(EventArgs e) {
        if (drag) { drag = false; Invalidate(); }
        base.OnMouseCaptureChanged(e);
    }
    // Precision touchpads send small deltas: add them up and step 2% per full notch (120).
    int wheelAcc;
    protected override void OnMouseWheel(MouseEventArgs e) {
        wheelAcc += e.Delta;
        int notches = wheelAcc / 120;
        if (notches != 0) { wheelAcc -= notches * 120; UserSet(value + 2 * notches); }
        base.OnMouseWheel(e);
    }
    protected override bool IsInputKey(Keys k) {
        switch (k & Keys.KeyCode) {
            case Keys.Left: case Keys.Right: case Keys.Up: case Keys.Down: case Keys.Home: case Keys.End: return true;
        }
        return base.IsInputKey(k);
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        switch (e.KeyCode) {
            case Keys.Left: case Keys.Down: UserSet(value - 1); e.Handled = true; break;
            case Keys.Right: case Keys.Up: UserSet(value + 1); e.Handled = true; break;
            case Keys.PageDown: UserSet(value - 10); e.Handled = true; break;
            case Keys.PageUp: UserSet(value + 10); e.Handled = true; break;
            case Keys.Home: UserSet(0); e.Handled = true; break;
            case Keys.End: UserSet(100); e.Handled = true; break;
        }
        base.OnKeyDown(e);
    }
}

// ---------------------------------------------------------------- Windows 11 button (preset %)
public class PresetButton : Control {
    public int Percent;
    public bool Selected;
    public float UiScale = 1f;
    public Theme T = Theme.Load();
    bool hover, press;

    public PresetButton() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                 ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        Cursor = Cursors.Default;
    }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        Color fill = Selected ? T.Accent : press ? T.BtnPress : hover ? T.BtnHover : T.BtnFill;
        if (Selected && (hover || press)) fill = ControlPaint.Light(T.Accent, press ? 0.0f : 0.15f);
        var r = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
        using (var path = Theme.Round(r, 4f * UiScale)) {
            using (var b = new SolidBrush(fill)) g.FillPath(b, path);
            if (!Selected) using (var pen = new Pen(T.BtnBorder, 1f)) g.DrawPath(pen, path);
        }
        Color fg = Selected ? T.OnAccent : (press ? T.SubText : T.Text);
        TextRenderer.DrawText(g, Percent + "%", Font, ClientRectangle, fg, fill,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; press = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { press = true; Invalidate(); } base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { press = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnMouseCaptureChanged(EventArgs e) { if (press) { press = false; Invalidate(); } base.OnMouseCaptureChanged(e); }
}

// ---------------------------------------------------------------- the flyout (looks like Windows 11 quick settings)
public class BrightnessFlyout : Form {
    public static readonly int[] Presets = { 10, 30, 50, 70, 100 };
    public readonly FluentSlider Slider = new FluentSlider();
    readonly List<PresetButton> buttons = new List<PresetButton>();
    readonly Timer anim = new Timer();
    public string MonitorName = "External monitor";
    public bool NoActivate;
    public event EventHandler ValueChanged;   // user changed the value (slider, wheel, keys or a preset)
    public event EventHandler EscapePressed;

    Theme T = Theme.Load();
    float s = 1f;
    Font textFont, valueFont, iconFont;
    int fontDpi;
    Rectangle iconRect, valueRect, footerRect;
    int animTarget, animStep;

    public BrightnessFlyout() {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        // Not TopMost = true: WinForms then activates the window on Show even with ShowWithoutActivation.
        // WS_EX_TOPMOST is set in CreateParams instead.
        KeyPreview = true;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);

        Slider.ValueChanged += delegate { UpdateValueUi(); if (ValueChanged != null) ValueChanged(this, EventArgs.Empty); };
        Controls.Add(Slider);
        foreach (int p in Presets) {
            var b = new PresetButton();
            b.Percent = p;
            b.Click += delegate(object sender, EventArgs e) {
                Slider.SetValue(((PresetButton)sender).Percent);
                UpdateValueUi();
                if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
            };
            buttons.Add(b);
            Controls.Add(b);
        }
        anim.Interval = 10;
        anim.Tick += delegate {
            animStep++;
            double t = Math.Min(1.0, animStep / 12.0);
            double ease = 1 - Math.Pow(1 - t, 3);
            Top = animTarget + (int)Math.Round((1 - ease) * 24 * s);
            if (t >= 1) anim.Stop();
        };
        ApplyLayout(96);
    }

    public int Value { get { return Slider.Value; } }
    public void SetValue(int v) { Slider.SetValue(v); UpdateValueUi(); }

    protected override bool ShowWithoutActivation { get { return NoActivate; } }
    protected override CreateParams CreateParams {
        get {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x80 | 0x8;   // WS_EX_TOOLWINDOW (not in Alt+Tab) | WS_EX_TOPMOST
            return cp;
        }
    }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        ApplyDwm();
    }

    void ApplyDwm() {
        if (!IsHandleCreated) return;
        try {
            int round = 2;                                    // DWMWCP_ROUND: Windows 11 rounded corners
            Native.DwmSetWindowAttribute(Handle, 33, ref round, 4);
            int c = T.Border.R | (T.Border.G << 8) | (T.Border.B << 16);
            Native.DwmSetWindowAttribute(Handle, 34, ref c, 4);   // border colour
        } catch { }
    }

    static Font MakeFont(string family, string fallback, float px, FontStyle style) {
        try {
            var f = new Font(family, px, style, GraphicsUnit.Pixel);
            if (f.Name == family) return f;
            f.Dispose();
        } catch { }
        return new Font(fallback, px, style, GraphicsUnit.Pixel);
    }

    void UpdateValueUi() {
        foreach (var b in buttons) {
            bool sel = b.Percent == Slider.Value;
            if (b.Selected != sel) { b.Selected = sel; b.Invalidate(); }
        }
        Invalidate(valueRect);
    }

    // Lay everything out for the given DPI (96 = 100%).
    void ApplyLayout(int dpi) {
        s = dpi / 96f;
        Func<float, int> S = v => (int)Math.Round(v * s);
        // Rebuild fonts only when the DPI changes; hand the new ones to the buttons before disposing the old ones.
        Font oldText = null, oldValue = null, oldIcon = null;
        if (dpi != fontDpi || textFont == null) {
            oldText = textFont; oldValue = valueFont; oldIcon = iconFont;
            textFont = MakeFont("Segoe UI Variable Text", "Segoe UI", 14 * s, FontStyle.Regular);
            valueFont = MakeFont("Segoe UI Variable Text Semibold", "Segoe UI Semibold", 14 * s, FontStyle.Regular);
            iconFont = MakeFont("Segoe Fluent Icons", "Segoe MDL2 Assets", 16 * s, FontStyle.Regular);
            fontDpi = dpi;
        }

        int w = S(360), pad = S(20);
        int rowY = S(16), rowH = S(40);
        iconRect = new Rectangle(pad, rowY, S(20), rowH);
        valueRect = new Rectangle(w - pad - S(44), rowY, S(44), rowH);
        int sx = pad + S(32);
        Slider.UiScale = s; Slider.T = T; Slider.BackColor = T.Surface;
        Slider.SetBounds(sx, rowY, valueRect.Left - S(8) - sx, rowH);

        int by = S(68), bh = S(32), gap = S(8);
        int bw = (w - 2 * pad - gap * (buttons.Count - 1)) / buttons.Count;
        for (int i = 0; i < buttons.Count; i++) {
            var b = buttons[i];
            b.UiScale = s; b.T = T; b.BackColor = T.Surface; b.Font = textFont;
            b.SetBounds(pad + i * (bw + gap), by, bw, bh);
        }
        if (oldText != null) { oldText.Dispose(); oldValue.Dispose(); oldIcon.Dispose(); }
        footerRect = new Rectangle(0, S(120), w, S(48));
        ClientSize = new Size(w, footerRect.Bottom);
        BackColor = T.Surface;
        Invalidate(true);
    }

    protected override void OnPaint(PaintEventArgs e) {
        var g = e.Graphics;
        g.Clear(T.Surface);
        using (var b = new SolidBrush(T.Footer)) g.FillRectangle(b, footerRect);
        using (var pen = new Pen(T.Border)) g.DrawLine(pen, 0, footerRect.Top, Width, footerRect.Top);

        var center = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding;
        TextRenderer.DrawText(g, "", iconFont, iconRect, T.Text, T.Surface, center);                  // brightness icon
        TextRenderer.DrawText(g, Slider.Value + "%", valueFont, valueRect, T.Text, T.Surface,
            TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        int pad = (int)Math.Round(20 * s);
        var mon = new Rectangle(pad, footerRect.Top, (int)Math.Round(20 * s), footerRect.Height);
        TextRenderer.DrawText(g, "", iconFont, mon, T.Text, T.Footer, center);                          // monitor icon
        const string hint = "Ctrl+Alt+B";
        int hintW = TextRenderer.MeasureText(g, hint, textFont, Size.Empty, TextFormatFlags.NoPadding).Width;
        TextRenderer.DrawText(g, hint, textFont, new Rectangle(0, footerRect.Top, Width - pad, footerRect.Height), T.SubText, T.Footer,
            TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        int nameX = mon.Right + (int)Math.Round(10 * s);
        var name = new Rectangle(nameX, footerRect.Top, Math.Max(0, Width - pad - hintW - (int)Math.Round(12 * s) - nameX), footerRect.Height);
        TextRenderer.DrawText(g, MonitorName, textFont, name, T.Text, T.Footer,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Escape && EscapePressed != null) { EscapePressed(this, EventArgs.Empty); e.Handled = true; }
        base.OnKeyDown(e);
    }

    // The first window a process shows takes its launcher's show state ("hidden" under conhost --headless).
    // Show once off-screen to use that up, so later shows are visible.
    public void Prime() {
        NoActivate = true;
        Location = new Point(-32000, -32000);
        Show();
        Hide();
    }

    // Show above the taskbar on the screen the mouse is on, sliding up like Windows flyouts.
    public void ShowAt(bool activate) {
        Point cur = Cursor.Position;
        T = Theme.Load();                     // follow theme / accent changes
        ApplyLayout(Native.DpiAt(cur));
        ApplyDwm();
        Rectangle wa = Screen.FromPoint(cur).WorkingArea;
        int m = (int)Math.Round(12 * s);
        animTarget = wa.Bottom - Height - m;
        bool wasVisible = Visible;
        Location = new Point(wa.Right - Width - m, wasVisible ? animTarget : animTarget + (int)Math.Round(24 * s));
        NoActivate = !activate;
        if (!wasVisible) { animStep = 0; Show(); anim.Start(); }
        if (activate) { Activate(); Native.Bring(Handle); Slider.Focus(); }
    }

    protected override void OnVisibleChanged(EventArgs e) {
        if (!Visible) { anim.Stop(); }
        base.OnVisibleChanged(e);
    }
}
