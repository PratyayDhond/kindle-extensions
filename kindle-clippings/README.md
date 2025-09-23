Kindle-Clippings KUAL Extension
===============================

This extension allows you to upload your Kindle highlights (My Clippings.txt) 
directly to your backend server from your jailbroken Kindle via KUAL.

Usage:
------
1. Place this folder 'Kindle-Clippings' into your Kindle's /mnt/us/extensions/ directory.
2. Ensure the sync script is executable. Run on your PC:
   chmod +x /mnt/us/extensions/Kindle-Clippings/bin/sync.sh
3. Create a config file at /mnt/us/.kindle_secret.kindle_clippings with the following lines:
   - Line 1: your userId
   - Line 2: your secretKey
   - Line 3: backend API base URL (e.g., https://yourserver.com)
4. Connect your Kindle to WiFi.
5. Open KUAL on your Kindle.
6. Select 'Upload Highlights' to sync your highlights.
7. Wait for success message or error if server is unreachable.
8. If upload fails, script retries every 15 seconds up to 6 times.

Note:
-----
- This script uploads the raw My Clippings.txt file.
- Your backend must accept multipart/form-data and require userId and secretKey fields.
- Ensure your backend is reachable and configured according to your API schema.
- The script shows status, handles retries, and alerts if server is down.

Contact:
--------
Any issues or improvements? Reach out to your developer community for support.

Enjoy syncing!
