#!/bin/bash
set -e

# Get the project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Project Root: $PROJECT_ROOT"

# Check if XQuartz is likely installed
if [ ! -d "/Applications/Utilities/XQuartz.app" ] && [ ! -d "/Applications/XQuartz.app" ]; then
    echo "WARNING: XQuartz does not seem to be installed in standard locations."
    echo "Please install it: brew install --cask xquartz"
    echo "And RESTART your Mac (or at least log out/in) after installation."
    echo "----------------------------------------------------------------"
fi

echo "Preparing to run with X11 forwarding..."
echo "IMPORTANT: Ensure you have run 'xhost +localhost' in your terminal."

# Run the app
# We assume the architecture is arm64 implies 'linux/arm64' path, correcting if strictly x64 host.
# But for now we just try the path we saw in the logs.
ARTIFACT_PATH="example/chat_app/build/linux/arm64/release/bundle/llama_dart_chat_example"
if [ ! -f "$PROJECT_ROOT/$ARTIFACT_PATH" ]; then
    # Fallback to x64 path if arm64 doesn't exist (e.g. if user is actually on Intel)
    ARTIFACT_PATH="example/chat_app/build/linux/x64/release/bundle/llama_dart_chat_example"
fi

if [ ! -f "$PROJECT_ROOT/$ARTIFACT_PATH" ]; then
    echo "ERROR: Could not find binary at $ARTIFACT_PATH"
    echo "Please run build_linux_docker.sh first."
    exit 1
fi

echo "Found binary at: $ARTIFACT_PATH"

# Check for IGLX (Indirect GLX) - Required for GL rendering
if [ "$(defaults read org.xquartz.X11 enable_iglx 2>/dev/null)" != "1" ]; then
    echo "----------------------------------------------------------------"
    echo "WARNING: IGLX seems to be disabled in XQuartz."
    echo "This often causes black screens in Docker apps."
    echo "Run this command to fix it:"
    echo "  defaults write org.xquartz.X11 enable_iglx -bool true"
    echo "Then RESTART XQuartz."
    echo "----------------------------------------------------------------"
fi

echo "Preparing to run with X11 forwarding..."
echo "IMPORTANT: Ensure you have run 'xhost +localhost' in your terminal."

docker run --rm -it \
  -v "$PROJECT_ROOT:/app" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  --shm-size=2g \
  -e DISPLAY=host.docker.internal:0 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e LIBGL_ALWAYS_INDIRECT=1 \
  llama_dart_linux_builder \
  /app/$ARTIFACT_PATH
