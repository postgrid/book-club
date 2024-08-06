#!/bin/bash

PUSH_ENV=".env.push"

dotenv_var() {
    cat "$PUSH_ENV" | grep $1 | awk -F= '{ print $2 }'
}

PROD_USER=ec2-user

PROD_BUILD_PROFILE=`dotenv_var PROD_BUILD_PROFILE`
PROD_IP=`dotenv_var PROD_IP`
PROD_SSH_KEY_PATH=`dotenv_var PROD_SSH_KEY_PATH`

PROD_SSH_DEST="$PROD_USER@$PROD_IP"
