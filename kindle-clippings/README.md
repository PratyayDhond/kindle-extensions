Kindle-Clippings KUAL Extension v1.0
====================================

This extension allows you to upload your Kindle highlights (My Clippings.txt) 
directly to your backend server from your jailbroken Kindle via KUAL with enhanced 
visual feedback and robust error handling.

This extension works with [Kindle-Clippings](https://kindle-clippings.pages.dev/).

Features:
---------
- **Enhanced Visual Display**: Uses fbink for professional, centered screen messages
- **Smart Error Handling**: Comprehensive error checking with user-friendly messages
- **Auto Library Refresh**: Automatically returns to Kindle home screen after completion
- **Robust Retry System**: Visual countdown during retry attempts with server health checks
- **Debug Logging**: Detailed logging to `kindle_sync_debug.log` for troubleshooting
- **Professional UI**: Clean interface with version info and progress indicators

Usage:
------
1. Place this folder 'Kindle-Clippings' into your Kindle's '/mnt/us/extensions/' or '/extensions/' directory.
2. Ensure the sync script is executable. Run on your PC: (Not necessary in newer kindles as it executes sh files by default)
   chmod +x /mnt/us/extensions/Kindle-Clippings/bin/sync.sh
3. Save the config file at '/mnt/us/' or '/'(root of your kindle) as 'kindle_secret.kindle_clippings'. The file can be downloaded from [Kindle-Clippings](https://kindle-clippings.pages.dev/kindle-secret)
4. Connect your Kindle to WiFi.
5. Open KUAL on your Kindle.
6. Select 'Upload Highlights' to sync your highlights.
7. The extension will display centered messages showing progress and status.
8. If upload fails, script retries every 15 seconds up to 6 times with visual countdown.
9. Upon completion (success or failure), you'll automatically return to the Kindle home screen.

Technical Details:
------------------
- **Display System**: Automatically detects and uses fbink (preferred) or eips for screen output
- **Error Recovery**: Server health checks during failures to diagnose connectivity issues
- **Logging**: All operations logged to `./kindle_sync_debug.log` in the extension directory
- **Config Format**: CSV format in config file: `userId,secretKey,apiUrl`
- **File Locations**: 
  - Clippings: `/mnt/us/documents/My Clippings.txt`
  - Config: `/mnt/us/kindle_secret.kindle_clippings`
  - Log: `./kindle_sync_debug.log` (in extension directory)

Troubleshooting:
---------------
- Check `kindle_sync_debug.log` for detailed error information
- Ensure WiFi connection is stable
- Verify config file format and API URL accessibility
- Test server connectivity using the health check endpoint

Contact: dhondpratyay@gmail.com
--------
Any issues or improvements? Reach out to your developer community for support.

Enjoy syncing with enhanced visual feedback!
