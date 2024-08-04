#!/bin/bash

# This script automatically builds and pushes to a
# prod instance as defined in a .env.push file.

source ./prod_ssh_config.sh

dune build --profile release

chmod +w ./_build/default/main.exe
cp -f ./_build/default/main.exe ./binaries/relay

scp -i "$PROD_SSH_KEY_PATH" ./binaries/relay supervisor.sh "$PROD_SSH_DEST:~"

# Stop the supervisor if its running
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" pkill -f "supervisor.sh"

# Start the supervisor again. Have to do it in a separate command because
# I don't care about the pkill output above.
ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST" nohup ./supervisor.sh relay.log relay 2892 &
