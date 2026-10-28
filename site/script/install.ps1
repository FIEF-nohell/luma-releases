# Luma installer for Windows.
#
# One line (PowerShell):
#   irm https://getluma.nohelll.com/script/install.ps1 | iex
#
# What it does: finds the newest Luma build in github.com/FIEF-nohell/luma-releases, downloads the zip and its
# SHA256 file, checks the hash, installs into %LOCALAPPDATA%\Programs\Luma (no administrator rights needed) and
# adds a Start menu shortcut. Your sessions and settings live in %LOCALAPPDATA%\Luma and are never touched.
# Running it again updates Luma in place.
#
# Options (environment variables, because "irm | iex" cannot pass parameters):
#   $env:LUMA_VERSION     = "v0.1.0-dev.cb13b6d"   install this release tag instead of the newest
#   $env:LUMA_INSTALL_DIR = "D:\Apps\Luma"          install somewhere else
#   $env:LUMA_NO_SHORTCUT = "1"                     skip the Start menu shortcut
#   $env:LUMA_UNINSTALL   = "1"                     remove the program and the shortcut (keeps sessions and settings)
# The same options also work as parameters when the file is saved and run: .\install.ps1 -Version <tag> -Uninstall

# Everything runs inside one function that is called on the last line, so a download cut short runs nothing.
function Install-Luma {
    [CmdletBinding()]
    param(
        [string]$Version = $env:LUMA_VERSION,
        [string]$InstallDir = $env:LUMA_INSTALL_DIR,
        [switch]$NoShortcut = ($env:LUMA_NO_SHORTCUT -eq "1"),
        [switch]$Uninstall = ($env:LUMA_UNINSTALL -eq "1")
    )

    $ErrorActionPreference = "Stop"
    $ProgressPreference = "SilentlyContinue"   # the progress bar makes Invoke-WebRequest very slow in PowerShell 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = "FIEF-nohell/luma-releases"
    $marker = "luma.installed"   # tells luma.exe to keep its settings in %LOCALAPPDATA%\Luma, not in the program folder
    if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Luma" }
    $InstallDir = [IO.Path]::GetFullPath($InstallDir)
    $shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Luma.lnk"

    function Say([string]$text) { Write-Host "luma: $text" }

    if (-not [Environment]::Is64BitOperatingSystem) { throw "Luma needs 64 bit Windows." }

    # An MSI install owns its files; overwriting them would break its repair and uninstall.
    $msi = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq "Luma" -and $_.WindowsInstaller -eq 1 } | Select-Object -First 1
    $msiHere = $false
    if ($msi) {
        if (-not $msi.InstallLocation) { $msiHere = $true }
        else { $msiHere = ([IO.Path]::GetFullPath($msi.InstallLocation).TrimEnd("\") -eq $InstallDir.TrimEnd("\")) }
    }
    if ($msiHere) {
        throw "Luma is installed with the MSI installer. Update it with a newer MSI, or uninstall it first (Settings > Apps > Luma) and run this script again."
    }

    # Only ever delete a folder that holds a Luma install (or nothing at all).
    function Assert-LumaFolder([string]$dir) {
        if (-not (Test-Path $dir)) { return }
        $items = @(Get-ChildItem -LiteralPath $dir -Force)
        if ($items.Count -eq 0) { return }
        if (-not (Test-Path (Join-Path $dir "luma.exe")) -or -not (Test-Path (Join-Path $dir $marker))) {
            throw "$dir is not empty and is not a Luma install made by this script. Choose another folder with `$env:LUMA_INSTALL_DIR."
        }
    }

    function Assert-NotRunning([string]$dir) {
        $exe = Join-Path $dir "luma.exe"
        $running = Get-Process -Name luma, luma-cli -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -like "$dir\*") }
        if ($running) { throw "Luma is running from $dir. Close it and run the script again." }
    }

    if ($Uninstall) {
        Assert-LumaFolder $InstallDir
        Assert-NotRunning $InstallDir
        if (Test-Path $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
        if (Test-Path $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
        Say "removed $InstallDir and the Start menu shortcut. Sessions and settings in $(Join-Path $env:LOCALAPPDATA 'Luma') are kept."
        return
    }

    # Find the release.
    $headers = @{ "User-Agent" = "luma-install"; "Accept" = "application/vnd.github+json" }
    $api = if ($Version) { "https://api.github.com/repos/$repo/releases/tags/$Version" } else { "https://api.github.com/repos/$repo/releases/latest" }
    try { $release = Invoke-RestMethod -Uri $api -Headers $headers } catch { throw "Could not find the Luma release ($api): $($_.Exception.Message)" }
    $zipAsset = $release.assets | Where-Object { $_.name -like "Luma-*-win-x64.zip" } | Select-Object -First 1
    $sumAsset = $release.assets | Where-Object { $_.name -eq "$($zipAsset.name).sha256" } | Select-Object -First 1
    if (-not $zipAsset -or -not $sumAsset) { throw "Release $($release.tag_name) has no Windows zip with a .sha256 file." }
    Say "installing $($release.tag_name) into $InstallDir"

    Assert-LumaFolder $InstallDir
    Assert-NotRunning $InstallDir

    $work = Join-Path ([IO.Path]::GetTempPath()) ("luma-install-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work $zipAsset.name
        Say "downloading $($zipAsset.name) ($([math]::Round($zipAsset.size / 1MB)) MB)"
        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ "User-Agent" = "luma-install" }
        $sumText = (Invoke-WebRequest -Uri $sumAsset.browser_download_url -UseBasicParsing -Headers @{ "User-Agent" = "luma-install" }).Content
        if ($sumText -is [byte[]]) { $sumText = [Text.Encoding]::ASCII.GetString($sumText) }
        $expected = ($sumText.Trim() -split "\s+")[0].ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -notmatch "^[0-9a-f]{64}$" -or $actual -ne $expected) {
            throw "SHA256 check failed (expected $expected, got $actual). Nothing was installed."
        }
        Say "SHA256 ok"

        $unpacked = Join-Path $work "unpacked"
        Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
        $source = Join-Path $unpacked "Luma"
        if (-not (Test-Path (Join-Path $source "luma.exe"))) { throw "The zip has no Luma\luma.exe." }

        # Replace the program folder: stage next to it, then swap, so a failure leaves the old version usable.
        $parent = Split-Path $InstallDir -Parent
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $staged = "$InstallDir.new"
        $old = "$InstallDir.old"
        foreach ($d in @($staged, $old)) { if (Test-Path $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
        Move-Item -LiteralPath $source -Destination $staged
        Set-Content -LiteralPath (Join-Path $staged $marker) -Value $release.tag_name -Encoding ascii
        if (Test-Path $InstallDir) { Move-Item -LiteralPath $InstallDir -Destination $old }
        try {
            Move-Item -LiteralPath $staged -Destination $InstallDir
        } catch {
            if (Test-Path $old) { Move-Item -LiteralPath $old -Destination $InstallDir }
            throw
        }
        if (Test-Path $old) { Remove-Item -LiteralPath $old -Recurse -Force }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $NoShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = Join-Path $InstallDir "luma.exe"
        $link.WorkingDirectory = $InstallDir
        $link.IconLocation = (Join-Path $InstallDir "assets\icons\luma.ico") + ",0"
        $link.Description = "Luma: video to 3D point cloud"
        $link.Save()
    }

    Say "done. Start Luma from the Start menu or run: & '$(Join-Path $InstallDir 'luma.exe')'"
    Say "the build is not code signed yet; Windows may show 'Unknown publisher' on first start (More info, Run anyway)."
}

Install-Luma @args
