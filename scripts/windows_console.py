#!/usr/bin/env python3
"""Run a program attached to this process's console and report the outcome.

scripts/test.py starts this script in a new hidden console. It is the Windows
counterpart of the POSIX PTY runner: the program reads its input from a real
console, so it can change the console mode, and this script checks that the
mode is put back once the program has exited.

The request is a JSON object in the first argument, and the result is a JSON
object on standard output.
"""
from __future__ import annotations

import ctypes
import json
import signal
import subprocess
import sys
import threading
import time
from ctypes import wintypes

KEY_EVENT = 0x0001
GENERIC_READ_WRITE = 0x80000000 | 0x40000000
FILE_SHARE_READ_WRITE = 0x00000001 | 0x00000002
OPEN_EXISTING = 3


class KeyEventRecord(ctypes.Structure):
    _fields_ = [
        ("bKeyDown", wintypes.BOOL),
        ("wRepeatCount", wintypes.WORD),
        ("wVirtualKeyCode", wintypes.WORD),
        ("wVirtualScanCode", wintypes.WORD),
        ("UnicodeChar", wintypes.WCHAR),
        ("dwControlKeyState", wintypes.DWORD),
    ]


class InputRecord(ctypes.Structure):
    _fields_ = [("EventType", wintypes.WORD), ("KeyEvent", KeyEventRecord)]


class Console:
    def __init__(self) -> None:
        self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel32.CreateFileW.restype = wintypes.HANDLE
        self.kernel32.CreateFileW.argtypes = [
            wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
            wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE,
        ]
        self.kernel32.GetConsoleMode.argtypes = [wintypes.HANDLE, wintypes.LPDWORD]
        self.kernel32.WriteConsoleInputW.argtypes = [
            wintypes.HANDLE, ctypes.POINTER(InputRecord), wintypes.DWORD, wintypes.LPDWORD,
        ]
        self.handle = self.kernel32.CreateFileW(
            "CONIN$", GENERIC_READ_WRITE, FILE_SHARE_READ_WRITE, None, OPEN_EXISTING, 0, None,
        )
        if self.handle == wintypes.HANDLE(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())

    def mode(self) -> int:
        mode = wintypes.DWORD()
        if not self.kernel32.GetConsoleMode(self.handle, ctypes.byref(mode)):
            raise ctypes.WinError(ctypes.get_last_error())
        return mode.value

    def press_key(self, character: str) -> None:
        records = (InputRecord * 2)()
        for record, key_down in zip(records, (True, False)):
            record.EventType = KEY_EVENT
            record.KeyEvent.bKeyDown = key_down
            record.KeyEvent.wRepeatCount = 1
            record.KeyEvent.UnicodeChar = character
        written = wintypes.DWORD()
        if not self.kernel32.WriteConsoleInputW(self.handle, records, 2, ctypes.byref(written)):
            raise ctypes.WinError(ctypes.get_last_error())


def run(request: dict[str, object]) -> dict[str, object]:
    args = [str(arg) for arg in request["args"]]
    deadline = time.monotonic() + float(request["timeout"])
    console = Console()
    # CTRL_C_EVENT broadcasts to the attached console. Keep this helper alive;
    # Signal.catch! re-enables Ctrl-C in the child after CREATE_NEW_PROCESS_GROUP.
    ctrl_handler_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.DWORD)
    ctrl_handler = ctrl_handler_type(lambda event: event == 0)
    console.kernel32.SetConsoleCtrlHandler.argtypes = [ctrl_handler_type, wintypes.BOOL]
    if not console.kernel32.SetConsoleCtrlHandler(ctrl_handler, True):
        raise ctypes.WinError(ctypes.get_last_error())
    initial_mode = console.mode()
    output = bytearray()
    with open("CONIN$", "rb", buffering=0) as console_input:
        process = subprocess.Popen(
            args, stdin=console_input, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            # Its own group, so a console event can be sent to it alone.
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
        )
    reader = threading.Thread(target=lambda: output.extend(process.stdout.read()), daemon=True)
    reader.start()
    try:
        if request["await_raw_mode"]:
            while console.mode() == initial_mode:
                if process.poll() is not None or time.monotonic() >= deadline:
                    return {"error": "Terminal never changed mode"}
                time.sleep(0.01)
        else:
            time.sleep(0.25)
        for character in str(request["stdin"]):
            console.press_key(character)
            time.sleep(float(request["input_delay"]))
        if request["send_signal"]:
            if request["send_signal"] == "SIGINT":
                if not console.kernel32.GenerateConsoleCtrlEvent(signal.CTRL_C_EVENT, 0):
                    raise ctypes.WinError(ctypes.get_last_error())
            else:
                process.send_signal(signal.CTRL_BREAK_EVENT)
        try:
            exit_code = process.wait(timeout=max(0.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            return {"error": f"Timed out after {request['timeout']}s"}
        reader.join()
        if console.mode() != initial_mode:
            return {"error": "Terminal mode was not restored"}
        return {"exit_code": exit_code, "output": output.decode("utf-8", errors="replace")}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


if __name__ == "__main__":
    try:
        result = run(json.loads(sys.argv[1]))
    except Exception as error:  # The caller cannot see this console.
        result = {"error": f"{type(error).__name__}: {error}"}
    print(json.dumps(result))
