using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class Ddc {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")]
    static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc cb, IntPtr data);
    [DllImport("dxva2.dll")]
    static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint count);
    [DllImport("dxva2.dll", CharSet = CharSet.Unicode)]
    static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")]
    static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")]
    static extern bool GetMonitorBrightness(IntPtr h, out uint min, out uint cur, out uint max);
    [DllImport("dxva2.dll")]
    static extern bool SetMonitorBrightness(IntPtr h, uint value);

    public static List<PHYSICAL_MONITOR> All() {
        var list = new List<PHYSICAL_MONITOR>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (h, dc, r, d) => {
            uint n;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(h, out n) && n > 0) {
                var arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(h, n, arr)) list.AddRange(arr);
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // returns -1 if the monitor does not answer DDC/CI
    public static int Get(IntPtr h) {
        uint min, cur, max;
        if (!GetMonitorBrightness(h, out min, out cur, out max) || max <= min) return -1;
        double p = 100.0 * ((double)cur - min) / ((double)max - min);
        return (int)Math.Max(0, Math.Min(100, Math.Round(p)));
    }

    public static bool Set(IntPtr h, int percent) {
        uint min, cur, max;
        if (!GetMonitorBrightness(h, out min, out cur, out max)) return false;
        percent = Math.Max(0, Math.Min(100, percent));
        uint raw = (uint)(min + Math.Round((max - min) * percent / 100.0));
        return SetMonitorBrightness(h, raw);
    }

    public static void Release(List<PHYSICAL_MONITOR> list) {
        DestroyPhysicalMonitors((uint)list.Count, list.ToArray());
    }
}
