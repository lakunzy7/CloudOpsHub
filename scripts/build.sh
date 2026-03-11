#!/bin/bash
set -euo pipefail

# Copy static assets into nginx build context before docker-compose build
echo "Copying static assets to nginx build context..."
cp -r theepicbook/public nginx/public

echo "Building services..."
docker compose "$@" build

echo "Cleaning up..."
rm -rf nginx/public

echo "Build complete."
