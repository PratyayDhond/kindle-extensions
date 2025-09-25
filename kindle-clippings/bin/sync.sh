#!/bin/sh

LOG_FILE="./kindle_sync_debug.log"
echo "Starting Kindle-Clippings sync..." > "$LOG_FILE"

# Simplified log function
log_debug() {
    echo "DEBUG: $1" >> "$LOG_FILE" 2>&1
}

# Function for early error display
early_error() {
    echo "$1" >> "$LOG_FILE"
    if command -v eips >/dev/null 2>&1; then
        eips 0 10 "$1" >/dev/null 2>&1
        sleep 3
    fi
    exit 1
}

# Function to check internet connectivity
check_internet() {
    log_debug "Checking internet connectivity"
    
    # Try to ping Google DNS (8.8.8.8) with timeout
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_debug "Internet connection available"
        return 0
    elif ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        log_debug "Internet connection available (via Cloudflare DNS)"
        return 0
    else
        log_debug "No internet connection detected"
        return 1
    fi
}

# Function to handle fatal server errors (don't retry)
handle_fatal_error() {
    ERROR_CODE="$1"
    case "$ERROR_CODE" in
        "402")
            show_kindle_message_center "ERROR: Payment Required (402)"
            sleep 1
            show_kindle_message_center "Please check your account balance"
            sleep 3
            ;;
        "418")
            show_kindle_message_center "ERROR: Rate Limited (418)"
            sleep 1
            show_kindle_message_center "Please try again later"
            sleep 3
            ;;
        *)
            show_kindle_message_center "ERROR: Fatal server error ($ERROR_CODE)"
            sleep 3
            ;;
    esac
    
    log_debug "Fatal error $ERROR_CODE - exiting without retry"
    refresh_kindle_library
    exit 1
}

# Find fbink binary
FBINK_BIN="true"
for my_dir in /var/tmp /mnt/us/koreader /mnt/us/libkh/bin /mnt/us/linkss/bin /mnt/us/linkfonts/bin /mnt/us/usbnet/bin; do
    my_fbink="${my_dir}/fbink"
    if [ -x "${my_fbink}" ]; then
        FBINK_BIN="${my_fbink}"
        log_debug "Found fbink at: $my_fbink"
        break
    fi
done

if [ "${FBINK_BIN}" = "true" ]; then
    log_debug "fbink not found, will use eips fallback"
fi

# Function to clear screen and show message in center
show_kindle_message_center() {
    if [ "${FBINK_BIN}" != "true" ]; then
        ${FBINK_BIN} -c
        ${FBINK_BIN} -qm -y 24 "$1"
    elif command -v eips >/dev/null 2>&1; then
        eips -c
        eips 10 15 "$1" >/dev/null
    fi
    
    echo "$1" >> "$LOG_FILE"
    
    if command -v usleep >/dev/null 2>&1; then
        usleep 150000
    else
        sleep 0.2
    fi
}

MESSAGE_ROW=5

show_message_line() {
    if [ "${FBINK_BIN}" != "true" ]; then
        ${FBINK_BIN} -qm -y $MESSAGE_ROW "$1"
    elif command -v eips >/dev/null 2>&1; then
        eips 0 $MESSAGE_ROW "$1" >/dev/null
    fi
    
    echo "$1" >> "$LOG_FILE"
    MESSAGE_ROW=$((MESSAGE_ROW + 1))
    
    if [ $MESSAGE_ROW -gt 30 ]; then
        MESSAGE_ROW=10
        if [ "${FBINK_BIN}" != "true" ]; then
            for i in $(seq 5 30); do
                ${FBINK_BIN} -qm -y $i " "
            done
        fi
        MESSAGE_ROW=10
    fi
    
    if command -v usleep >/dev/null 2>&1; then
        usleep 150000
    else
        sleep 0.2
    fi
}

# Function to refresh Kindle library
refresh_kindle_library() {
    log_debug "Refreshing Kindle library..."
    
    if [ "${FBINK_BIN}" != "true" ]; then
        ${FBINK_BIN} -c
    elif command -v eips >/dev/null 2>&1; then
        eips -c
    fi
    
    if command -v lipc-set-prop >/dev/null 2>&1; then
        lipc-set-prop com.lab126.appmgrd stop app://com.lab126.booklet.home 2>/dev/null
        sleep 1
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home 2>/dev/null
        sleep 2
        log_debug "Returned to Kindle home screen"
    else
        log_debug "lipc-set-prop not available, cannot refresh library automatically"
    fi
}

# Configuration
SECRET_FILE="/mnt/us/kindle_secret.kindle_clippings"
UPLOAD_CACHE_FILE="/mnt/us/kindle_upload_cache.txt"
RETRIES=6
SLEEP=15

# Show startup screen
if [ "${FBINK_BIN}" != "true" ]; then
    ${FBINK_BIN} -c
fi
show_message_line "Kindle-Clippings" 
show_message_line "Made by Pratyay Dhond!"
sleep 3

# Clear screen and show centered messages
show_kindle_message_center "Kindle Highlight Sync v1.0"
sleep 1
show_kindle_message_center "Checking internet connection..."

# Check internet connectivity before proceeding
if ! check_internet; then
    show_kindle_message_center "ERROR: No internet connection!"
    sleep 1
    show_kindle_message_center "Please connect to WiFi and try again"
    sleep 3
    refresh_kindle_library
    exit 1
fi

show_kindle_message_center "Internet connection: OK"
sleep 1
show_kindle_message_center "Scanning for clipping files..."

# Step 1: Simple file discovery WITHOUT arrays - now with pattern matching
log_debug "Starting file discovery process"

# Use simple variables instead of arrays
CLIPPING_FILE_1=""
CLIPPING_FILE_2=""
CLIPPING_FILE_3=""
CLIPPING_FILE_4=""
CLIPPING_FILE_COUNT=0

log_debug "Checking standard clipping file locations"

# Check exact matches first
if [ -f "/mnt/us/documents/My Clippings.txt" ]; then
    log_debug "Found: My Clippings.txt"
    CLIPPING_FILE_1="/mnt/us/documents/My Clippings.txt"
    CLIPPING_FILE_COUNT=1
fi

if [ -f "/mnt/us/documents/myClippings.txt" ]; then
    log_debug "Found: myClippings.txt"
    if [ $CLIPPING_FILE_COUNT -eq 0 ]; then
        CLIPPING_FILE_1="/mnt/us/documents/myClippings.txt"
        CLIPPING_FILE_COUNT=1
    else
        CLIPPING_FILE_2="/mnt/us/documents/myClippings.txt"
        CLIPPING_FILE_COUNT=2
    fi
fi

# Now check for timestamped files using ls and pattern matching
if [ -d "/mnt/us/documents" ]; then
    log_debug "Checking for timestamped clipping files"
    
    # Save current directory
    ORIGINAL_DIR=$(pwd)
    cd /mnt/us/documents 2>/dev/null
    
    # Look for files with myClippings.txt pattern
    for file in *myClippings.txt; do
        if [ -f "$file" ] && [ "$file" != "*myClippings.txt" ]; then
            full_path="/mnt/us/documents/$file"
            log_debug "Found timestamped file: $full_path"
            
            # Check if we already have this file
            if [ "$full_path" != "$CLIPPING_FILE_1" ] && [ "$full_path" != "$CLIPPING_FILE_2" ]; then
                CLIPPING_FILE_COUNT=$((CLIPPING_FILE_COUNT + 1))
                
                if [ $CLIPPING_FILE_COUNT -eq 1 ]; then
                    CLIPPING_FILE_1="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 2 ]; then
                    CLIPPING_FILE_2="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 3 ]; then
                    CLIPPING_FILE_3="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 4 ]; then
                    CLIPPING_FILE_4="$full_path"
                    break  # Limit to 4 files max
                fi
            fi
        fi
    done
    
    # Look for files with My Clippings.txt pattern
    for file in *"My Clippings.txt"; do
        if [ -f "$file" ] && [ "$file" != "*My Clippings.txt" ]; then
            full_path="/mnt/us/documents/$file"
            log_debug "Found timestamped My Clippings file: $full_path"
            
            # Check if we already have this file
            if [ "$full_path" != "$CLIPPING_FILE_1" ] && [ "$full_path" != "$CLIPPING_FILE_2" ] && [ "$full_path" != "$CLIPPING_FILE_3" ]; then
                CLIPPING_FILE_COUNT=$((CLIPPING_FILE_COUNT + 1))
                
                if [ $CLIPPING_FILE_COUNT -eq 1 ]; then
                    CLIPPING_FILE_1="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 2 ]; then
                    CLIPPING_FILE_2="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 3 ]; then
                    CLIPPING_FILE_3="$full_path"
                elif [ $CLIPPING_FILE_COUNT -eq 4 ]; then
                    CLIPPING_FILE_4="$full_path"
                    break  # Limit to 4 files max
                fi
            fi
        fi
    done
    
    # Return to original directory
    cd "$ORIGINAL_DIR" 2>/dev/null
fi

log_debug "File discovery completed. Found $CLIPPING_FILE_COUNT files"
log_debug "File 1: $CLIPPING_FILE_1"
log_debug "File 2: $CLIPPING_FILE_2"
log_debug "File 3: $CLIPPING_FILE_3"
log_debug "File 4: $CLIPPING_FILE_4"

if [ $CLIPPING_FILE_COUNT -eq 0 ]; then
    log_debug "No clipping files found, showing error"
    show_kindle_message_center "ERROR: No clipping files found!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

show_kindle_message_center "Found $CLIPPING_FILE_COUNT clipping file(s)"
sleep 1

# Step 2: Check if secret file exists
log_debug "Checking for secret file: $SECRET_FILE"

if [ ! -f "$SECRET_FILE" ]; then
    log_debug "Secret file not found"
    show_kindle_message_center "ERROR: Config file not found!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

show_kindle_message_center "Reading configuration..."

SECRET_LINE=$(cat "$SECRET_FILE")
log_debug "Secret line read successfully"

USER_ID=$(echo "$SECRET_LINE" | cut -d',' -f1)
SECRET_KEY=$(echo "$SECRET_LINE" | cut -d',' -f2)
API_URL=$(echo "$SECRET_LINE" | cut -d',' -f3-)

log_debug "Configuration parsed successfully"

if [ -z "$USER_ID" ] || [ -z "$SECRET_KEY" ] || [ -z "$API_URL" ]; then
    log_debug "Missing credentials in config"
    show_kindle_message_center "ERROR: Missing credentials!"
    sleep 3
    refresh_kindle_library
    exit 1
fi

# Step 3: Process files individually
show_kindle_message_center "Checking upload cache..."
log_debug "Checking upload cache file: $UPLOAD_CACHE_FILE"

# Create cache file if it doesn't exist
if [ ! -f "$UPLOAD_CACHE_FILE" ]; then
    log_debug "Creating new cache file"
    touch "$UPLOAD_CACHE_FILE"
fi

# Process file 1
UPLOAD_FILE_1=""
if [ ! -z "$CLIPPING_FILE_1" ]; then
    log_debug "Processing file 1: $CLIPPING_FILE_1"
    
    # Calculate current file hash
    if command -v sha256sum >/dev/null 2>&1; then
        CURRENT_HASH=$(sha256sum "$CLIPPING_FILE_1" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        CURRENT_HASH=$(openssl dgst -sha256 "$CLIPPING_FILE_1" | awk '{print $2}')
    else
        CURRENT_HASH=""
    fi
    
    if [ ! -z "$CURRENT_HASH" ]; then
        # Check cache
        CACHED_HASH=$(grep -A1 "^$CLIPPING_FILE_1$" "$UPLOAD_CACHE_FILE" 2>/dev/null | tail -n1)
        
        if [ "$CACHED_HASH" != "$CURRENT_HASH" ]; then
            log_debug "File 1 needs upload"
            UPLOAD_FILE_1="$CLIPPING_FILE_1"
        else
            log_debug "File 1 unchanged, skipping"
            show_kindle_message_center "Skipping unchanged: $(basename "$CLIPPING_FILE_1")"
            sleep 1
        fi
    else
        # No hash available, upload anyway
        log_debug "No hash available for file 1, will upload"
        UPLOAD_FILE_1="$CLIPPING_FILE_1"
    fi
fi

# Process file 2 (if exists)
UPLOAD_FILE_2=""
if [ ! -z "$CLIPPING_FILE_2" ]; then
    log_debug "Processing file 2: $CLIPPING_FILE_2"
    
    # Calculate current file hash
    if command -v sha256sum >/dev/null 2>&1; then
        CURRENT_HASH=$(sha256sum "$CLIPPING_FILE_2" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        CURRENT_HASH=$(openssl dgst -sha256 "$CLIPPING_FILE_2" | awk '{print $2}')
    else
        CURRENT_HASH=""
    fi
    
    if [ ! -z "$CURRENT_HASH" ]; then
        # Check cache
        CACHED_HASH=$(grep -A1 "^$CLIPPING_FILE_2$" "$UPLOAD_CACHE_FILE" 2>/dev/null | tail -n1)
        
        if [ "$CACHED_HASH" != "$CURRENT_HASH" ]; then
            log_debug "File 2 needs upload"
            UPLOAD_FILE_2="$CLIPPING_FILE_2"
        else
            log_debug "File 2 unchanged, skipping"
            show_kindle_message_center "Skipping unchanged: $(basename "$CLIPPING_FILE_2")"
            sleep 1
        fi
    else
        # No hash available, upload anyway
        log_debug "No hash available for file 2, will upload"
        UPLOAD_FILE_2="$CLIPPING_FILE_2"
    fi
fi

# Process file 3 (if exists)
UPLOAD_FILE_3=""
if [ ! -z "$CLIPPING_FILE_3" ]; then
    log_debug "Processing file 3: $CLIPPING_FILE_3"
    
    # Calculate current file hash
    if command -v sha256sum >/dev/null 2>&1; then
        CURRENT_HASH=$(sha256sum "$CLIPPING_FILE_3" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        CURRENT_HASH=$(openssl dgst -sha256 "$CLIPPING_FILE_3" | awk '{print $2}')
    else
        CURRENT_HASH=""
    fi
    
    if [ ! -z "$CURRENT_HASH" ]; then
        # Check cache
        CACHED_HASH=$(grep -A1 "^$CLIPPING_FILE_3$" "$UPLOAD_CACHE_FILE" 2>/dev/null | tail -n1)
        
        if [ "$CACHED_HASH" != "$CURRENT_HASH" ]; then
            log_debug "File 3 needs upload"
            UPLOAD_FILE_3="$CLIPPING_FILE_3"
        else
            log_debug "File 3 unchanged, skipping"
            show_kindle_message_center "Skipping unchanged: $(basename "$CLIPPING_FILE_3")"
            sleep 1
        fi
    else
        log_debug "No hash available for file 3, will upload"
        UPLOAD_FILE_3="$CLIPPING_FILE_3"
    fi
fi

# Process file 4 (if exists)
UPLOAD_FILE_4=""
if [ ! -z "$CLIPPING_FILE_4" ]; then
    log_debug "Processing file 4: $CLIPPING_FILE_4"
    
    # Calculate current file hash
    if command -v sha256sum >/dev/null 2>&1; then
        CURRENT_HASH=$(sha256sum "$CLIPPING_FILE_4" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        CURRENT_HASH=$(openssl dgst -sha256 "$CLIPPING_FILE_4" | awk '{print $2}')
    else
        CURRENT_HASH=""
    fi
    
    if [ ! -z "$CURRENT_HASH" ]; then
        # Check cache
        CACHED_HASH=$(grep -A1 "^$CLIPPING_FILE_4$" "$UPLOAD_CACHE_FILE" 2>/dev/null | tail -n1)
        
        if [ "$CACHED_HASH" != "$CURRENT_HASH" ]; then
            log_debug "File 4 needs upload"
            UPLOAD_FILE_4="$CLIPPING_FILE_4"
        else
            log_debug "File 4 unchanged, skipping"
            show_kindle_message_center "Skipping unchanged: $(basename "$CLIPPING_FILE_4")"
            sleep 1
        fi
    else
        log_debug "No hash available for file 4, will upload"
        UPLOAD_FILE_4="$CLIPPING_FILE_4"
    fi
fi

# Count files to upload
UPLOAD_COUNT=0
if [ ! -z "$UPLOAD_FILE_1" ]; then
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
fi
if [ ! -z "$UPLOAD_FILE_2" ]; then
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
fi
if [ ! -z "$UPLOAD_FILE_3" ]; then
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
fi
if [ ! -z "$UPLOAD_FILE_4" ]; then
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
fi

if [ $UPLOAD_COUNT -eq 0 ]; then
    log_debug "No files need uploading"
    show_kindle_message_center "All files up to date!"
    sleep 2
    refresh_kindle_library
    exit 0
fi

show_kindle_message_center "Uploading $UPLOAD_COUNT file(s)..."
sleep 1

# Upload file 1 if needed
if [ ! -z "$UPLOAD_FILE_1" ]; then
    log_debug "Starting upload for file 1: $UPLOAD_FILE_1"
    show_kindle_message_center "Uploading: $(basename "$UPLOAD_FILE_1")"
    
    # Upload logic for file 1
    i=1
    UPLOAD_SUCCESS=false
    
    while [ $i -le $RETRIES ]; do
        show_kindle_message_center "Attempt $i/$RETRIES: Uploading..."
        log_debug "Upload attempt $i/$RETRIES for file 1"

        RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
            -F "userId=$USER_ID" \
            -F "secretKey=$SECRET_KEY" \
            -F "file=@$UPLOAD_FILE_1;type=text/plain" \
            "$API_URL/kindle/upload-clippings" 2>> "$LOG_FILE")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | awk '{print $2}')

        # Check for fatal errors that should exit immediately
        if [ "$HTTP_CODE" = "402" ] || [ "$HTTP_CODE" = "418" ]; then
            handle_fatal_error "$HTTP_CODE"
        fi
        
        # Check for connection errors
        if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
            log_debug "No HTTP response - possible connection issue"
            if ! check_internet; then
                show_kindle_message_center "ERROR: Internet connection lost!"
                sleep 3
                refresh_kindle_library
                exit 1
            fi
        fi

        if [ "$HTTP_CODE" = "200" ]; then
            log_debug "Upload successful for file 1"
            show_kindle_message_center "SUCCESS!"
            sleep 1
            
            # Update cache
            if command -v sha256sum >/dev/null 2>&1; then
                NEW_HASH=$(sha256sum "$UPLOAD_FILE_1" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                NEW_HASH=$(openssl dgst -sha256 "$UPLOAD_FILE_1" | awk '{print $2}')
            else
                NEW_HASH="uploaded"
            fi
            
            # Update cache file
            grep -v "^$UPLOAD_FILE_1$" "$UPLOAD_CACHE_FILE" > "$UPLOAD_CACHE_FILE.tmp" 2>/dev/null || true
            echo "$UPLOAD_FILE_1" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "$NEW_HASH" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "" >> "$UPLOAD_CACHE_FILE.tmp"
            mv "$UPLOAD_CACHE_FILE.tmp" "$UPLOAD_CACHE_FILE"
            
            UPLOAD_SUCCESS=true
            break
        fi

        show_kindle_message_center "Failed. Server error (HTTP $HTTP_CODE)"
        
        if [ $i -lt $RETRIES ]; then
            show_kindle_message_center "Retrying in $SLEEP sec..."
            REMAINING=$SLEEP
            while [ $REMAINING -gt 0 ]; do
                show_kindle_message_center "Retry in: $REMAINING seconds"
                sleep 1
                REMAINING=$((REMAINING - 1))
            done
        fi

        i=$((i + 1))
    done
    
    if [ "$UPLOAD_SUCCESS" = false ]; then
        show_kindle_message_center "FAILED to upload file 1"
        sleep 2
    fi
fi

# Upload file 2 if needed
if [ ! -z "$UPLOAD_FILE_2" ]; then
    log_debug "Starting upload for file 2: $UPLOAD_FILE_2"
    show_kindle_message_center "Uploading: $(basename "$UPLOAD_FILE_2")"
    
    # Upload logic for file 2
    i=1
    UPLOAD_SUCCESS=false
    
    while [ $i -le $RETRIES ]; do
        show_kindle_message_center "Attempt $i/$RETRIES: Uploading..."
        log_debug "Upload attempt $i/$RETRIES for file 2"

        RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
            -F "userId=$USER_ID" \
            -F "secretKey=$SECRET_KEY" \
            -F "file=@$UPLOAD_FILE_2;type=text/plain" \
            "$API_URL/kindle/upload-clippings" 2>> "$LOG_FILE")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | awk '{print $2}')

        # Check for fatal errors that should exit immediately
        if [ "$HTTP_CODE" = "402" ] || [ "$HTTP_CODE" = "418" ]; then
            handle_fatal_error "$HTTP_CODE"
        fi
        
        # Check for connection errors
        if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
            log_debug "No HTTP response - possible connection issue"
            if ! check_internet; then
                show_kindle_message_center "ERROR: Internet connection lost!"
                sleep 3
                refresh_kindle_library
                exit 1
            fi
        fi

        if [ "$HTTP_CODE" = "200" ]; then
            log_debug "Upload successful for file 2"
            show_kindle_message_center "SUCCESS!"
            sleep 1
            
            # Update cache
            if command -v sha256sum >/dev/null 2>&1; then
                NEW_HASH=$(sha256sum "$UPLOAD_FILE_2" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                NEW_HASH=$(openssl dgst -sha256 "$UPLOAD_FILE_2" | awk '{print $2}')
            else
                NEW_HASH="uploaded"
            fi
            
            # Update cache file
            grep -v "^$UPLOAD_FILE_2$" "$UPLOAD_CACHE_FILE" > "$UPLOAD_CACHE_FILE.tmp" 2>/dev/null || true
            echo "$UPLOAD_FILE_2" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "$NEW_HASH" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "" >> "$UPLOAD_CACHE_FILE.tmp"
            mv "$UPLOAD_CACHE_FILE.tmp" "$UPLOAD_CACHE_FILE"
            
            UPLOAD_SUCCESS=true
            break
        fi

        show_kindle_message_center "Failed. Server error (HTTP $HTTP_CODE)"
        
        if [ $i -lt $RETRIES ]; then
            show_kindle_message_center "Retrying in $SLEEP sec..."
            REMAINING=$SLEEP
            while [ $REMAINING -gt 0 ]; do
                show_kindle_message_center "Retry in: $REMAINING seconds"
                sleep 1
                REMAINING=$((REMAINING - 1))
            done
        fi

        i=$((i + 1))
    done
    
    if [ "$UPLOAD_SUCCESS" = false ]; then
        show_kindle_message_center "FAILED to upload file 2"
        sleep 2
    fi
fi

# Upload file 3 if needed
if [ ! -z "$UPLOAD_FILE_3" ]; then
    log_debug "Starting upload for file 3: $UPLOAD_FILE_3"
    show_kindle_message_center "Uploading: $(basename "$UPLOAD_FILE_3")"
    
    # Upload logic for file 3
    i=1
    UPLOAD_SUCCESS=false
    
    while [ $i -le $RETRIES ]; do
        show_kindle_message_center "Attempt $i/$RETRIES: Uploading..."
        log_debug "Upload attempt $i/$RETRIES for file 3"

        RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
            -F "userId=$USER_ID" \
            -F "secretKey=$SECRET_KEY" \
            -F "file=@$UPLOAD_FILE_3;type=text/plain" \
            "$API_URL/kindle/upload-clippings" 2>> "$LOG_FILE")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | awk '{print $2}')

        # Check for fatal errors that should exit immediately
        if [ "$HTTP_CODE" = "402" ] || [ "$HTTP_CODE" = "418" ]; then
            handle_fatal_error "$HTTP_CODE"
        fi
        
        # Check for connection errors
        if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
            log_debug "No HTTP response - possible connection issue"
            if ! check_internet; then
                show_kindle_message_center "ERROR: Internet connection lost!"
                sleep 3
                refresh_kindle_library
                exit 1
            fi
        fi

        if [ "$HTTP_CODE" = "200" ]; then
            log_debug "Upload successful for file 3"
            show_kindle_message_center "SUCCESS!"
            sleep 1
            
            # Update cache
            if command -v sha256sum >/dev/null 2>&1; then
                NEW_HASH=$(sha256sum "$UPLOAD_FILE_3" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                NEW_HASH=$(openssl dgst -sha256 "$UPLOAD_FILE_3" | awk '{print $2}')
            else
                NEW_HASH="uploaded"
            fi
            
            # Update cache file
            grep -v "^$UPLOAD_FILE_3$" "$UPLOAD_CACHE_FILE" > "$UPLOAD_CACHE_FILE.tmp" 2>/dev/null || true
            echo "$UPLOAD_FILE_3" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "$NEW_HASH" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "" >> "$UPLOAD_CACHE_FILE.tmp"
            mv "$UPLOAD_CACHE_FILE.tmp" "$UPLOAD_CACHE_FILE"
            
            UPLOAD_SUCCESS=true
            break
        fi

        show_kindle_message_center "Failed. Server error (HTTP $HTTP_CODE)"
        
        if [ $i -lt $RETRIES ]; then
            show_kindle_message_center "Retrying in $SLEEP sec..."
            REMAINING=$SLEEP
            while [ $REMAINING -gt 0 ]; do
                show_kindle_message_center "Retry in: $REMAINING seconds"
                sleep 1
                REMAINING=$((REMAINING - 1))
            done
        fi

        i=$((i + 1))
    done
    
    if [ "$UPLOAD_SUCCESS" = false ]; then
        show_kindle_message_center "FAILED to upload file 3"
        sleep 2
    fi
fi

# Upload file 4 if needed
if [ ! -z "$UPLOAD_FILE_4" ]; then
    log_debug "Starting upload for file 4: $UPLOAD_FILE_4"
    show_kindle_message_center "Uploading: $(basename "$UPLOAD_FILE_4")"
    
    # Upload logic for file 4
    i=1
    UPLOAD_SUCCESS=false
    
    while [ $i -le $RETRIES ]; do
        show_kindle_message_center "Attempt $i/$RETRIES: Uploading..."
        log_debug "Upload attempt $i/$RETRIES for file 4"

        RESPONSE=$(curl -s -w "\nHTTP %{http_code}" \
            -F "userId=$USER_ID" \
            -F "secretKey=$SECRET_KEY" \
            -F "file=@$UPLOAD_FILE_4;type=text/plain" \
            "$API_URL/kindle/upload-clippings" 2>> "$LOG_FILE")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | awk '{print $2}')

        # Check for fatal errors that should exit immediately
        if [ "$HTTP_CODE" = "402" ] || [ "$HTTP_CODE" = "418" ]; then
            handle_fatal_error "$HTTP_CODE"
        fi
        
        # Check for connection errors
        if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
            log_debug "No HTTP response - possible connection issue"
            if ! check_internet; then
                show_kindle_message_center "ERROR: Internet connection lost!"
                sleep 3
                refresh_kindle_library
                exit 1
            fi
        fi

        if [ "$HTTP_CODE" = "200" ]; then
            log_debug "Upload successful for file 4"
            show_kindle_message_center "SUCCESS!"
            sleep 1
            
            # Update cache
            if command -v sha256sum >/dev/null 2>&1; then
                NEW_HASH=$(sha256sum "$UPLOAD_FILE_4" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                NEW_HASH=$(openssl dgst -sha256 "$UPLOAD_FILE_4" | awk '{print $2}')
            else
                NEW_HASH="uploaded"
            fi
            
            # Update cache file
            grep -v "^$UPLOAD_FILE_4$" "$UPLOAD_CACHE_FILE" > "$UPLOAD_CACHE_FILE.tmp" 2>/dev/null || true
            echo "$UPLOAD_FILE_4" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "$NEW_HASH" >> "$UPLOAD_CACHE_FILE.tmp"
            echo "" >> "$UPLOAD_CACHE_FILE.tmp"
            mv "$UPLOAD_CACHE_FILE.tmp" "$UPLOAD_CACHE_FILE"
            
            UPLOAD_SUCCESS=true
            break
        fi

        show_kindle_message_center "Failed. Server error (HTTP $HTTP_CODE)"
        
        if [ $i -lt $RETRIES ]; then
            show_kindle_message_center "Retrying in $SLEEP sec..."
            REMAINING=$SLEEP
            while [ $REMAINING -gt 0 ]; do
                show_kindle_message_center "Retry in: $REMAINING seconds"
                sleep 1
                REMAINING=$((REMAINING - 1))
            done
        fi

        i=$((i + 1))
    done
    
    if [ "$UPLOAD_SUCCESS" = false ]; then
        show_kindle_message_center "FAILED to upload file 4"
        sleep 2
    fi
fi

show_kindle_message_center "Upload process completed!"
sleep 2
refresh_kindle_library
exit 0
