#!/bin/bash

# This is a program supervisor that also
# does log rotation, retaining at most 2mb
# of logs.

LOGFILE=$1
PROGRAM=$2

shift 2

# Cycle after 1mb of logs
MAX_LOG_SIZE=1000000

log_message() {
    local context=$1
    local msg="$2"
    local ts=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
    local line="[$ts] [$context] $msg"
    echo "$line"
    echo "$line" >> "$LOGFILE"
}

start_program() {
    log_message "SUPERVISOR" "Starting $PROGRAM $@..."

    # The IFS= read -r line 
    "$PROGRAM" $@ 2>&1 | while IFS= read -r line; do
        log_message "PROGRAM" "$line"
    done &
}

cycle_log_if_required() {
    if [ -f "$LOGFILE" ] && [ `stat -c%s "$LOGFILE"` -gt "$MAX_LOG_SIZE" ]; then
        mv "$LOGFILE" "$LOGFILE.old"
        log_message "SUPERVISOR" "Log file cycled."
    fi
}

get_program_pid() {
    pgrep -f "^${PROGRAM}"
}

is_program_running() {
    get_program_pid > /dev/null
}

log_program_metrics() {
    local pid=`get_program_pid`
    local cpu=`ps --no-headers -p "$pid" -o %cpu | tr -d ' '`
    local mem=`ps --no-headers -p "$pid" -o %mem | tr -d ' '`
    log_message "METRICS" "pid=$pid cpu=$cpu mem=$mem"
}

while true; do
    if ! is_program_running; then
        log_message "SUPERVISOR" "Program is not running. Starting..."
        start_program $@
    fi
    log_program_metrics
    cycle_log_if_required
    sleep 20
done
