# Luma releases

Public Windows builds of Luma, a Windows 11 application that turns a video into a colored 3D point cloud. The source code is private; this repository only holds the builds and the installer script.

## Install

In PowerShell:

```powershell
irm https://getluma.nohelll.com/script/install.ps1 | iex
```

This installs the newest build into `%LOCALAPPDATA%\Programs\Luma` (no administrator rights needed) and adds a Start menu shortcut. Run the same line again to update. The script checks the SHA256 of the download before it installs anything. Read [site/script/install.ps1](site/script/install.ps1) before running it if you like; it is short.

Options, set before the line above:

```powershell
$env:LUMA_VERSION = "v0.1.0-dev.cb13b6d"   # a specific build (see Releases)
$env:LUMA_INSTALL_DIR = "D:\Apps\Luma"      # another folder
$env:LUMA_NO_SHORTCUT = "1"                 # no Start menu shortcut
$env:LUMA_UNINSTALL = "1"                   # remove Luma (keeps sessions and settings)
```

Manual install: download `Luma-<version>-win-x64.zip` from [Releases](https://github.com/FIEF-nohell/luma-releases/releases), check it against the `.sha256` file, extract it and start `Luma\luma.exe`.

## Requirements

- Windows 11, 64 bit.
- A GPU with OpenGL 4.5 for the viewer. Dense depth runs on DirectML (a Direct3D 12 GPU); without it the sparse point cloud still works.

## Notes

- These are development builds. The builds are not code signed yet, so Windows may show "Unknown publisher" on first start (More info, Run anyway).
- Sessions and settings live in `%LOCALAPPDATA%\Luma`; installing, updating and uninstalling never touch them.
- Third party licenses ship in the zip as `THIRD_PARTY_NOTICES.txt`.

## Repository layout

- `site/`: the only folder Vercel publishes (`vercel.json`): `index.html` (a one page landing at https://getluma.nohelll.com) and `script/install.ps1` (the installer).
- Releases: the builds, published here by the CI of the private Luma repository.
