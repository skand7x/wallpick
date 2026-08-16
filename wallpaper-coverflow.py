#!/usr/bin/env python3
"""
wallpaper-coverflow.py — true 3D coverflow wallpaper picker for Hyprland.

A transparent, frameless webview window (GTK/WebKit backend) that renders
wallpaper-coverflow.html — a free-scrolling, borderless, tilted-in-3D
thumbnail strip — and calls back into wallpaper-picker.sh to actually
apply whatever gets selected.

This file is pure UI glue. All the hyprpaper/hyprlock logic lives in
wallpaper-picker.sh (--list-json to populate the strip, --apply <path>
to commit a choice), so there is exactly one place that knows how to
talk to hyprpaper.

Requires (Arch):
    sudo pacman -S python-pywebview webkit2gtk-4.1 python-gobject

Run directly, or bind to a key in hyprland.conf:
    bind = $mainMod, W, exec, python3 ~/.local/bin/wallpaper-coverflow.py
"""

import json
import os
import subprocess
import sys
import threading
from pathlib import Path
from urllib.parse import quote

import webview

SCRIPT_DIR = Path(__file__).resolve().parent
ENGINE = SCRIPT_DIR / "wallpaper-picker.sh"
HTML_FILE = SCRIPT_DIR / "wallpaper-coverflow.html"

WINDOW_TITLE = "Wallpaper Coverflow"  # matched by the Hyprland windowrule below

# Every call into wallpaper-picker.sh gets a hard ceiling. Without this, any
# stall in the engine (or anything it shells out to) blocks pywebview's
# per-call worker thread indefinitely -- and since that thread isn't a
# daemon thread, Python won't let the process exit even after the window
# is closed. A slow/hung shell call should surface as an error in the UI,
# not as a resident zombie process.
ENGINE_TIMEOUT_SECS = 15

# Grace period given to a normal shutdown (destroying the GTK window) before
# close() forces the issue. See close() below.
FORCE_EXIT_GRACE_SECS = 1.5


class Api:
    """Exposed to JS as window.pywebview.api.<method>(...)."""

    def list_wallpapers(self):
        """Return the wallpaper list (name/path/thumb) as parsed JSON."""
        try:
            result = subprocess.run(
                [str(ENGINE), "--list-json"],
                capture_output=True,
                text=True,
                check=True,
                timeout=ENGINE_TIMEOUT_SECS,
            )
            return json.loads(result.stdout)
        except subprocess.TimeoutExpired:
            return {"error": f"Engine timed out after {ENGINE_TIMEOUT_SECS}s"}
        except subprocess.CalledProcessError as e:
            return {"error": e.stderr.strip() or str(e)}
        except json.JSONDecodeError as e:
            return {"error": f"bad JSON from engine: {e}"}

    def apply_wallpaper(self, path):
        """Apply one wallpaper and report success/failure back to JS."""
        try:
            result = subprocess.run(
                [str(ENGINE), "--apply", path],
                capture_output=True,
                text=True,
                timeout=ENGINE_TIMEOUT_SECS,
            )
            if result.returncode != 0:
                return {"ok": False, "error": result.stderr.strip()}
            return {"ok": True}
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": f"Engine timed out after {ENGINE_TIMEOUT_SECS}s"}
        except Exception as e:  # noqa: BLE001 - surface any failure to the UI
            return {"ok": False, "error": str(e)}

    def close(self):
        # Belt and suspenders: destroying the window is the clean path, but
        # if any other in-flight call is stuck on a non-daemon thread (the
        # exact bug the timeout above guards against), the process would
        # keep running invisibly after the window disappears. Schedule a
        # hard kill shortly after so Esc always actually ends the process,
        # not just the window -- but give the clean path a moment first.
        timer = threading.Timer(FORCE_EXIT_GRACE_SECS, lambda: os._exit(0))
        timer.daemon = True  # must not itself become a reason the process lingers
        timer.start()

        if webview.windows:
            webview.windows[0].destroy()


def main():
    if not ENGINE.exists():
        sys.exit(f"Engine script not found: {ENGINE}")
    if not HTML_FILE.exists():
        sys.exit(f"UI file not found: {HTML_FILE}")

    api = Api()
    # Pass an explicit file:// URL rather than a bare path. A bare local
    # path gets routed through pywebview's internal HTTP server, which
    # would serve this page from http://127.0.0.1:<port>/ — and an
    # http-origin document can't reliably load file:// thumbnail images
    # even with allow_file_access_from_file_urls (that flag only covers
    # file-to-file access). Loading the page itself as file:// keeps
    # everything on the same scheme.
    html_url = "file://" + quote(str(HTML_FILE))
    webview.create_window(
        WINDOW_TITLE,
        html_url,
        js_api=api,
        width=1400,
        height=820,
        frameless=True,
        easy_drag=False,   # the HTML handles its own drag-to-scroll
        transparent=True,
        on_top=True,
        background_color="#1a1b26",  # only the first 6 hex digits are read;
                                      # this just picks the pre-load flash
                                      # color to match the coverflow's palette
    )
    webview.start(gui="gtk", debug=False)


if __name__ == "__main__":
    main()
