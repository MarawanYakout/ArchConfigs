"""
ManimGL live workflow for Sublime Text + Terminus.

    ctrl+shift+r  play the scene under the cursor in full, then open the
                  IPython shell. If a session is already open, re-run in the
                  same window instead of opening a new one.
    ctrl+p        play the last thing again (one scene, or all of them) in the
                  same window. While something is playing, stop it instead.
                  With no session open, same as ctrl+shift+r.
    ctrl+alt+p    continue a play that ctrl+p stopped, from where it stopped
    ctrl+shift+p  play the last thing over and over, reloading the file each
                  round; press again to stop. With no session open, loops the
                  scene under the cursor.
    ctrl+a        play every scene of the file, in order, in the same window
    ctrl+r        replay the selected code (or the current line) in the live
                  scene with checkpoint_paste(). A selection that starts at a
                  block's `# comment` line jumps back to where that block
                  started during the run, then plays it.
    ctrl+alt+r    same, without animating
    ctrl+e        export the scene under the cursor at 480p to videos/480p/
    ctrl+shift+e  export it at 4K (3840x2160), 60 fps to videos/4k/
    ctrl+shift+q  end the session (closes the window)
    ctrl+t        show/hide the ManimGL terminal, or a plain terminal if no
                  session is running

Any other shortcut pressed while something is still playing stops it first,
so it takes effect right away instead of waiting its turn.

Scenes run through manimgl_live.py, found next to the nearest .venv-gl folder
above the file being edited. Exports run plain manimgl in panels of their own,
so the live session keeps going. The keymap only uses these keys in Python
files of such a project (context key "manim_gl_project"), so they keep their
usual meaning everywhere else.
"""
import os
import re

import sublime
import sublime_plugin

PANEL = "manimgl"
VENV_DIR = ".venv-gl"
LAUNCHER = "manimgl_live.py"
CLASS_RE = re.compile(r"^class\s+(\w+)\s*[(:]")
# Anything starting at column 0 (code or comment) is outside the class above it
TOP_LEVEL_RE = re.compile(r"^\S")
# What the launcher and IPython print, to tell what the session is doing
PROMPT_RE = re.compile(r"^In \[\d+\]:")
IDLE_PROMPT_RE = re.compile(r"^In \[\d+\]:\s*$")
LOOPING_RE = re.compile(r"^Looping ")
STOPPED_RE = re.compile(r"Stopped\.")
# manimgl flags for each export quality, written to videos/<quality>/
EXPORTS = {
    "480p": ["-l"],
    "1080p": ["--hd", "--fps", "60"],
    "4k": ["--uhd", "--fps", "60"],
}


def find_project_root(file_path):
    folder = os.path.dirname(file_path)
    while True:
        if os.path.isfile(os.path.join(folder, VENV_DIR, "bin", "python")):
            return folder
        parent = os.path.dirname(folder)
        if parent == folder:
            return None
        folder = parent


def find_scene(view, row):
    """Name of the class whose body contains row, or None."""
    for r in range(row, -1, -1):
        line = view.substr(view.line(view.text_point(r, 0)))
        match = CLASS_RE.match(line)
        if match:
            return match.group(1)
        if TOP_LEVEL_RE.match(line):
            return None
    return None


def all_classes(view):
    lines = view.substr(sublime.Region(0, view.size())).splitlines()
    return [m.group(1) for m in map(CLASS_RE.match, lines) if m]


def with_scene(view, callback, placeholder):
    """
    Call back with the scene the cursor is in, or with one picked from the
    file's classes when the cursor is outside every class.
    """
    scene_name = find_scene(view, view.rowcol(view.sel()[0].begin())[0])
    if scene_name is not None:
        callback(scene_name)
        return

    names = all_classes(view)
    if not names:
        sublime.status_message("ManimGL: no classes in this file")
        return

    def on_done(index):
        if index >= 0:
            callback(names[index])

    view.window().show_quick_panel(names, on_done, placeholder=placeholder)


def live_panel(window, name=PANEL):
    """The terminal panel if its process is still running."""
    panel = window.find_output_panel(name)
    if panel is None or panel.settings().get("terminus_view.finished"):
        return None
    return panel


def close_panel(window, name=PANEL):
    panel = window.find_output_panel(name)
    if panel is not None:
        panel.run_command("terminus_close")


def panel_lines(panel, count=200):
    """The last non-blank lines of the panel."""
    first_row = max(0, panel.rowcol(panel.size())[0] - count)
    text = panel.substr(sublime.Region(panel.text_point(first_row, 0), panel.size()))
    return [line.rstrip() for line in text.splitlines() if line.strip()]


def is_looping(panel):
    """Whether the launcher is playing in a loop, going by what it printed last."""
    for line in reversed(panel_lines(panel)):
        if LOOPING_RE.match(line):
            return True
        if PROMPT_RE.match(line) or STOPPED_RE.search(line):
            return False
    return False


def is_idle(panel):
    lines = panel_lines(panel)
    return bool(lines) and IDLE_PROMPT_RE.match(lines[-1]) is not None


def venv_env(root):
    venv = os.path.join(root, VENV_DIR)
    path = os.pathsep.join([os.path.join(venv, "bin"), os.environ.get("PATH", "")])
    return {"VIRTUAL_ENV": venv, "PATH": path}


def send(window, string):
    window.run_command("terminus_send_string", {"string": string, "tag": PANEL})


def send_to_shell(window, code):
    """
    Type a line of code into the shell. Whatever the shell is busy with (a
    scene playing, a loop) is stopped with ctrl+c first and the code typed once
    the prompt is back, so it runs right away instead of queueing behind it.
    Pressing again while waiting replaces the code rather than adding to it.
    """
    panel = live_panel(window)
    if panel is None:
        return
    waiting = window.id() in pending_code
    pending_code[window.id()] = code
    if waiting:
        return
    if not is_idle(panel):
        send(window, "\x03")
    send_when_idle(window)


# Code waiting for the shell's prompt, by window id
pending_code = {}


def send_when_idle(window, tries=100):
    """Type the pending code once the shell shows an empty prompt, checking every 0.1 s for 10 s."""
    panel = live_panel(window)
    if panel is not None and is_idle(panel):
        send(window, pending_code.pop(window.id()) + "\n")
    elif panel is not None and tries > 0:
        sublime.set_timeout(lambda: send_when_idle(window, tries - 1), 100)
    else:
        pending_code.pop(window.id(), None)
        if panel is not None:
            sublime.status_message("ManimGL: the shell didn't come back, press ctrl+c in the panel")


def start_session(window, root, args):
    """Open the launcher in the ManimGL panel, replacing a finished one."""
    close_panel(window)
    python = os.path.join(root, VENV_DIR, "bin", "python")
    window.run_command("terminus_open", {
        "cmd": [python, os.path.join(root, LAUNCHER)] + args,
        "cwd": root,
        "env": venv_env(root),
        "title": "ManimGL",
        "show_in_panel": True,
        "panel_name": PANEL,
        "tag": PANEL,
        "auto_close": False,
        "focus": False,
    })


def prepare(view):
    """(window, project root, file path) with the file saved, or None."""
    window = view.window()
    file_path = view.file_name()
    if window is None or file_path is None:
        sublime.status_message("ManimGL: save the file first")
        return None

    root = find_project_root(file_path)
    if root is None or not os.path.isfile(os.path.join(root, LAUNCHER)):
        sublime.status_message("ManimGL: no {} with {} found above this file".format(VENV_DIR, LAUNCHER))
        return None

    if view.is_dirty():
        view.run_command("save")
    return window, root, file_path


class ManimRunSceneCommand(sublime_plugin.TextCommand):
    """
    mode "run" plays the scene under the cursor, "again" plays the last thing
    again (or stops what is playing), "loop" plays it over and over (or stops
    the loop), "resume" continues a stopped play from where it stopped. With no
    session open, the first three start one on the scene under the cursor.
    """

    def run(self, edit, mode="run"):
        prepared = prepare(self.view)
        if prepared is None:
            return
        window, root, file_path = prepared

        panel = live_panel(window)
        if mode == "resume":
            if panel is None:
                sublime.status_message("ManimGL: nothing to continue, no session running")
            else:
                send_to_shell(window, "resume()")
            return
        if panel is not None and mode == "loop":
            if is_looping(panel):
                send(window, "\x03")
            else:
                send_to_shell(window, "loop()")
            return
        if panel is not None and mode == "again":
            if is_idle(panel):
                send(window, "reload()\n")
            else:
                send(window, "\x03")  # Something is playing: this press stops it
            return

        extra = ["--loop"] if mode == "loop" else []

        def run_scene(scene_name):
            if live_panel(window) is not None:
                # Same window, same shell: just re-run
                send_to_shell(window, "run_scene({!r}, {!r})".format(scene_name, file_path))
            else:
                start_session(window, root, [file_path, scene_name] + extra)

        with_scene(self.view, run_scene, "Scene to run")


class ManimPlayAllCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        prepared = prepare(self.view)
        if prepared is None:
            return
        window, root, file_path = prepared

        if live_panel(window) is not None:
            send_to_shell(window, "run_all({!r})".format(file_path))
        else:
            start_session(window, root, [file_path, "-a"])


class ManimCheckpointPasteCommand(sublime_plugin.TextCommand):
    def run(self, edit, skip=False):
        view = self.view
        window = view.window()
        if window is None:
            return
        if live_panel(window) is None:
            sublime.status_message("ManimGL: no scene running, press ctrl+shift+r first")
            return

        # Whole lines only, so textwrap.dedent in checkpoint_paste sees
        # consistent indentation and the leading `# comment` stays first.
        text = "\n".join(view.substr(view.line(region)) for region in view.sel())
        if not text.strip():
            return

        sublime.set_clipboard(text)
        send_to_shell(window, "checkpoint_paste(skip=True)" if skip else "checkpoint_paste()")


class ManimExportCommand(sublime_plugin.TextCommand):
    """Render the scene under the cursor to videos/<quality>/<Scene>.mp4."""

    def run(self, edit, quality="480p"):
        prepared = prepare(self.view)
        if prepared is None:
            return
        window, root, file_path = prepared
        panel_name = "manimgl-" + quality

        def export(scene_name):
            if live_panel(window, panel_name) is not None:
                sublime.status_message("ManimGL: the {} export is still running".format(quality))
                window.run_command("show_panel", {"panel": "output." + panel_name})
                return
            close_panel(window, panel_name)
            manimgl = os.path.join(root, VENV_DIR, "bin", "manimgl")
            window.run_command("terminus_open", {
                "cmd": [manimgl, file_path, scene_name, "-w", "--video_dir", os.path.join("videos", quality)]
                + EXPORTS[quality],
                "cwd": root,
                "env": venv_env(root),
                "title": "Export " + quality,
                "show_in_panel": True,
                "panel_name": panel_name,
                "tag": panel_name,
                "auto_close": False,
                "focus": False,
            })

        with_scene(self.view, export, "Scene to export at " + quality)


class ManimExitCommand(sublime_plugin.WindowCommand):
    def run(self):
        close_panel(self.window)


class ManimTogglePanelCommand(sublime_plugin.WindowCommand):
    def run(self):
        window = self.window
        if window.find_output_panel(PANEL) is not None:
            window.run_command("toggle_terminus_panel", {"panel_name": PANEL, "hide_active": True})
            return

        # No ManimGL session: a plain terminal, with .venv-gl active when found
        args = {"hide_active": True}
        view = window.active_view()
        root = find_project_root(view.file_name()) if view and view.file_name() else None
        if root is not None:
            args.update(cwd=root, env=venv_env(root))
        window.run_command("toggle_terminus_panel", args)


class ManimProjectContext(sublime_plugin.EventListener):
    """Keymap context "manim_gl_project": the file sits in a project with .venv-gl."""

    def on_query_context(self, view, key, operator, operand, match_all):
        if key != "manim_gl_project":
            return None
        file_path = view.file_name()
        value = bool(file_path) and find_project_root(file_path) is not None
        if operator == sublime.OP_EQUAL:
            return value == operand
        if operator == sublime.OP_NOT_EQUAL:
            return value != operand
        return None
