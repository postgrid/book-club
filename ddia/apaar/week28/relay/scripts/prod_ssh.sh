#/bin/bash

source ./scripts/prod_ssh_config.sh

ssh -i "$PROD_SSH_KEY_PATH" "$PROD_SSH_DEST"
