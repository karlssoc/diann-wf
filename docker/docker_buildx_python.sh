#!/bin/bash

export DOCKER_ENGINE="OrbStack"

# Check if docker engine is running
if ! pgrep -f "$DOCKER_ENGINE" > /dev/null; then
    echo "Starting $DOCKER_ENGINE..."
    open -a "$DOCKER_ENGINE"
    sleep 5  # Allow time for startup
fi

# Build context must be the project root so that
# COPY docker/requirements.python.txt resolves correctly.
cd "$(dirname "$0")/.." || exit 1

# Ensure a multi-platform capable builder exists.
# The default 'docker' driver only supports the host platform; the
# 'docker-container' driver supports linux/amd64 + linux/arm64 via QEMU.
BUILDER_NAME="multiplatform"
if ! docker buildx inspect "$BUILDER_NAME" > /dev/null 2>&1; then
    echo "Creating buildx builder '$BUILDER_NAME'..."
    docker buildx create --name "$BUILDER_NAME" --driver docker-container --use
else
    docker buildx use "$BUILDER_NAME"
fi

# Build multi-platform image and push.
# Requires docker buildx (included with Docker Desktop / OrbStack).
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --file docker/Dockerfile.python \
    --tag quay.io/karlssoc/diannwf-python:1.0 \
    --push \
    .