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

function Show-FontSelection {
    param (
        [array]$FontUrls
    )
    
    # Create a list of font families
    $fontFamilies = @($FontUrls | ForEach-Object {
        if ($_ -match '/v[\d.]+/(.+?)\.zip') {
            $Matches[1]
        }
    } | Sort-Object -Unique)

    # Calculate columns based on console width
    $maxFontNameLength = ($fontFamilies | Measure-Object -Property Length -Maximum).Maximum
    $itemWidth = $maxFontNameLength + 6  # Add space for "[ ] " and padding
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    $columns = [Math]::Max(1, [Math]::Floor($consoleWidth / $itemWidth))
    $rows = [Math]::Ceiling($fontFamilies.Count / $columns)

    # Pre-check installed fonts and initialize selection state
    $selected = @{}
    foreach ($i in 0..($fontFamilies.Count - 1)) {
        $fontName = $fontFamilies[$i]
        # Check if any font file from this family exists
        $fontFiles = Get-ChildItem -Path "$env:SystemRoot\Fonts" -Filter "*$fontName*.ttf" -ErrorAction SilentlyContinue
        $selected[$i] = ($fontFiles.Count -gt 0)
    }
    
    $currentIndex = 0
    
    function Redraw-Menu {
        Clear-Host
        Write-Host "`nUse ↑/↓/←/→ arrows to move, Spacebar to select/unselect, Enter to confirm"
        Write-Host "Pre-selected fonts (×) are already installed`n"
        
        # Display the grid
        for ($row = 0; $row -lt $rows; $row++) {
            $line = ""
            for ($col = 0; $col -lt $columns; $col++) {
                $index = ($col * $rows) + $row
                if ($index -lt $fontFamilies.Count) {
                    $marker = if ($selected[$index]) { "[×]" } else { "[ ]" }
                    $highlight = if ($index -eq $currentIndex) { ">" } else { " " }
                    $fontName = $fontFamilies[$index]
                    $item = "$highlight$marker $fontName"
                    $line += $item.PadRight($itemWidth)
                }
            }
            Write-Host $line
        }
    }
    
    Redraw-Menu
    
    do {
        # Handle key input
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        $redraw = $true
        
        switch ($key.VirtualKeyCode) {
            38 { # Up arrow
                $currentIndex = [Math]::Max(0, $currentIndex - 1)
            }
            40 { # Down arrow
                $currentIndex = [Math]::Min($fontFamilies.Count - 1, $currentIndex + 1)
            }
            37 { # Left arrow
                $currentIndex = [Math]::Max(0, $currentIndex - $rows)
            }
            39 { # Right arrow
                $currentIndex = [Math]::Min($fontFamilies.Count - 1, $currentIndex + $rows)
            }
            32 { # Spacebar
                $selected[$currentIndex] = !$selected[$currentIndex]
            }
            13 { # Enter
                Clear-Host
                return $fontFamilies | Where-Object { $selected[$fontFamilies.IndexOf($_)] }
            }
        }
        
        if ($redraw) {
            Redraw-Menu
        }
    } while ($true)
}

# Add these functions before the font selection code
function Save-FontSelection {
    param (
        [array]$SelectedFonts
    )
    $configPath = Join-Path $env:LOCALAPPDATA "NerdFontsConfig.json"
    $config = @{
        SelectedFonts = $SelectedFonts
        LastUpdate = Get-Date
    }
    $config | ConvertTo-Json | Set-Content $configPath
}

function Get-SavedFontSelection {
    $configPath = Join-Path $env:LOCALAPPDATA "NerdFontsConfig.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json
        return $config.SelectedFonts
    }
    return $null
}

# Get selected font families
Write-Host "Found $($fontUrls.Count) font packages."
$selectedFamilies = Show-FontSelection -FontUrls $fontUrls

if (-not $selectedFamilies) {
    Write-Host "No fonts selected. Exiting..."
    return
}

# Filter URLs based on selection
$selectedUrls = $fontUrls | Where-Object {
    $url = $_
    $selectedFamilies | Where-Object { $url -match $_ }
}

Write-Host "`nSelected $($selectedUrls.Count) font packages. Starting download..."

# Download and install fonts
foreach ($url in $selectedUrls) {
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
                # Use Shell.Application to copy fonts
                $shell = New-Object -ComObject Shell.Application
                $fontsFolder = $shell.Namespace(0x14) # Windows Fonts folder
                $fontsFolder.CopyHere($fontFile.FullName, 0x14)
                Start-Sleep -Milliseconds 100  # Add small delay
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
