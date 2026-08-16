#!/bin/bash
#
# wallpaper-picker.sh — Hyprland wallpaper engine
#
# Three modes:
#   (no args)            Interactive rofi thumbnail grid (fallback/CLI use)
#   --list-json          Print every wallpaper as JSON: [{"name","path","thumb"}, ...]
#   --apply <path>       Apply one wallpaper directly, no menu
#
# In every mode, applying a wallpaper:
#   - sets it live through hyprpaper's IPC (hyprctl hyprpaper ...)
#   - rewrites hyprpaper.conf using the current block syntax:
#       preload = <path>
#       wallpaper { monitor = ...  path = ...  fit_mode = ... }
#   - rewrites the `path =` line inside hyprlock.conf's background { } block
#   - (optional) regenerates a pywal palette and restarts waybar
#
# --list-json / --apply exist so a separate front end (e.g. the coverflow
# webview picker) can reuse this file as its single "apply engine" instead
# of duplicating the hyprpaper/hyprlock logic.
#
# Requires: hyprctl (hyprpaper running or startable); rofi only for the
# interactive mode. Optional: imagemagick (magick/convert) for fast
# thumbnails, pywal, notify-send.

set -uo pipefail

# ── Config — edit these for your setup ──────────────────────────────────
WALLPAPER_DIR="$HOME/.assets/wallpapers"
HYPRPAPER_CONF="$HOME/.config/hypr/hyprpaper.conf"
HYPRLOCK_CONF="$HOME/.config/hypr/hyprlock.conf"
MONITOR="eDP-1"
FIT_MODE="cover" # contain | cover | tile | fill

ROFI_THEME="$HOME/.config/rofi/wallpaper-menu.rasi"
THUMB_DIR="$HOME/.cache/wallpaper-thumbnails"
THUMB_SIZE=300

mkdir -p "$WALLPAPER_DIR" "$THUMB_DIR" "$(dirname "$ROFI_THEME")"

# ── Parse args ────────────────────────────────────────────────────────────
MODE="interactive"
APPLY_PATH=""
case "${1:-}" in
--list-json) MODE="list-json" ;;
--apply)
    MODE="apply"
    APPLY_PATH="${2:-}"
    ;;
--apply=*)
    MODE="apply"
    APPLY_PATH="${1#--apply=}"
    ;;
-h | --help)
    echo "Usage: $0 [--list-json | --apply <path>]"
    exit 0
    ;;
"") ;; # interactive
*)
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--list-json | --apply <path>]" >&2
    exit 1
    ;;
esac

# ── Dependency checks ────────────────────────────────────────────────────
command -v hyprctl >/dev/null 2>&1 || {
    echo "Missing dependency: hyprctl" >&2
    exit 1
}
if [[ "$MODE" == "interactive" ]]; then
    command -v rofi >/dev/null 2>&1 || {
        echo "Missing dependency: rofi" >&2
        exit 1
    }
fi

HAS_MAGICK=0
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    HAS_MAGICK=1
fi
HAS_WAL=0
command -v wal >/dev/null 2>&1 && HAS_WAL=1
HAS_NOTIFY=0
command -v notify-send >/dev/null 2>&1 && HAS_NOTIFY=1

notify() {
    [[ "$HAS_NOTIFY" -eq 1 ]] && notify-send "$@"
    return 0
}

# ── Escape a string for safe use as a sed replacement ───────────────────
sed_escape_repl() {
    printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}

# ── Minimal JSON string escaping (backslash + double quote) ─────────────
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ── Thumbnail cache (keeps any menu snappy on big wallpaper folders) ────
make_thumb() {
    local src="$1" key thumb
    key="$(printf '%s' "$src" | md5sum | cut -d' ' -f1)"
    thumb="$THUMB_DIR/$key.png"
    if [[ "$HAS_MAGICK" -eq 1 && (! -f "$thumb" || "$src" -nt "$thumb") ]]; then
        if command -v magick >/dev/null 2>&1; then
            magick "${src}[0]" -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
                -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$thumb" 2>/dev/null
        else
            convert "${src}[0]" -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
                -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$thumb" 2>/dev/null
        fi
    fi
    [[ -f "$thumb" ]] && echo "$thumb" || echo "$src"
}

# ── Apply one wallpaper: live IPC + persist both configs + extras ───────
apply_wallpaper() {
    local SELECTED="$1" ESC_SELECTED

    if [[ ! -f "$SELECTED" ]]; then
        echo "File not found: $SELECTED" >&2
        return 1
    fi
    ESC_SELECTED="$(sed_escape_repl "$SELECTED")"

    # Make sure hyprpaper is actually running before we IPC into it
    if ! pgrep -x hyprpaper >/dev/null; then
        setsid -f hyprpaper >/dev/null 2>&1
        for _ in $(seq 1 20); do
            hyprctl hyprpaper listloaded >/dev/null 2>&1 && break
            sleep 0.1
        done
    fi

    # preload -> assign -> unload anything no longer in use (avoids the
    # black flash you'd get from unloading everything before the new one
    # is ready)
    hyprctl hyprpaper preload "$SELECTED" >/dev/null
    hyprctl hyprpaper wallpaper "$MONITOR,$SELECTED,$FIT_MODE" >/dev/null
    hyprctl hyprpaper unload unused >/dev/null

    # Persist to hyprpaper.conf using the current block syntax
    if [[ -f "$HYPRPAPER_CONF" ]]; then
        sed -i "s|^preload = .*|preload = $ESC_SELECTED|" "$HYPRPAPER_CONF"
        sed -i "/^[[:space:]]*wallpaper[[:space:]]*{/,/^[[:space:]]*}/{
            s|^\([[:space:]]*path[[:space:]]*=[[:space:]]*\).*|\1$ESC_SELECTED|
        }" "$HYPRPAPER_CONF"
    else
        cat >"$HYPRPAPER_CONF" <<EOF
preload = $SELECTED

wallpaper {
    monitor = $MONITOR
    path = $SELECTED
    fit_mode = $FIT_MODE
}

splash = false
EOF
    fi

    # Persist to hyprlock.conf (same background{} block as before)
    if [[ -f "$HYPRLOCK_CONF" ]]; then
        sed -i "/^[[:space:]]*background[[:space:]]*{/,/^[[:space:]]*}/{
            s|^[[:space:]]*path[[:space:]]*=.*|    path = $ESC_SELECTED|
        }" "$HYPRLOCK_CONF"
    fi

    # Optional: regenerate a pywal palette from the new wallpaper
    #
    # setsid -f + full redirection matters here, not just style: this
    # function's stdout/stderr are the same pipe Python's
    # subprocess.run(capture_output=True) reads from when this script is
    # driven by the coverflow picker. A plain `wal ... &` would inherit
    # that pipe, and subprocess.run() won't return until every process
    # holding it open has exited -- so a slow (or hung) wal call would
    # silently block wallpaper-coverflow.py's apply thread, sometimes for
    # a very long time. setsid -f detaches it into its own session and
    # the redirect gives it its own stdout/stderr, so it can never hold
    # this script's pipe open.
    if [[ "$HAS_WAL" -eq 1 ]]; then
        setsid -f wal -i "$SELECTED" -n -q >/dev/null 2>&1
    fi
    # matugen image "$SELECTED"   # uncomment if you use matugen instead of pywal

    # Restart waybar cleanly, detached from this script's shell
    if pgrep -x waybar >/dev/null; then
        pkill -x waybar
    fi
    setsid -f waybar >/dev/null 2>&1

    notify -i "$SELECTED" "Wallpaper changed" "$(basename "$SELECTED")"
    return 0
}

# ── Collect wallpapers (NUL-safe, so spaces in filenames are fine) ──────
declare -A FILE_MAP
while IFS= read -r -d '' full_path; do
    FILE_MAP["$(basename "$full_path")"]="$full_path"
done < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
    -o -iname "*.webp" -o -iname "*.gif" \) -print0)

# ── Mode: --apply <path> ─────────────────────────────────────────────────
if [[ "$MODE" == "apply" ]]; then
    if [[ -z "$APPLY_PATH" ]]; then
        echo "Usage: $0 --apply <path>" >&2
        exit 1
    fi
    apply_wallpaper "$APPLY_PATH"
    exit $?
fi

if [[ ${#FILE_MAP[@]} -eq 0 ]]; then
    echo "No wallpapers found in $WALLPAPER_DIR" >&2
    notify "Wallpaper Picker" "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

mapfile -t SORTED_NAMES < <(printf '%s\n' "${!FILE_MAP[@]}" | sort)

# ── Mode: --list-json (feeds the coverflow webview picker) ──────────────
if [[ "$MODE" == "list-json" ]]; then
    first=1
    printf '['
    for filename in "${SORTED_NAMES[@]}"; do
        path="${FILE_MAP[$filename]}"
        thumb="$(make_thumb "$path")"
        [[ $first -eq 1 ]] && first=0 || printf ','
        printf '{"name":"%s","path":"%s","thumb":"%s"}' \
            "$(json_escape "$filename")" "$(json_escape "$path")" "$(json_escape "$thumb")"
    done
    printf ']\n'
    exit 0
fi

# ── Mode: interactive rofi grid (default) ────────────────────────────────
if [[ ! -f "$ROFI_THEME" ]]; then
    cat >"$ROFI_THEME" <<'EOF'
/* Glassy grid theme for the wallpaper picker — layered, low-opacity fills
   so the desktop shows through. Pair with a Hyprland layerrule (see the
   note at the bottom of this file) for a real frosted-glass blur. */
* {
    bg:          #1a1b2680;   /* window glass, ~50% */
    bg-soft:     #1a1b264d;   /* inputbar glass, lighter still */
    card:        #24283b59;  /* hovered/selected card, ~35% */
    border:      #7aa2f759;  /* faint hairline border */
    border-glow: #bb9af7cc;  /* brighter ring on the active item */
    accent:      #bb9af7;
    fg:          #c0caf5;
    fg-dim:      #a9b1d688;
    fg-faint:    #565f89aa;
}

window {
    width:            960px;
    height:           680px;
    background-color: @bg;
    border:           1px;
    border-radius:    26px;
    border-color:     @border;
    padding:          24px;
}

mainbox {
    background-color: transparent;
    children:          [ inputbar, listview ];
    spacing:            18px;
}

inputbar {
    background-color: @bg-soft;
    border-radius:     16px;
    border:              1px;
    border-color:         @border;
    padding:               12px 20px;
    children:               [ prompt, entry ];
    spacing:                 12px;
}

prompt {
    background-color: transparent;
    text-color:        @accent;
    font:               "JetBrainsMono Nerd Font Bold 12";
}

entry {
    background-color:   transparent;
    text-color:          @fg;
    placeholder:          "Search wallpapers…";
    placeholder-color:    @fg-faint;
    font:                 "JetBrainsMono Nerd Font 12";
}

listview {
    background-color: transparent;
    columns:            3;
    lines:               2;
    spacing:              18px;
    fixed-height:          false;
    dynamic:               true;
    scrollbar:              false;
}

/* Unselected thumbnails float with no card behind them — just the image
   and a dimmed label, so the grid itself reads as transparent. */
element {
    background-color: transparent;
    text-color:         @fg-dim;
    orientation:         vertical;
    border-radius:        18px;
    padding:               10px;
    border:                 1px;
    border-color:            transparent;
}

/* Hovered/selected gets a soft glass card + a glowing accent ring. */
element selected, element active {
    background-color: @card;
    border-color:        @border-glow;
    text-color:            @fg;
}

element-icon {
    size:              208px;
    border-radius:      14px;
    horizontal-align:    0.5;
}

element-text {
    horizontal-align: 0.5;
    vertical-align:    0.5;
    margin:              10px 0px 0px 0px;
    font:                 "JetBrainsMono Nerd Font 10";
}

/*
   For a true frosted-glass blur (not just flat translucency), add to
   hyprland.conf and reload:

       layerrule = blur, rofi
       layerrule = ignorezero, rofi

   and make sure `decoration { blur { enabled = true } }` is set in your
   general Hyprland decoration config. Without that layerrule the window
   is still see-through, just not blurred.
*/
EOF
fi

SELECTED_FILENAME=$(
    for filename in "${SORTED_NAMES[@]}"; do
        icon="$(make_thumb "${FILE_MAP[$filename]}")"
        printf '%s\x00icon\x1f%s\n' "$filename" "$icon"
    done | rofi -dmenu -i -show-icons -theme "$ROFI_THEME" -p "Wallpapers"
)

[[ -z "$SELECTED_FILENAME" ]] && exit 0

apply_wallpaper "${FILE_MAP[$SELECTED_FILENAME]}"
exit $?
