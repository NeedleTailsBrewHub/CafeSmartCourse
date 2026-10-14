# ================================
# Build image
# ================================
FROM swift:6.2.0-noble AS build

# Install OS updates
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
# NOTE: Vendor/swift-onnx-runtime must be a real directory copy in the build
# context (Docker will not follow host symlinks that point outside the context).
COPY ./Package.* ./
COPY ./Vendor ./Vendor
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy entire repo into container
COPY . .

# Build the application, with optimizations, with static linking, and using jemalloc
# N.B.: The static version of jemalloc is incompatible with the static Swift runtime.
RUN swift build -c release \
        --product CafeSmartApi \
        --static-swift-stdlib \
        -Xlinker -ljemalloc

# Switch to the staging area
WORKDIR /staging

# Copy main executable to staging area
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/CafeSmartApi" ./

# Copy static swift backtracer binary to staging area
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy resources bundled by SPM to staging area
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \;

# Copy any resources from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Certificates ] && { mv /build/Certificates ./Certificates && chmod -R a-w ./Certificates; } || true
RUN [ -f /build/.env ] && { cp /build/.env ./.env && chmod -R a-w ./.env; } || true
RUN mkdir -p ./lib ./Trainer \
 && cp -a /build/Vendor/swift-onnx-runtime/Sources/CONNX/lib/. ./lib/ \
 && cp -a /build/Trainer/. ./Trainer/


# ================================
# Run image
# ================================
FROM ubuntu:noble AS web

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      python3 \
      python3-venv \
      python3-pip \
# If your app or its dependencies import FoundationNetworking, also install `libcurl4`.
      # libcurl4 \
# If your app or its dependencies import FoundationXML, also install `libxml2`.
      # libxml2 \
    && rm -r /var/lib/apt/lists/*

# Create a manager user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app manager

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=manager:manager /staging /app

RUN python3 -m venv /app/Trainer/.venv \
 && /app/Trainer/.venv/bin/pip install --no-cache-dir -r /app/Trainer/requirements.txt \
 && chown -R manager:manager /app/Trainer

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static
ENV LD_LIBRARY_PATH=/app/lib
ENV TRAINER_PYTHON=/app/Trainer/.venv/bin/python
ENV TRAINER_SCRIPT=/app/Trainer/train_restock.py

# Ensure all further commands run as the manager user
USER manager:manager

# Let Docker bind to port 8080
EXPOSE 8080

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
ENTRYPOINT ["./CafeSmartApi"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
