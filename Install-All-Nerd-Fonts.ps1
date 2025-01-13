# Define the URL for Nerd Fonts
$nerdFontsPage = "https://www.nerdfonts.com/font-downloads"

# Temporary folder for downloading fonts
$tempDir = "$env:TEMP\NerdFonts"
if (-Not (Test-Path -Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# System-wide fonts directory
# $fontsDir = "$env:SystemRoot\Fonts" # This variable is not used

# Create a single WebClient instance
$client = New-Object System.Net.WebClient

# Function to download a file
function Get-File {
    param (
        [string]$Uri,
        [string]$OutputPath
    )
    $client.DownloadFile($Uri, $OutputPath)
}

try {
    $response = Invoke-WebRequest -Uri $nerdFontsPage
} catch {
    Write-Error "Failed to fetch Nerd Fonts download page: $_"
    return
}

# Extract all font download URLs
try {
    $fontUrls = ($response.Content | Select-String -Pattern 'https://github\.com/ryanoasis/nerd-fonts/releases/download/[^\\"]+\.zip' -AllMatches).Matches.Value | Sort-Object -Unique
} catch {
    Write-Error "Failed to parse font download links: $_"
    return
}

if ($fontUrls.Count -eq 0) {
    Write-Error "No font download links found. The page structure may have changed."
    return
}

Write-Host "Found $($fontUrls.Count) font packages. Starting download..."

# Download and install fonts
foreach ($url in $fontUrls) {
    $fileName = [System.IO.Path]::GetFileName($url)
    $outputPath = Join-Path $tempDir $fileName

    if (-Not (Test-Path -Path $outputPath)) {
        try {
            Get-File -Uri $url -OutputPath $outputPath
        } catch {
            Write-Error "Failed to download $fileName : $($_.Exception.Message)"
            continue
        }
    } else {
        Write-Host "$fileName already downloaded. Skipping."
    }

    Write-Host "Extracting $fileName..."
    $extractPath = Join-Path $tempDir ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
    if (-Not (Test-Path -Path $extractPath)) {
        try {
            Expand-Archive -Path $outputPath -DestinationPath $extractPath -Force
        } catch {
            Write-Error "Failed to extract $fileName. The file may be corrupted or there may be permission issues."
            continue
        }
    }

    $fontFiles = Get-ChildItem -Path $extractPath -Filter *.ttf -Recurse
    foreach ($fontFile in $fontFiles) {
        $destinationPath = Join-Path $env:SystemRoot\Fonts $fontFile.Name
        if (-Not (Test-Path -Path $destinationPath)) {
            try {
                Copy-Item -Path $fontFile.FullName -Destination $destinationPath -Force
                Write-Host "Installed $($fontFile.Name)"
            } catch {
                Write-Error "Failed to install $($fontFile.Name): $_"
            }
        } else {
            Write-Host "$($fontFile.Name) is already installed. Skipping."
        }
    }
}

# Clean up temporary directory
Write-Host "Cleaning up temporary files..."
try {
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "Temporary files cleaned up successfully."
} catch {
    Write-Error "Failed to clean up temporary files: $_"
}

Write-Host "All Nerd Fonts have been installed successfully!"
