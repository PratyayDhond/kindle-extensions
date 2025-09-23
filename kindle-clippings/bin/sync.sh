#!/bin/bash

LOG_FILE="./kindle_sync_debug.log"
echo "Starting Kindle-Clippings sync..." > "$LOG_FILE"

# Find fbink binary (adapted from libkohelper.sh)
FBINK_BIN="true"
for my_dir in /var/tmp /mnt/us/koreader /mnt/us/libkh/bin /mnt/us/linkss/bin /mnt/us/linkfonts/bin /mnt/us/usbnet/bin; do
    my_fbink="${my_dir}/fbink"
    if [ -x "${my_fbink}" ]; then
        FBINK_BIN="${my_fbink}"
        break
    fi
done

# Function to clear screen and show message in true center (both X and Y axis)
show_kindle_message_center() {
    show_creator_credit
    if [ "${FBINK_BIN}" != "true" ]; then
        # Clear screen to white first
        ${FBINK_BIN} -c
        # Center both horizontally (-m flag) and vertically (-y 24)
        ${FBINK_BIN} -qm -y 24 "$1"
    elif command -v eips >/dev/null 2>&1; then
        eips -c
        # For eips, calculate center position (approximate)
        eips 10 15 "$1" >/dev/null
    fi
    
    # Log it too
    echo "$1" >> "$LOG_FILE"
    
    # Sleep for e-ink update
    usleep 150000 || sleep 0.15
}


# Function to show message in lower center (like KOReader)
show_kindle_message_bottom() {
    if [ "${FBINK_BIN}" != "true" ]; then
        # Use same formula as libkohelper.sh: -y -4 for bottom center
        ${FBINK_BIN} -qpm -y -4 "$1"
    elif command -v eips >/dev/null 2>&1; then
        eips 0 0 "$1" >/dev/null
    fi
    
    # Log it too
    echo "$1" >> "$LOG_FILE"
    
    # Sleep for e-ink update
    usleep 150000 || sleep 0.15
}

# Function to show creator credit at bottom
show_creator_credit() {
    if [ "${FBINK_BIN}" != "true" ]; then
        # Show at bottom without clearing screen
        ${FBINK_BIN} -qm -y -2 "Created by Pratyay Dhond"
    elif command -v eips >/dev/null 2>&1; then
        eips 5 35 "Created by Pratyay Dhond" >/dev/null
    fi
}


# Function to refresh Kindle library and return to home screen
refresh_kindle_library() {
    log_debug "Refreshing Kindle library..."
    
    # Clear any existing display first
    if [ "${FBINK_BIN}" != "true" ]; then
        ${FBINK_BIN} -c
    elif command -v eips >/dev/null 2>&1; then
        eips -c
    fi
    
    # Start the home application to show library
    lipc-set-prop com.lab126.appmgrd stop app://com.lab126.booklet.home
    sleep 1
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home

    # Give it time to load
    sleep 2
    
    log_debug "Returned to Kindle home screen"
}


# Function to log debug info only
log_debug() {
    {
        set -x
        echo "$1"
    } >> "$LOG_FILE" 2>&1
}

CLIPPINGS="/mnt/us/documents/My Clippings.txt"
SECRET_FILE="/mnt/us/kindle_secret.kindle_clippings"
RETRIES=6
SLEEP=15

# Clear screen and show centered messages (Option 1: Clean white screen, center)
show_kindle_message_center "Kindle Highlight Sync v2.1"
sleep 1
show_kindle_message_center "Initializing..."

if [ ! -f "$CLIPPINGS" ]; then
    show_kindle_message_center "ERROR: My Clippings.txt not found!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

if [ ! -f "$SECRET_FILE" ]; then
    show_kindle_message_center "ERROR: Config file not found!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

show_kindle_message_center "Reading configuration..."

SECRET_LINE=$(cat "$SECRET_FILE")
log_debug "Secret line: $SECRET_LINE"

USER_ID=$(echo "$SECRET_LINE" | cut -d',' -f1)
SECRET_KEY=$(echo "$SECRET_LINE" | cut -d',' -f2)
API_URL=$(echo "$SECRET_LINE" | cut -d',' -f3-)

log_debug "USER_ID: $USER_ID"
log_debug "API_URL: $API_URL"

if [ -z "$USER_ID" ] || [ -z "$SECRET_KEY" ] || [ -z "$API_URL" ]; then
    show_kindle_message_center "ERROR: Missing credentials!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

i=1
while [ $i -le $RETRIES ]; do
    show_kindle_message_center "Attempt $i/$RETRIES: Uploading..."

    log_debug "Executing curl to $API_URL/kindle/upload-clippings"

    RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
        -F "userId=$USER_ID" \
        -F "secretKey=$SECRET_KEY" \
        -F "file=@$CLIPPINGS;type=text/plain" \
        "$API_URL/kindle/upload-clippings" 2>> "$LOG_FILE")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | awk '{print $2}')
    BODY=$(echo "$RESPONSE" | head -n -1)

    log_debug "Full response: $RESPONSE"
    log_debug "HTTP Code: $HTTP_CODE"

    if [ "$HTTP_CODE" = "200" ]; then
        show_kindle_message_center "SUCCESS!"
        sleep 1
        show_kindle_message_center "Highlights uploaded successfully!"
        sleep 3
        refresh_kindle_library
        exit 0
    fi

    show_kindle_message_center "Failed. Server error (HTTP $HTTP_CODE)"
    
    if [ $i -lt $RETRIES ]; then
        show_kindle_message_center "Retrying in $SLEEP sec... ($i/$RETRIES)"
        REMAINING=$SLEEP
        while [ $REMAINING -gt 0 ]; do
            show_kindle_message_center "Retry in: $REMAINING seconds"
            sleep 1
            REMAINING=$((REMAINING - 1))
        done
    fi

    log_debug "Health check to $API_URL/kindle/health"
    HEALTH=$(curl -s -w "\nHTTP %{http_code}" "$API_URL/kindle/health" 2>> "$LOG_FILE")
    log_debug "Health response: $HEALTH"

    i=$((i + 1))
done

show_kindle_message_center "ALERT: Server not responding!"
sleep 1
show_kindle_message_center "Check connection and try again."
sleep 3
refresh_kindle_library
exit 1
