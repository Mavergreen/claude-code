#!/bin/sh
# platform: macOS-only -- reads the CPU features Mac OS X 10.9's sysctl reports
if [ -z "$ROOT" ]; then
  case " $(sysctl -n machdep.cpu.features 2>/dev/null) " in
    *" AVX1.0 "*) : ;;
    *) echo "Claude Code for Mavericks needs a CPU with AVX (AVX1.0); this Mac's CPU does not have it." >&2; false ;;
  esac
fi
