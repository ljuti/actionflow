#!/usr/bin/env bash
set -euo pipefail

bundle install
bundle exec rake

# Ensure the named volume mount is writable by the devcontainer user.
sudo mkdir -p /apexflow
sudo chown -R "$(id -u):$(id -g)" /apexflow

curl -fsSL https://omp.sh/install | sh