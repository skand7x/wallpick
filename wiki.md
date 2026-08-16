# Hyprland 3D Coverflow Wallpaper Picker Wiki

## 1. Overview
This project is a 3D coverflow wallpaper picker designed specifically for Hyprland. It is split into three main components to separate the UI from the window management logic:
* **`wallpaper-picker.sh`**: The core engine. It handles IPC with `hyprpaper`, updates configuration files, generates thumbnails, and provides an interactive `rofi` fallback menu.
* **`wallpaper-coverflow.py`**: A Python wrapper using `pywebview` (GTK/WebKit backend) to create a frameless, transparent window for the UI.
* **`wallpaper-coverflow.html`**: The frontend UI built with HTML/CSS/JS that renders the 3D coverflow and interacts with the Python backend to apply wallpapers.

## 2. Dependencies
To ensure all features work correctly, you need to install the following packages.
```bash
sudo pacman -S python-pywebview webkit2gtk-4.1 python-gobject imagemagick rofi
```
* **Required for UI**: `python-pywebview`, `webkit2gtk-4.1`, `python-gobject`.
* **Required for Engine**: `hyprpaper`, `hyprctl`.
* **Optional but recommended**: `imagemagick` (for fast thumbnail generation), `python-pywal` (for dynamic color schemes), and `libnotify` (for desktop notifications).

## 3. Customizing Paths & Variables (Crucial Step)
Before running the picker, you **must** configure the paths in `wallpaper-picker.sh` to match your system structure. Open `wallpaper-picker.sh` and edit the `Config` block at the top.

### Core Paths
*   **`WALLPAPER_DIR`**: The directory containing your wallpapers.
    *   *Default:* `"$HOME/.assets/wallpapers"`
    *   *Action:* Change this to wherever you keep your images (e.g., `"$HOME/Pictures/Wallpapers"`).
*   **`HYPRPAPER_CONF`**: The path to your Hyprpaper configuration file. The script rewrites this file so your wallpaper persists after reboot.
    *   *Default:* `"$HOME/.config/hypr/hyprpaper.conf"`
*   **`HYPRLOCK_CONF`**: The path to your Hyprlock configuration file.
    *   *Default:* `"$HOME/.config/hypr/hyprlock.conf"`

### Monitor & Rendering
*   **`MONITOR`**: The name of the monitor you want the wallpaper applied to. (You can find your monitor name by running `hyprctl monitors`).
    *   *Default:* `"eDP-1"`
*   **`FIT_MODE`**: How the image should scale on your screen.
    *   *Default:* `"cover"` (Other options: `contain`, `tile`, `fill`).

### Caching & Fallback UI
*   **`THUMB_DIR`**: Where the script stores generated thumbnails for the coverflow and rofi.
    *   *Default:* `"$HOME/.cache/wallpaper-thumbnails"`
*   **`ROFI_THEME`**: Where the script will auto-generate its glassy `rofi` theme for the fallback menu.
    *   *Default:* `"$HOME/.config/rofi/wallpaper-menu.rasi"`

## 4. Installation & Setup
1. Save all three files (`wallpaper-picker.sh`, `wallpaper-coverflow.py`, and `wallpaper-coverflow.html`) in the exact same directory (e.g., `~/.local/bin/`).
2. Make the executable files runnable:
   ```bash
   chmod +x ~/.local/bin/wallpaper-picker.sh
   chmod +x ~/.local/bin/wallpaper-coverflow.py
   ```
3. Ensure `hyprpaper` is configured to launch with Hyprland by adding `exec-once = hyprpaper` to your `hyprland.conf`.

## 5. Usage & Integration
### Launching the 3D Coverflow
Bind the Python script in your `hyprland.conf`:
```hyprlang
bind = $mainMod, W, exec, python3 ~/.local/bin/wallpaper-coverflow.py
```
*(Navigation: Use `Esc` to close the window, `Arrow Keys` or drag to scroll, and `Enter` to apply).*

### Rofi Fallback Mode
If you execute `wallpaper-picker.sh` from the terminal with no arguments, it opens an interactive Rofi thumbnail grid instead of the 3D web view. This is useful as a fallback or CLI alternative.
```bash
~/.local/bin/wallpaper-picker.sh
```

## 6. Advanced Customization & Effects
*   **Blurring the Coverflow Window:** To give the transparent window a true frosted glass effect, add these rules to your `hyprland.conf`:
    ```hyprlang
    windowrule = float, ^(Wallpaper Coverflow)$
    windowrule = noborder, ^(Wallpaper Coverflow)$
    # Add blur to the Rofi menu as well
    layerrule = blur, rofi
    layerrule = ignorezero, rofi
    ```
*   **Dynamic Colors (pywal):** If `wal` is installed, the bash script automatically generates a new palette and restarts Waybar whenever a wallpaper is applied. If you prefer a static color scheme, comment out the `setsid -f wal ...` line in `wallpaper-picker.sh`.
