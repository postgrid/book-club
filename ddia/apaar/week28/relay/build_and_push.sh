#!/bin/bash

# This script automatically builds and pushes to a
# prod instance as defined in a .env.push file.

PUSH_ENV=".env.push"

PROD_USER=ec2-user
PROD_IP=`cat $PUSH_ENV | grep PROD_IP | awk -F= '{ print $2 }'`
PROD_SSH_KEY_PATH=`cat $PUSH_ENV | grep PROD_SSH_KEY_PATH | awk -F= '{ print $2 }'`

dune build --profile release

cp -f ./_build/default/main.exe ./binaries/relay

SSH_DEST="$PROD_USER@$PROD_IP"

scp -i "$PROD_SSH_KEY_PATH" ./binaries/relay supervisor.sh "$SSH_DEST:~" ./binaries/relay

# Stop the supervisor if its running
ssh -i "$PROD_SSH_KEY_PATH" "$SSH_DEST" pkill -f "supervisor.sh"

# Start the supervisor again. Have to do it in a separate command because
# I don't care about the pkill output above.
ssh -i "$PROD_SSH_KEY_PATH" "$SSH_DEST" ./supervisor.sh
