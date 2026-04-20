# Windows Junk File Scanner

A lightweight PowerShell tool for checking common junk-file locations on
Windows without deleting anything by default.

## Features

- Scans common temporary and cache directories
- Reports file count, folder count, and estimated size
- Skips missing folders automatically
- Can show the largest files in each category
- Can export the results to JSON

## Included scan targets

- User temp folder
- Windows temp folder
- Windows update download cache
- Delivery optimization cache
- Windows error reporting files
- Thumbnail cache
- Chrome cache
- Edge cache
- Firefox cache

## Usage

Run the scanner:

```powershell
.\scripts\Get-JunkFileReport.ps1
```

Show the largest files found in each category:

```powershell
.\scripts\Get-JunkFileReport.ps1 -ShowTopFiles -TopFileCount 10
```

Export the scan result to JSON:

```powershell
.\scripts\Get-JunkFileReport.ps1 -ExportJsonPath .\junk-report.json
```

## Notes

- This script is detection-only. It does not remove files.
- Some system locations may require elevated permissions for a full scan.
- Reported sizes are estimates based on files the script can access.
