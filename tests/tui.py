#!/usr/bin/env python3
"""Real terminal input and cross-process lifecycle tests; standard library only."""
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


def run(directory, case, script="tui", argv=()):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 110, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", NVIM_NOTTYFAST="1", WORKSPACE_TEST_DIR=str(directory),
               WORKSPACE_TEST_CASE=case, NVIM_LOG_FILE=str(directory / "nvim.log"),
               XDG_STATE_HOME=str(directory / "state"), XDG_CACHE_HOME=str(directory / "cache"))
    for file in ("stage", "result"):
        (directory / file).unlink(missing_ok=True)
    process = subprocess.Popen([env.get("NVIM_BIN", "nvim"), "-u", "NONE", "-n", "-i", "NONE",
                                "--cmd", f"lua dofile('tests/{script}.lua')", *argv],
                               cwd=ROOT, env=env, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    handled, output = set(), bytearray()
    actions = {"open": b"\x1b[17~", "move": b"\x0e", "long": b"x" * 120, "filter": b"\x15bta-trgt-wrkspc",
               "confirm": b"\r", "reopen": b"\x1b[17~", "cancel": b"\x1b", "command_cancel": b"\x1b"}
    deadline = time.monotonic() + 25
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            stage_file = directory / "stage"
            stage = stage_file.read_text().strip() if stage_file.exists() else ""
            if stage not in handled:
                if stage in actions:
                    os.write(master, actions[stage])
                    handled.add(stage)
                elif stage == "resize":
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 18, 42, 0, 0))
                    os.kill(process.pid, signal.SIGWINCH)
                    handled.add(stage)
        assert process.poll() is not None, "timeout " + case + " " + repr(handled)
        result = (directory / "result").read_text() if (directory / "result").exists() else ""
        assert process.returncode == 0, result + output.decode(errors="replace")[-4000:]
        if script == "tui" or case in {"restore", "late", "default", "directory_arg"}:
            assert result.startswith("PASS"), result + output.decode(errors="replace")[-4000:]
            print(result.strip())
    except Exception:
        print(output.decode(errors="replace")[-4000:])
        raise
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)


def main():
    for case in ("builtin", "selection"):
        if case == "selection" and not (ROOT.parent / "selection-tools.nvim").is_dir():
            continue
        with tempfile.TemporaryDirectory(prefix="workspace-tui-") as temp:
            run(Path(temp), case)
    with tempfile.TemporaryDirectory(prefix="workspace-life-") as temp:
        directory = Path(temp)
        run(directory, "seed", "lifecycle")
        records = list((directory / "store").glob("*.json"))
        assert len(records) == 1, "VimLeavePre did not save"
        original = records[0].read_bytes()
        # JSON must remain valid UTF-8 even when mksession includes bytewise escapes.
        assert json.loads(original)["session_encoding"] == "base64"
        run(directory, "default", "lifecycle")
        run(directory, "restore", "lifecycle")
        run(directory, "directory_arg", "lifecycle", [str(directory / "project")])
        run(directory, "late", "lifecycle")
        run(directory, "delete", "lifecycle")
        assert not records[0].exists(), "deleted workspace was recreated on exit"
        records[0].write_bytes(original)
        run(directory, "blocked", "lifecycle")
        assert records[0].read_bytes() != original, "invalid fixture was not installed"
        from base64 import b64decode
        data = json.loads(records[0].read_bytes())
        assert b64decode(data["session"]) == b"invalid session command\n", "failed restore overwritten on exit"
        print("PASS cross-process exit save, delete suppression, failed-restore protection, private UTF-8 bundles")
    for case in ("suppressed", "stopped", "file_arg"):
        with tempfile.TemporaryDirectory(prefix="workspace-skip-") as temp:
            directory = Path(temp)
            run(directory, case, "lifecycle", [str(ROOT / "README.md")] if case == "file_arg" else [])
            assert not list((directory / "store").glob("*.json")), case + " unexpectedly saved"
    print("PASS automatic save guards: suppressed directories, pause, explicit command-line file")


if __name__ == "__main__":
    main()
