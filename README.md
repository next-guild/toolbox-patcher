# Toolbox Patcher

PowerShell updater for GW Toolbox and TAS Toolbox builds.

The script reads the installed GW Toolbox version from `GWToolbox.ini`, checks GitHub releases, then downloads matching updater files:

- `GWToolbox.exe` from `gwdevhub/GWToolboxpp`
- `GWToolboxdll.dll` from `gwtasdevs/GWToolboxpp`
- `gwca.dll` into the user-specific toolbox folder
- optional plugin DLLs into the `plugins` folder, preserving existing `.ini` plugin config files

## Usage

Place `update-toolbox.ps1` in the GW Toolbox root folder, then run it from that folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\update-toolbox.ps1
```

The `-ExecutionPolicy Bypass` flag applies only to that PowerShell process. It does not permanently change the user's execution policy.

If Windows blocks the file because it was downloaded from the internet, unblock it once:

```powershell
Unblock-File .\update-toolbox.ps1
```

Then run:

```powershell
.\update-toolbox.ps1
```

## Requirements

- Windows PowerShell
- Internet access to GitHub
- Run from the GW Toolbox root folder containing the computer-named user folder and `GWToolbox.ini`
