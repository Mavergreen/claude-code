#!/usr/bin/env python
# platform: macOS-only -- times Claude Code going idle in a pseudo-terminal, with no pyte, under Mac OS X 10.9's Python 2.7 or a modern Python 3
#   usage: python ttidle.py MAXSECONDS COMMAND [ARG]...
#          Runs COMMAND in a 120x40 pseudo-terminal, answering the terminal queries Claude Code's UI
#          sends, and samples its CPU every 3 s. Prints "TTIDLE=<seconds> ..." once it stays under 15%
#          for three samples in a row, or "TTIDLE=none ..." if it never does within MAXSECONDS (or
#          exits first). Then kills COMMAND's whole session. With TTIDLE_LOG set, also appends
#          everything COMMAND wrote to its terminal to that file.
from __future__ import print_function

import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

IDLE_PCT, IDLE_HOLD, STEP = 15.0, 3, 3.0
COLS, ROWS = 120, 40
ANSWERS = (
    (b'\x1b[6n', b'\x1b[1;1R'),
    (b'\x1b[c', b'\x1b[?1;2c'),
    (b'\x1b[>0q', b'\x1bP>|xterm(370)\x1b\\'),
    (b'\x1b]11;?', b'\x1b]11;rgb:1e1e/1e1e/1e1e\x1b\\'),
    (b'\x1b[?u', b'\x1b[?0u'),
)


def cputime(pid):
    try:
        out = subprocess.check_output(['ps', '-o', 'cputime=', '-p', str(pid)]).decode().strip()
    except (subprocess.CalledProcessError, OSError):
        return None
    total = 0.0
    for part in out.split(':'):
        total = total * 60 + float(part or 0)
    return total


def pump(fd, seconds, log):
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if not ready:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            return False
        if not data:
            return False
        if log:
            log.write(data)
            log.flush()
        for query, answer in ANSWERS:
            if query in data:
                try:
                    os.write(fd, answer)
                except OSError:
                    pass
    return True


def main():
    if len(sys.argv) < 3:
        sys.stderr.write('usage: ttidle.py MAXSECONDS COMMAND [ARG]...\n')
        return 2
    maxdur = float(sys.argv[1])
    cmd = sys.argv[2:]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        try:
            os.execvp(cmd[0], cmd)
        finally:
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, 0, 0))
    log = open(os.environ['TTIDLE_LOG'], 'ab') if os.environ.get('TTIDLE_LOG') else None
    alive = pump(fd, STEP, log)
    watched = STEP
    prev = cputime(pid) or 0.0
    idle_run, ttidle, peak = 0, None, 0.0
    while alive and watched < maxdur:
        alive = pump(fd, STEP, log)
        watched += STEP
        cur = cputime(pid)
        if cur is None:
            break
        pct = (cur - prev) / STEP * 100
        prev = cur
        peak = max(peak, pct)
        idle_run = idle_run + 1 if pct < IDLE_PCT else 0
        if idle_run >= IDLE_HOLD:
            ttidle = watched - (IDLE_HOLD - 1) * STEP
            break
    total = cputime(pid)
    print('TTIDLE=%s maxcpu=%.0f totalcpu=%.1fs watched=%ds'
          % ('%d' % ttidle if ttidle is not None else 'none', peak, total or 0.0, watched))
    sys.stdout.flush()
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError as e:
        if e.errno != errno.ESRCH:
            raise
    os.waitpid(pid, 0)
    return 0


if __name__ == '__main__':
    sys.exit(main())
