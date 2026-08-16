# Quick Setup: Hyprland Wallpaper Coverflow

## 1. Install Dependencies
Arch Linux packages required for the Python webview and Bash engine:
```bash
sudo pacman -S python-pywebview webkit2gtk-4.1 python-gobject imagemagick rofi
```

## 2. Save the Files
Save the provided files to `~/.local/bin/` (or your preferred scripts folder):
* `wallpaper-picker.sh`
* `wallpaper-coverflow.py` 
* `wallpaper-coverflow.html`

Make the scripts executable:
```bash
chmod +x ~/.local/bin/wallpaper-picker.sh
chmod +x ~/.local/bin/wallpaper-coverflow.py
```

## 3. Configure Your Paths
Open `wallpaper-picker.sh` and update the following variables to match your personal setup. **This step is required for the script to find your wallpapers and configs.**

```bash
WALLPAPER_DIR="$HOME/.assets/wallpapers"
HYPRPAPER_CONF="$HOME/.config/hypr/hyprpaper.conf"
HYPRLOCK_CONF="$HOME/.config/hypr/hyprlock.conf"
MONITOR="eDP-1"
FIT_MODE="cover"

ROFI_THEME="$HOME/.config/rofi/wallpaper-menu.rasi"
THUMB_DIR="$HOME/.cache/wallpaper-thumbnails"
```

## 4. Add Hyprland Keybind
Add this line to your `hyprland.conf` to launch the 3D coverflow picker:
```hyprlang
bind = $mainMod, W, exec, python3 ~/.local/bin/wallpaper-coverflow.py
```
