#!/bin/sh

# Stop the scipt on eny error
set -e

echo "=== Build the sandbox image ==="
(cd priv/sandbox/ && ./build.sh)

echo "=== Build the headless browser image==="
(cd priv/headless-browser && ./build.sh)

echo "=== Done! ==="