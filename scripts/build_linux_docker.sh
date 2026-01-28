#!/bin/bash
set -e

# Get the project root (one level up from scripts)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Project Root: $PROJECT_ROOT"

# 1. Build the Docker image
echo "Building Docker image (llama_dart_linux_builder)..."
docker build -t llama_dart_linux_builder -f "$SCRIPT_DIR/Dockerfile.linux" "$SCRIPT_DIR"

# 2. Run the build container
# We mount the project root to /app
echo "Running build in Docker..."
docker run --rm \
  -v "$PROJECT_ROOT:/app" \
  llama_dart_linux_builder \
  bash -c "
    echo 'Building example/chat_app...' && \
    cd example/chat_app && \
    flutter pub get && \
    flutter build linux --release
  "

echo "Build complete. Artifacts should be in example/chat_app/build/linux/x64/release/bundle/"
