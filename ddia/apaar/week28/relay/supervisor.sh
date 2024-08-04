#!/bin/bash

# This is a program supervisor that also
# does log rotation, retaining at most 2mb
# of logs.

PROGRAM=$1
LOGFILE=$2

# Cycle after 1mb of logs
MAX_LOG_SIZE=1000000

log_message() {
    local msg="$1"
    local ts=`date`
    local line="$ts: $msg"
    echo "$line" >> "$LOGFILE"
    echo "$line"
}

start_program() {
    log_message "Starting $PROGRAM..."

    # The IFS= read -r line 
    "$PROGRAM" 2>&1 | while IFS= read -r line; do
        log_message "$line"
    done &
}

cycle_log_if_required() {
    if [ -f "$LOGFILE" ] && [ `stat -c%s "$LOGFILE"` -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOGFILE" "$LOGFILE.old"
        log_message "Log file cycled."
    fi
}

is_program_running() {
    pgrep -f "$PROGRAM" > /dev/null
}

while true; do
    if ! is_program_running; then
        log_message "Program is not running. Starting..."
        start_program
    fi
    cycle_log_if_required
    sleep 10
done
