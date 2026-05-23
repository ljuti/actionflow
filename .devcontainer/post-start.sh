#!/usr/bin/env bash
set -euo pipefail

# Keep the named volume mount available and writable after container restarts.
sudo mkdir -p /apexflow
sudo chown -R "$(id -u):$(id -g)" /apexflow
