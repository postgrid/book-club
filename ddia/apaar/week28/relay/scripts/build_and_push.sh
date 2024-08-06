#!/bin/bash

# This script automatically builds and pushes to a
# prod instance as defined in a .env.push file.

source ./scripts/prod_ssh_config.sh

set -euo pipefail

dune build --profile "$PROD_BUILD_PROFILE"

chmod +w ./_build/default/server/server.exe
cp -f ./_build/default/server/server.exe ./binaries/linux_amd64/relay-server

# Stop the running processes, if any
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" pkill -f "supervisor.sh" > /dev/null || true
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" pkill -f "relay-server" > /dev/null || true

scp -i "$PROD_SSH_KEY_PATH" ./binaries/linux_amd64/relay-server ./scripts/supervisor.sh "$PROD_SSH_DEST:~"

# Start the supervisor again. Have to do it in a separate command because
# I don't care about the pkill output above.
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" nohup ./supervisor.sh relay-server.log ./relay-server 2892 &
