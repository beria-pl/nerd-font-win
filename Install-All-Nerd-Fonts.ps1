# Define the URL for Nerd Fonts
$nerdFontsPage = "https://www.nerdfonts.com/font-downloads"

# Temporary folder for downloading fonts
$tempDir = "$env:TEMP\NerdFonts"
if (-Not (Test-Path -Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# System-wide fonts directory
$fontsDir = "$env:SystemRoot\Fonts"

# Function to download a file
function Download-File {
    param (
        [string]$Uri,
        [string]$OutputPath
    )
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($Uri, $OutputPath)
}

# Fetch the Nerd Fonts page and parse download links
Write-Host "Fetching Nerd Fonts download page..."
$response = Invoke-WebRequest -Uri $nerdFontsPage

# Extract all font download URLs
$fontUrls = ($response.Content | Select-String -Pattern "https://github.com/ryanoasis/nerd-fonts/releases/download/[^"]+\.zip" -AllMatches).Matches.Value | Sort-Object -Unique

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
        Write-Host "Downloading $fileName..."
        Download-File -Uri $url -OutputPath $outputPath
    } else {
        Write-Host "$fileName already downloaded. Skipping."
    }

    Write-Host "Extracting $fileName..."
    $extractPath = Join-Path $tempDir ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
    if (-Not (Test-Path -Path $extractPath)) {
        Expand-Archive -Path $outputPath -DestinationPath $extractPath -Force
    }

    Write-Host "Installing fonts from $fileName..."
    $fontFiles = Get-ChildItem -Path $extractPath -Recurse -Filter *.ttf,*.otf
    foreach ($fontFile in $fontFiles) {
        $destinationPath = Join-Path $fontsDir $fontFile.Name
        if (-Not (Test-Path -Path $destinationPath)) {
            Copy-Item -Path $fontFile.FullName -Destination $destinationPath -Force
            Write-Host "Installed $($fontFile.Name)"
        } else {
            Write-Host "$($fontFile.Name) is already installed. Skipping."
        }
    }
}

# Clean up temporary directory
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "All Nerd Fonts have been installed successfully!"
