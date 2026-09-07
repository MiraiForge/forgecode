#!/usr/bin/env python3
"""Smoke test for the fish plugin: drives a real interactive fish under a pty.

The generated plugin (`forge fish plugin`) and theme are sourced into
`fish --no-config -i` with `FORGE_BIN` pointing at scripts/fixtures/fake-forge,
which logs its argv/environment and prints canned output. Each step types
keystrokes and waits for expected output, so the Enter/Tab bindings,
dispatcher, session state and terminal-context export are exercised end to
end without credentials or network access.

Usage: python3 scripts/test-fish-plugin.py [path/to/forge]
"""
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ANSI = re.compile(
    r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Za-z0-9]|\x1b[=>]|\r"
)


def run_steps(argv, env, steps, prompt=r"> $", startup_timeout=15):
    """Runs `argv` in a pty, feeding `steps` ({send, wait, timeout}) in order."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(argv[0], argv, env)

    buf = b""
    transcript = []

    def read_until(pattern, timeout):
        nonlocal buf
        deadline = time.time() + timeout
        rx = re.compile(pattern, re.S)
        while time.time() < deadline:
            clean = ANSI.sub("", buf.decode("utf-8", "replace"))
            if rx.search(clean):
                return True, clean
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                # Answer fish's Primary Device Attribute query so it does not
                # wait for terminal capabilities before the first prompt.
                if b"\x1b[c" in data:
                    os.write(fd, b"\x1b[?1;2c")
                buf += data
        return False, ANSI.sub("", buf.decode("utf-8", "replace"))

    ok, out = read_until(prompt, startup_timeout)
    transcript.append(out)
    buf = b""
    failed = None
    for index, step in enumerate(steps):
        os.write(fd, step["send"].encode())
        ok, out = read_until(step["wait"], step.get("timeout", 10))
        transcript.append(f"--- step {index} send={step['send']!r} wait={step['wait']!r} ok={ok}\n{out}")
        buf = b""
        if not ok:
            failed = index
            break

    try:
        os.write(fd, b"exit\n")
        time.sleep(0.2)
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass
    return failed, transcript


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    forge = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "target", "debug", "forge")
    if not os.access(forge, os.X_OK):
        print(f"forge binary not found at {forge}; run: cargo build -p forge_main")
        return 1
    if not shutil.which("fish"):
        print("fish is not installed")
        return 1

    version = subprocess.run(["fish", "--version"], capture_output=True, text=True, check=True).stdout.strip()
    fish_major = int(re.search(r"version (\d+)", version).group(1))
    print(version)

    work = tempfile.mkdtemp(prefix="forge-fish-test-")
    home = os.path.join(work, "home")
    os.makedirs(os.path.join(home, ".config"), exist_ok=True)
    plugin = os.path.join(work, "plugin.fish")
    theme = os.path.join(work, "theme.fish")
    with open(plugin, "w") as out:
        subprocess.run([forge, "fish", "plugin"], stdin=subprocess.DEVNULL, stdout=out, check=True)
    with open(theme, "w") as out:
        subprocess.run([forge, "fish", "theme"], stdin=subprocess.DEVNULL, stdout=out, check=True)
    for script in (plugin, theme):
        subprocess.run(["fish", "--no-execute", script], check=True)
    print("generated plugin and theme parse")

    log = os.path.join(work, "fake-forge.log")
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": home,
        "XDG_CONFIG_HOME": os.path.join(home, ".config"),
        "XDG_DATA_HOME": os.path.join(work, "data"),
        "TERM": "xterm-256color",
        "PAGER": "cat",
        "FORGE_BIN": os.path.join(root, "scripts", "fixtures", "fake-forge"),
        "FAKE_FORGE_LOG": log,
    }
    steps = [
        {"send": f"source {plugin}; source {theme}; echo loaded=$_FORGE_PLUGIN_LOADED\n", "wait": r"loaded=\d+"},
        {"send": ":sage\n", "wait": r"SAGE.*is now the active agent"},
        {"send": ": hello world\n", "wait": r"PROMPT-SENT: hello world \(agent=sage\)"},
        {"send": "false\n", "wait": r"false"},
        {"send": "echo ctx=$_FORGE_TERM_COMMANDS codes=$_FORGE_TERM_EXIT_CODES\n", "wait": r"ctx=.*codes=.*1"},
        {"send": ": check ctx\n", "wait": r"PROMPT-SENT: check ctx"},
        {"send": "@src\t", "wait": r"@\[src/main.rs\]"},
        {"send": "\x15:sa\t", "wait": r":sage "},
        {"send": "\x15:nope\n", "wait": r"Command 'nope' not found"},
        {"send": ":mycmd do it\n", "wait": r"CUSTOM-EXECUTED"},
        {"send": ":ask why\n", "wait": r"PROMPT-SENT: why \(agent=sage\)"},
        {"send": ":m\n", "wait": r"Session model set to gpt-9 \(provider: openai\)"},
        {"send": ":re\n", "wait": r"Session reasoning effort set to high"},
        {"send": ": with overrides\n", "wait": r"PROMPT-SENT: with overrides"},
        {"send": ":cr\n", "wait": r"Session overrides cleared"},
        {"send": ":s list files\n", "wait": r"ls -la"},
        {"send": "\x15:c\n", "wait": r"Switched to conversation aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"},
        {"send": ":c -\n", "wait": r"Switched to conversation 11111111-2222"},
        {"send": "eval ':sage'\n", "wait": r"SAGE.*is now the active agent"},
        {"send": "fish_vi_key_bindings; echo vi=$fish_key_bindings\n", "wait": r"vi=fish_vi_key_bindings"},
        {"send": ":muse\n", "wait": r"MUSE.*is now the active agent"},
    ]
    if fish_major >= 4:
        steps.append({"send": "history search --prefix ':' | cat\n", "wait": r": hello world"})
    steps.append({"send": "echo final=ok\n", "wait": r"final=ok"})

    failed, transcript = run_steps(["fish", "--no-config", "-i"], env, steps)
    if failed is not None:
        print("\n".join(transcript))
        print(f"\nFAILED at step {failed}")
        return 1

    with open(log) as handle:
        log_text = handle.read()
    checks = {
        "prompt carries agent, conversation and terminal context": re.search(
            r"ARGV: \[--agent\] \[sage\] \[-p\] \[check ctx\] \[--cid\] \[11111111-2222-3333-4444-555555555555\]\n"
            r"ENV _FORGE_TERM_COMMANDS=.*false.*\nENV _FORGE_TERM_EXIT_CODES=.*1",
            log_text,
        ),
        "session overrides are exported": re.search(
            r"ARGV: \[--agent\] \[sage\] \[-p\] \[with overrides\].*\n"
            r"ENV FORGE_SESSION__MODEL_ID=gpt-9\nENV FORGE_SESSION__PROVIDER_ID=openai\nENV FORGE_REASONING__EFFORT=high",
            log_text,
        ),
        "custom command runs through cmd execute": "[cmd] [execute] [--cid] [11111111-2222-3333-4444-555555555555] [mycmd] [do it]" in log_text,
        "right prompt is rendered by forge": "ARGV: [fish] [rprompt]" in log_text,
    }
    for name, ok in checks.items():
        print(f"{'ok' if ok else 'FAIL'}: {name}")
    if not all(checks.values()):
        print(log_text)
        return 1

    print(f"all {len(steps)} steps passed")
    shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
