#!/bin/bash
# macOS: viam-server runs as root, but TCC denies camera access to root processes.
# To get AVFoundation camera access, we register the binary as a LaunchAgent in
# the console user's session — giving it a proper user bootstrap namespace where
# TCC consent applies. run.sh acts as a supervisor: it bootstraps the agent,
# waits for it to start, then blocks until it exits or receives SIGTERM.
#
# Linux: root is fine, exec the binary directly.

echo "run.sh: running as $(whoami) (uid=$(id -u))"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_BIN="$SCRIPT_DIR/modular-webcam"

# On Linux or when already running as a non-root user, exec directly
if [ "$(uname)" != "Darwin" ] || [ "$(id -u)" -ne 0 ]; then
    exec "$MODULE_BIN" "$@"
fi

CONSOLE_USER=$(stat -f '%Su' /dev/console)

if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
    echo "run.sh: WARNING: no console user found; camera will not work due to TCC restrictions." >&2
    exec "$MODULE_BIN" "$@"
fi

CONSOLE_UID=$(id -u "$CONSOLE_USER")
LABEL="com.viam.modular-webcam.${VIAM_MACHINE_PART_ID:-default}"
DOMAIN="gui/$CONSOLE_UID"
TARGET_BIN="/tmp/viam-modular-webcam-${VIAM_MACHINE_PART_ID:-default}"
PLIST_PATH="/tmp/${LABEL}.plist"

echo "run.sh: console user is $CONSOLE_USER (uid=$CONSOLE_UID)"

# Securely copy binary to /tmp so the console user can traverse the path.
# The module may be installed under /var/root/ (drwx------) which the console
# user cannot enter. Use a stable name to avoid accumulation across restarts.
SAFE_TMP=$(mktemp /tmp/modular-webcam-XXXXXX)
cp "$MODULE_BIN" "$SAFE_TMP"
chmod 755 "$SAFE_TMP"
mv -f "$SAFE_TMP" "$TARGET_BIN"

# XML-escape a string for embedding in the plist
xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    printf '%s' "$s"
}

# Build <string> entries for ProgramArguments (binary + forwarded args)
PROG_ARGS="        <string>$(xml_escape "$TARGET_BIN")</string>"
for arg in "$@"; do
    PROG_ARGS="${PROG_ARGS}"$'\n'"        <string>$(xml_escape "$arg")</string>"
done

# Pass through VIAM_* env vars, skipping the ones that point to /var/root/.viam
# (VIAM_HOME, VIAM_MODULE_ROOT, VIAM_MODULE_DATA) which are inaccessible to the
# console user.
ENV_DICT=""
while IFS= read -r line; do
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
        VIAM_HOME|VIAM_MODULE_ROOT|VIAM_MODULE_DATA) continue ;;
        VIAM_*) ;;
        *) continue ;;
    esac
    ENV_DICT="${ENV_DICT}"$'\n'"        <key>$(xml_escape "$key")</key>"$'\n'"        <string>$(xml_escape "$val")</string>"
done < <(env)

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
${PROG_ARGS}
    </array>
    <key>EnvironmentVariables</key>
    <dict>
${ENV_DICT}
    </dict>
</dict>
</plist>
PLIST

echo "run.sh: wrote plist to $PLIST_PATH"

# Remove any stale agent from a previous run
sudo -u "$CONSOLE_USER" launchctl bootout "$DOMAIN"/"$LABEL" 2>/dev/null || true

# Bootstrap the plist into the console user's GUI session (gui/<uid> is the
# Aqua/WindowServer session domain — the only domain where TCC grants apply)
BOOTSTRAP_OUT=$(sudo -u "$CONSOLE_USER" launchctl bootstrap "$DOMAIN" "$PLIST_PATH" 2>&1)
BOOTSTRAP_RC=$?
echo "run.sh: bootstrap exit=$BOOTSTRAP_RC output=$BOOTSTRAP_OUT"


cleanup() {
    echo "run.sh: cleaning up agent $LABEL"
    sudo -u "$CONSOLE_USER" launchctl bootout "$DOMAIN"/"$LABEL" 2>/dev/null || true
    rm -f "$PLIST_PATH"
}

handle_term() {
    echo "run.sh: received SIGTERM"
    cleanup
    exit 0
}

trap handle_term TERM INT

# Kickstart the agent in the user's session
echo "run.sh: starting agent $LABEL as $CONSOLE_USER"
KICKSTART_OUT=$(sudo -u "$CONSOLE_USER" launchctl kickstart "$DOMAIN"/"$LABEL" 2>&1)
KICKSTART_RC=$?
echo "run.sh: kickstart exit=$KICKSTART_RC output=$KICKSTART_OUT"

# Wait for the agent to obtain a PID (up to 15s)
echo "run.sh: waiting for agent to start..."
AGENT_PID=""
for i in $(seq 1 30); do
    AGENT_PID=$(launchctl print "$DOMAIN"/"$LABEL" 2>/dev/null | awk '/pid =/ {gsub(/[^0-9]/,""); print $3}')
    if [ -n "$AGENT_PID" ]; then
        echo "run.sh: agent is running (pid=$AGENT_PID)"
        break
    fi
    sleep 0.5
done

if [ -z "$AGENT_PID" ]; then
    echo "run.sh: WARNING: agent did not report a PID within 15s" >&2
fi

# Block until the agent process exits
while launchctl print "$DOMAIN"/"$LABEL" 2>/dev/null | grep -q "pid ="; do
    sleep 2
done

# Log final launchctl state to understand why the agent stopped
FINAL_STATE=$(launchctl print "$DOMAIN"/"$LABEL" 2>&1)
echo "run.sh: agent has stopped — final launchctl state:"
echo "$FINAL_STATE"
cleanup
