import os
import sys
import winreg
import asyncio
import threading
import tkinter as tk

import pystray
from PIL import Image, ImageDraw
from pycaw.pycaw import AudioUtilities
from winrt.windows.media.control import (
    GlobalSystemMediaTransportControlsSessionManager
)

PLAYING = 4
PAUSED = 5
ACTIVE_AUDIO_SESSION = 1

monitoring_paused = threading.Event()
exit_requested = threading.Event()
spotify_paused_by_us = False


# Windows startup configuration
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
SETTINGS_KEY = r"Software\SpotifyMediaController"
APP_NAME = "SpotifyMediaController"


def is_startup_enabled():
    """Check whether the app launches with Windows."""

    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER, RUN_KEY
        ) as key:
            winreg.QueryValueEx(key, APP_NAME)
        return True
    except FileNotFoundError:
        return False


def set_startup_enabled(enabled):
    """Enable or disable automatic startup for this user."""

    with winreg.CreateKey(
        winreg.HKEY_CURRENT_USER, RUN_KEY
    ) as key:

        if enabled:
            if getattr(sys, "frozen", False):
                # Running as a packaged EXE.
                command = f'"{sys.executable}" --startup'
            else:
                
                # Run Python without opening a console window.
                pythonw = os.path.join(
                    os.path.dirname(sys.executable),
                    "pythonw.exe",
                )
                script = os.path.abspath(__file__)
                command = (
                    f'"{pythonw}" "{script}" --startup'
                )


            winreg.SetValueEx(
                key, APP_NAME, 0, winreg.REG_SZ, command
            )

        else:
            try:
                winreg.DeleteValue(key, APP_NAME)
            except FileNotFoundError:
                pass

    # Remember that the user has configured this setting.
    with winreg.CreateKey(
        winreg.HKEY_CURRENT_USER, SETTINGS_KEY
    ) as key:
        winreg.SetValueEx(
            key, "StartupConfigured", 0,
            winreg.REG_DWORD, 1
        )


def initialize_startup():
    """Enable startup by default on the first launch only."""

    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER, SETTINGS_KEY
        ) as key:
            winreg.QueryValueEx(key, "StartupConfigured")
            already_configured = True

    except FileNotFoundError:
        already_configured = False

    if not already_configured:
        set_startup_enabled(True)


def toggle_startup(icon, item):
    """Toggle the Start with Windows setting."""

    enabled = not is_startup_enabled()

    try:
        set_startup_enabled(enabled)

        message = (
            "Start with Windows enabled."
            if enabled
            else "Start with Windows disabled."
        )

        icon.notify(message, "Spotify Media Controller")

    except OSError as error:
        icon.notify(
            f"Could not change startup setting: {error}",
            "Spotify Media Controller",
        )

def other_audio_playing():
    """Detect audio from apps such as VLC."""

    browser_processes = {
        "chrome.exe",
        "brave.exe",
        "msedge.exe",
        "firefox.exe",
        "opera.exe",
        "vivaldi.exe",
        "browser.exe",
    }

    try:
        for session in AudioUtilities.GetAllSessions():
            process = session.Process

            if process is None:
                continue

            app = process.name().lower()

            if "spotify" in app:
                continue

            # Browser playback is detected through Windows Media API.
            if app in browser_processes:
                continue

            if session.State == ACTIVE_AUDIO_SESSION:
                return True

    except Exception as error:
        print("Audio detection error:", error)

    return False


def show_welcome_window():
    """Show a welcome window without stopping the controller."""

    window = tk.Tk()
    window.title("Spotify Media Controller")
    window.configure(bg="#171b20")
    window.resizable(False, False)

    # Center the window on the screen.
    width = 440
    height = 320
    screen_width = window.winfo_screenwidth()
    screen_height = window.winfo_screenheight()

    x = (screen_width - width) // 2
    y = (screen_height - height) // 2

    window.geometry(f"{width}x{height}+{x}+{y}")

    # App title.
    tk.Label(
        window,
        text="♫  Spotify Media Controller",
        font=("Segoe UI", 17, "bold"),
        fg="#1DB954",
        bg="#171b20",
    ).pack(pady=(25, 18))

    # Welcome message.
    message = (
        "Spotify Media Controller is running!\n"
        "Find its icon near the Windows clock.\n"
        "Use the tray menu to pause, resume, or exit.\n"
        "\n"
        "You can close this window now...\n"
        "\n"
        "Enjoy ;)"
    )

    tk.Label(
        window,
        text=message,
        font=("Segoe UI", 10),
        fg="#E6E6E6",
        bg="#171b20",
        justify="center",
        wraplength=400,
    ).pack(padx=18, pady=(0, 20))

    # Dismiss the window without stopping monitoring.
    tk.Button(
        window,
        text="Got it!",
        font=("Segoe UI", 10, "bold"),
        fg="#101510",
        bg="#1DB954",
        activebackground="#18a349",
        activeforeground="#FFFFFF",
        relief="flat",
        cursor="hand2",
        padx=28,
        pady=7,
        command=window.destroy,
    ).pack()

    window.mainloop()

def create_icon_image():
    """Create a simple green music icon."""

    image = Image.new("RGB", (64, 64), "#20252b")
    draw = ImageDraw.Draw(image)

    draw.ellipse((8, 8, 56, 56), fill="#1DB954")
    draw.line((36, 18, 36, 42), fill="white", width=5)
    draw.line((36, 18, 47, 15), fill="white", width=5)
    draw.ellipse((24, 37, 37, 49), fill="white")

    return image


def pause_monitoring(icon, item):
    monitoring_paused.set()
    print("Monitoring paused.")


def resume_monitoring(icon, item):
    monitoring_paused.clear()
    print("Monitoring resumed.")


def exit_controller(icon, item):
    exit_requested.set()
    icon.stop()



def create_tray_icon():
    menu = pystray.Menu(
        pystray.MenuItem(
            "Pause monitoring", pause_monitoring
        ),
        pystray.MenuItem(
            "Resume monitoring", resume_monitoring
        ),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem(
            "Start with Windows",
            toggle_startup,
            checked=lambda item: is_startup_enabled(),
        ),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem(
            "Exit controller", exit_controller
        ),
    )

    return pystray.Icon(
        "SpotifyMediaController",
        create_icon_image(),
        "Spotify Media Controller",
        menu,
    )


    return pystray.Icon(
        "SpotifyMediaController",
        create_icon_image(),
        "Spotify Media Controller",
        menu,
    )



async def main():
    global spotify_paused_by_us

    try:
        initialize_startup()
    except OSError as error:
        print("Could not configure Windows startup:", error)

    manager = (

        await GlobalSystemMediaTransportControlsSessionManager
        .request_async()
    )

    icon = create_tray_icon()

    # Run the tray icon separately from the monitoring loop.
    tray_thread = threading.Thread(
        target=icon.run,
        daemon=True,
    )
    
    tray_thread.start()

    if "--startup" not in sys.argv:
        welcome_thread = threading.Thread(
            target=show_welcome_window,
            daemon=True,
        )
        welcome_thread.start()


    print("Spotify Media Controller is running!")
    print("Find its icon near the Windows clock.")
    print("Use the tray menu to pause, resume, or exit.")

    try:
        while not exit_requested.is_set():

            if monitoring_paused.is_set():
                await asyncio.sleep(0.2)
                continue

            sessions = manager.get_sessions()
            spotify = None
            other_media_playing = other_audio_playing()

            for session in sessions:
                app = session.source_app_user_model_id.lower()
                status = session.get_playback_info().playback_status

                if "spotify" in app:
                    spotify = session

                elif status == PLAYING:
                    other_media_playing = True

            if spotify is not None:
                spotify_status = (
                    spotify.get_playback_info().playback_status
                )

                if other_media_playing:
                    if spotify_status == PLAYING:
                        result = await spotify.try_pause_async()

                        if result:
                            spotify_paused_by_us = True
                            print(
                                "Other media playing -> Spotify paused"
                            )

                elif spotify_paused_by_us:
                    if spotify_status == PAUSED:
                        result = await spotify.try_play_async()

                        if result:
                            print(
                                "Other media stopped -> Spotify resumed"
                            )

                    spotify_paused_by_us = False

            await asyncio.sleep(0.2)

    finally:
        # If we paused Spotify, try to restore playback on exit.
        if spotify_paused_by_us:
            for session in manager.get_sessions():
                app = session.source_app_user_model_id.lower()

                if "spotify" in app:
                    if (
                        session.get_playback_info().playback_status
                        == PAUSED
                    ):
                        await session.try_play_async()
                    break

        icon.stop()
        print("Controller stopped.")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        exit_requested.set()
