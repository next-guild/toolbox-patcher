# GW Toolbox Updater Script
# This script updates GW Toolbox components from GitHub releases
# Run this from the GW Toolbox root folder (gwtoolboxpp)

param(
    [Parameter(Position = 0)]
    [string]$Version
)

# Function to get version from ini file
function Get-DllVersion {
    param([string]$iniPath)
    $content = Get-Content $iniPath
    foreach ($line in $content) {
        if ($line -match '^dllversion\s*=\s*(.+)') {
            return $matches[1].Trim()
        }
    }
    throw "dllversion not found in $iniPath"
}

# Function to compare versions (simple string comparison, assumes format like 8.16)
function Compare-Versions {
    param([string]$v1, [string]$v2)
    $v1Parts = $v1 -split '\.'
    $v2Parts = $v2 -split '\.'
    for ($i = 0; $i -lt [math]::Max($v1Parts.Length, $v2Parts.Length); $i++) {
        $p1 = if ($i -lt $v1Parts.Length) { [int]$v1Parts[$i] } else { 0 }
        $p2 = if ($i -lt $v2Parts.Length) { [int]$v2Parts[$i] } else { 0 }
        if ($p1 -gt $p2) { return 1 }
        if ($p1 -lt $p2) { return -1 }
    }
    return 0
}

# Function to download file
function Download-File {
    param([string]$url, [string]$outputPath)
    Write-Host "Downloading $url to $outputPath"
    Invoke-WebRequest -Uri $url -OutFile $outputPath
}

# Main script
try {
    # Get user folder
    $userFolder = $env:COMPUTERNAME
    $pluginsPath = Join-Path $userFolder "plugins"
    $iniPath = Join-Path $userFolder "GWToolbox.ini"

    # Check if running from toolbox folder
    if (!(Test-Path $userFolder)) {
        throw "$userFolder not found. Please run this script from the GW Toolbox root folder."
    }

    # Get requested version, or fall back to the installed version.
    $targetVersion = if ($null -eq $Version) { "" } else { $Version.Trim() }
    if ([string]::IsNullOrWhiteSpace($targetVersion)) {
        if (!(Test-Path $iniPath)) {
            throw "GWToolbox.ini not found in $userFolder. Please run this script from the GW Toolbox root folder or provide a version, e.g. .\update-toolbox.ps1 8.26"
        }

        $targetVersion = Get-DllVersion $iniPath
        Write-Host "No version provided. Using installed GW Toolbox version: $targetVersion"
    } else {
        if ($targetVersion -notmatch '^\d+\.\d+$') {
            throw "Invalid version '$targetVersion'. Expected a version like 8.26"
        }

        Write-Host "Target GW Toolbox version: $targetVersion"
        if (Test-Path $iniPath) {
            $installedVersion = Get-DllVersion $iniPath
            Write-Host "Installed GW Toolbox version: $installedVersion"
        }
    }

    # Check for more recent GW Toolbox version
    Write-Host "Checking for more recent GW Toolbox version..."
    $gwReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/gwdevhub/GWToolboxpp/releases"
    # Find latest release tag matching X.Y_Release
    $latestRelease = $gwReleases | Where-Object { $_.tag_name -match '^(\d+\.\d+)_Release$' -and $_.prerelease -eq $false } | 
        ForEach-Object { [PSCustomObject]@{ Release = $_; Version = [version]$matches[1] } } | 
        Sort-Object Version -Descending | Select-Object -First 1
    if ($latestRelease) {
        $latestTag = $latestRelease.Version.ToString()
        $comparison = Compare-Versions $latestTag $targetVersion
        if ($comparison -gt 0) {
            Write-Host "A newer GW Toolbox version is available: $latestTag (target: $targetVersion)"
        } else {
            Write-Host "Target GW Toolbox version is up to date."
        }
    }

    # Find GW release for exe using the target major version
    $majorVersion = ($targetVersion -split '\.')[0]
    $exeReleaseTag = "$majorVersion.0_Exe"
    Write-Host "Looking for GW Toolbox exe release tag $exeReleaseTag"
    $gwRelease = $gwReleases | Where-Object { $_.tag_name -eq $exeReleaseTag } | Select-Object -First 1
    if ($gwRelease) {
        Write-Host "Found GW Toolbox exe release"
        # Find exe asset
        $exeAsset = $gwRelease.assets | Where-Object { $_.name -like "*GWToolbox*.exe" -or $_.name -eq "GWToolbox.exe" } | Select-Object -First 1
        if ($exeAsset) {
            Write-Host "Updating GWToolbox.exe..."
            Download-File $exeAsset.browser_download_url "GWToolbox.exe"
        } else {
            Write-Host "No exe found in GW Toolbox exe release"
        }
    } else {
        Write-Host "No GW Toolbox exe release found for tag $exeReleaseTag"
    }

    # Check TAS releases for matching version (including beta releases)
    Write-Host "Checking TAS Toolbox releases..."
    $tasReleases = Invoke-RestMethod -Uri "https://api.github.com/repos/gwtasdevs/GWToolboxpp/releases"
    
    # Find latest release matching the target version (either Release or Beta)
    $matchingReleases = $tasReleases | Where-Object { 
        $_.tag_name -match "^$([regex]::Escape($targetVersion))_(Release|Beta_[a-f0-9]+)$" 
    }
    
    # Sort by published date descending to get the latest one
    $tasRelease = $matchingReleases | Sort-Object -Property published_at -Descending | Select-Object -First 1
    
    if ($tasRelease) {
        Write-Host "Found TAS Toolbox release: $($tasRelease.tag_name)"

        # Download GWToolboxdll.dll
        $dllAsset = $tasRelease.assets | Where-Object { $_.name -eq "GWToolboxdll.dll" } | Select-Object -First 1
        if ($dllAsset) {
            Write-Host "Updating GWToolboxdll.dll..."
            Download-File $dllAsset.browser_download_url "GWToolboxdll.dll"
        }

        # Download gwca.dll to user folder
        $gwcaAsset = $tasRelease.assets | Where-Object { $_.name -eq "gwca.dll" } | Select-Object -First 1
        if ($gwcaAsset) {
            Write-Host "Updating gwca.dll..."
            Download-File $gwcaAsset.browser_download_url (Join-Path $userFolder "gwca.dll")
        }

        # Plugins - dynamically get all .dll files except GWToolboxdll.dll and gwca.dll
        $updatePlugins = Read-Host "Do you want to update plugins? This will delete all current plugins and replace them. (y/n)"
        if ($updatePlugins -eq 'y' -or $updatePlugins -eq 'Y') {
            # Clear plugins folder (except .ini files)
            if (Test-Path $pluginsPath) {
                Write-Host "Clearing plugins folder (preserving .ini files)..."
                Get-ChildItem -Path $pluginsPath -Exclude "*.ini" -Force | Remove-Item -Force -Recurse
            } else {
                New-Item -ItemType Directory -Path $pluginsPath -Force | Out-Null
            }

            # Get all .dll assets except GWToolboxdll.dll and gwca.dll
            $pluginAssets = $tasRelease.assets | Where-Object { 
                $_.name -like "*.dll" -and 
                $_.name -ne "GWToolboxdll.dll" -and 
                $_.name -ne "gwca.dll" 
            }

            # Download all plugins
            foreach ($asset in $pluginAssets) {
                Write-Host "Updating plugin: $($asset.name)..."
                Download-File $asset.browser_download_url (Join-Path $pluginsPath $asset.name)
            }

            if ($pluginAssets.Count -gt 0) {
                Write-Host "Downloaded $($pluginAssets.Count) plugin(s)."
            } else {
                Write-Host "No plugins found in release."
            }
        } else {
            Write-Host "Skipping plugin updates."
        }
    } else {
        Write-Host "No TAS Toolbox release found for version $targetVersion"
    }

    Write-Host "Update complete."
} catch {
    Write-Host "Error: $_"
}
