FROM ghcr.io/cirruslabs/flutter:stable

# Install build dependencies
RUN apt-get update && apt-get install -y \
  cmake \
  build-essential \
  clang \
  git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire project to preserve relative paths
COPY . .

# Build the native library
WORKDIR /app/src/native
RUN rm -rf build && mkdir -p build && cd build && \
  cmake .. -DCMAKE_BUILD_TYPE=Release && \
  make -j$(nproc)

# Verify the library exists
RUN ls -l /app/src/native/build/bin/

# Run the basic_app
WORKDIR /app/example/basic_app
RUN flutter pub get

# Run the test
CMD ["dart", "run"]
