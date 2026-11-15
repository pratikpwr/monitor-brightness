<div align="center">

<img src="assets/icon.png" width="72" alt="Monitor Brightness icon">

# Monitor Brightness for Windows

**Change your external monitor's brightness from Windows 11 and Windows 10, without the monitor's buttons.**

A free, open-source system tray app with a Windows 11–style brightness slider and keyboard shortcuts, for any external monitor that supports DDC/CI.

[![Latest release](https://img.shields.io/github/v/release/pratikpwr/monitor-brightness?label=download&style=flat-square)](https://github.com/pratikpwr/monitor-brightness/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/pratikpwr/monitor-brightness/total?style=flat-square)](https://github.com/pratikpwr/monitor-brightness/releases)
[![Windows 10 | 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=flat-square&logo=windows)](#requirements)
[![License: MIT](https://img.shields.io/github/license/pratikpwr/monitor-brightness?style=flat-square)](LICENSE)

![Monitor Brightness: Windows 11 style brightness slider for an external monitor](docs/flyout.png)

**[⬇ Download MonitorBrightness.zip](https://github.com/pratikpwr/monitor-brightness/releases/latest/download/MonitorBrightness.zip)**

</div>

---

Windows' brightness slider only works on **laptop screens**. On a desktop PC or an external monitor, it's missing or does nothing, so you're stuck pressing the monitor's physical buttons. **Monitor Brightness** fixes that. It talks to your monitor over **DDC/CI**, the standard most monitors already support, so you can adjust brightness from the taskbar or a keyboard shortcut.

## Features

- 🔆 **Brightness slider in the system tray.** Click the sun icon to get a flyout that looks like Windows 11 quick settings. It follows your accent colour and light/dark mode.
- 🎚️ **One-click presets:** 10 / 30 / 50 / 70 / 100%.
- ⌨️ **Global keyboard shortcuts:**

  | Shortcut | Action |
  |---|---|
  | `Ctrl` + `Alt` + `B` | Open / close the brightness slider |
  | `Ctrl` + `Alt` + `Page Up` | 10% brighter |
  | `Ctrl` + `Alt` + `Page Down` | 10% dimmer |

- 🖱️ **Mouse wheel and arrow keys** work on the slider, including on precision touchpads.
- 🚀 **Starts when you sign in** and stays quietly in the tray.
- 🖥️ **Sharp on every display:** it handles a different scaling (DPI) per monitor.
- 🪶 **Lightweight native app (about 50 KB), no admin rights, nothing extra to install.** It's built on your PC from source with tools already in Windows. It appears in *Settings → Apps* with a normal Uninstall button.
- 🔓 **Free and open source** (MIT).

## Download and install

### Option 1: ZIP (easiest)

1. Download **[MonitorBrightness.zip](https://github.com/pratikpwr/monitor-brightness/releases/latest/download/MonitorBrightness.zip)** and extract it.
2. Double-click **`Install.cmd`**.

Look for the ☀ sun icon in the system tray, or press **Ctrl + Alt + B**.

> Windows may say *"The publisher could not be verified"* because the scripts aren't code-signed. Click **Run**. All the source code is in this repo for you to inspect.

### Option 2: one-line PowerShell install

Open PowerShell (no admin needed) and run:

```powershell
irm https://raw.githubusercontent.com/pratikpwr/monitor-brightness/main/web-install.ps1 | iex
```

It downloads the latest release, installs it and cleans up after itself. To **update**, run the same command again, or run `Install.cmd` from a newer ZIP.

### Option 3: from source

```powershell
git clone https://github.com/pratikpwr/monitor-brightness.git
cd monitor-brightness
powershell -ExecutionPolicy Bypass -File install.ps1
```

## Requirements

- **Windows 11 or Windows 10.** The rounded flyout corners need Windows 11.
- An **external monitor with DDC/CI turned on.** Most monitors from Acer, Dell, LG, Samsung, ASUS, BenQ, HP, Lenovo, AOC, MSI, ViewSonic and others support it, and it's usually on by default. If not, enable **DDC/CI** in the monitor's on-screen menu.
- It works over **HDMI, DisplayPort, USB-C and DVI**. Some docks, KVM switches and USB display adapters (often DisplayLink) don't pass DDC/CI through.

## FAQ

**Why can't I change brightness on my external monitor in Windows 11?**
Windows' built-in brightness slider controls only the built-in panels of laptops and tablets. External monitors have their own brightness setting, which Windows doesn't expose. This app sets it directly over DDC/CI, the same channel the monitor's own buttons use.

**What is DDC/CI?**
*Display Data Channel / Command Interface.* It's a standard that lets a computer read and change monitor settings, such as brightness, over the video cable.

**Does it dim the screen with an overlay, like f.lux or Night light?**
No. It changes the monitor's real **backlight brightness**. That saves power and is easier on your eyes than a dark overlay. For warmer colours in the evening, combine it with Windows **Night light**.

**Does it work with multiple monitors?**
Yes. The slider and hotkeys set every external monitor that supports DDC/CI to the same level. Laptop screens are left to Windows.

**Is it safe?**
It's open source (PowerShell plus a little C#), runs only for your user account, needs no admin rights, and makes no network connections. It only reads and sets brightness.

**Can I change the shortcuts, step size or presets?**
Yes. See [Customise](#customise).

## Command line

`brightness.ps1` can be used in scripts and scheduled tasks:

```powershell
powershell -ExecutionPolicy Bypass -File brightness.ps1        # show current brightness
powershell -ExecutionPolicy Bypass -File brightness.ps1 40     # set to 40%
powershell -ExecutionPolicy Bypass -File brightness.ps1 +10    # 10% brighter
powershell -ExecutionPolicy Bypass -File brightness.ps1 -10    # 10% dimmer
```

After installing, it's in `%LOCALAPPDATA%\MonitorBrightness`.

## Customise

The installer keeps the source code in `%LOCALAPPDATA%\MonitorBrightness\src`, so you can change it and rebuild:

| What | Where |
|---|---|
| Hotkey step (default 10%) | `const int Step = 10;` in `src\app.cs` |
| Preset buttons | `Presets = { 10, 30, 50, 70, 100 }` in `src\ui.cs` |

Then rebuild and restart the app:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MonitorBrightness\install.ps1"
```

**Start with Windows** can be turned on or off from the tray icon's right-click menu.

## Uninstall

Use **Settings → Apps → Installed apps → Monitor Brightness → Uninstall**, double-click `Uninstall.cmd` from the ZIP, or run:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\MonitorBrightness\install.ps1" -Uninstall
```

## Troubleshooting

- **"No monitor answered DDC/CI"**
  - Turn on DDC/CI in the monitor's menu.
  - Connect the monitor directly instead of through a dock or adapter.
  - Make sure the monitor isn't asleep.
- **A shortcut does nothing:** another app is already using it. The tray app shows a notification at start-up if a shortcut couldn't be registered.
- **No tray icon after restarting:**
  - Check **Settings → Apps → Startup** and turn on *Monitor Brightness*.
  - The icon may be hidden in the tray overflow (˄). Drag it onto the taskbar to keep it visible.
- **Run the installer yourself.** Installing from inside another sandboxed app (for example a Microsoft Store app's terminal) can put the files in that app's private storage, where Windows can't see them at sign-in.
- **Something else:** errors are logged to `%LOCALAPPDATA%\MonitorBrightness\tray.log`. Please [open an issue](https://github.com/pratikpwr/monitor-brightness/issues) with the log and your monitor model.

## How it works

| File | Role |
|---|---|
| `app.cs` | The tray app (`MonitorBrightness.exe`). Runs a single instance, handles the hotkeys and the tray menu, and limits DDC/CI writes while you drag (the bus is slow). |
| `ui.cs` | Draws the Windows 11–style flyout, Fluent slider and buttons. Reads the theme and accent colour, handles per-monitor DPI, and registers the global hotkeys. |
| `ddc.cs` | Reads and sets brightness through the Windows Monitor Configuration API (`dxva2.dll`, DDC/CI VCP code 0x10). |
| `install.ps1` | Builds the exe and handles per-user install, update and uninstall, including shortcuts, auto-start (`HKCU\…\Run`) and the *Settings → Apps* entry. |
| `brightness.ps1` | Command-line tool. |
| `web-install.ps1` | The one-line installer. |

The installer compiles `MonitorBrightness.exe` on your PC with the C# compiler that's part of the .NET Framework built into Windows. The release therefore contains only readable source code and no pre-built binary. `tools/build-release.ps1` builds the release ZIP.

## Contributing

Issues and pull requests are welcome, especially reports of monitors that do or don't work.

## License

[MIT](LICENSE) © pratikpwr

<sub>Keywords: windows 11 external monitor brightness, change monitor brightness without buttons, desktop PC brightness slider, DDC/CI brightness control, brightness hotkey windows, adjust second monitor brightness, screen brightness tray app.</sub>
