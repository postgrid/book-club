#!/bin/bash

PUSH_ENV=".env.push"

PROD_USER=ec2-user
PROD_IP=`cat $PUSH_ENV | grep PROD_IP | awk -F= '{ print $2 }'`
PROD_SSH_KEY_PATH=`cat $PUSH_ENV | grep PROD_SSH_KEY_PATH | awk -F= '{ print $2 }'`

PROD_SSH_DEST="$PROD_USER@$PROD_IP"
