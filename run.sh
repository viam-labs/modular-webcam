#!/bin/bash
# Entrypoint for the modular-webcam module.
#
# On macOS, when running as root under a launchd daemon (i.e. viam-server was
# launched by launchd), delegates to run_darwin_tcc.sh which re-launches the
# binary as a LaunchAgent in the console user's GUI session for TCC camera access.
# In all other cases, exec the binary directly.

echo "run.sh: running as $(whoami) (uid=$(id -u))"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_BIN="$SCRIPT_DIR/modular-webcam"

# On macOS, when running as root without SUDO_USER, we're in a launchd daemon context
# (viam-server launched by launchd). A manual `sudo` invocation sets SUDO_USER, which
# distinguishes it from launchd. In the daemon context, TCC denies camera access to
# root, so we delegate to run_darwin_tcc.sh to re-launch under the console user's GUI session.
if [ "$(uname)" = "Darwin" ] && [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo "run.sh: detected launchd daemon context, delegating to run_darwin_tcc.sh"
    exec "$SCRIPT_DIR/run_darwin_tcc.sh" "$MODULE_BIN" "$@"
elif [ "$(uname)" = "Darwin" ]; then
    echo "run.sh: darwin but not in launchd context, executing binary directly"
fi

exec "$MODULE_BIN" "$@"
