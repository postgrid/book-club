#!/bin/bash

# This script automatically builds and pushes to a
# prod instance as defined in a .env.push file.

source ./prod_ssh_config.sh

set -euo pipefail

dune build --profile "$PROD_BUILD_PROFILE"

chmod +w ./_build/default/relay.exe
cp -f ./_build/default/relay.exe ./binaries/linux_amd64/relay

# Stop the running processes, if any
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" pkill -f "supervisor.sh" > /dev/null || true
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" pkill -f "relay" > /dev/null || true

scp -i "$PROD_SSH_KEY_PATH" ./binaries/linux_amd64/relay supervisor.sh "$PROD_SSH_DEST:~"

# Start the supervisor again. Have to do it in a separate command because
# I don't care about the pkill output above.
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" nohup ./supervisor.sh relay.log ./relay 2892 &
