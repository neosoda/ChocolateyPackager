<div align="center">

# Chocolatey Packager

**Build Chocolatey packages from Windows MSI and EXE installers.**

[![Version](https://img.shields.io/badge/version-0.3.0-334155)](https://github.com/neosoda/ChocolateyPackager)
![Windows](https://img.shields.io/badge/Windows-10%2F11%2FServer-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-4674BE)
![Status](https://img.shields.io/badge/status-beta-D97706)

[Français](README.md) · **English**

</div>

Chocolatey Packager is a portable Windows tool that creates `.nupkg` files without requiring Chocolatey on the packaging machine. Select an installer, review its package ID, version and silent switches, then choose the output directory.

## Features

- Windows Forms GUI with file picker and drag-and-drop.
- MSI metadata inspection and static EXE signature analysis, **without launching the installer**.
- Suggested silent switches for MSI, Inno Setup, NSIS, WiX Burn and some known installers. Uncertain detections are clearly flagged.
- Self-contained packages with bundled installers, `.nuspec` manifests and `chocolateyInstall.ps1`.
- SHA-256 integrity checks during packaging and publication.
- Local or network-share output, without overwriting existing packages.

**Requirements:** Windows 10, 11 or Server with Windows PowerShell 5.1. Chocolatey, NuGet, Python and Docker are **not** required to *build* packages.

## Getting started

1. Download [the repository ZIP](https://github.com/neosoda/ChocolateyPackager/archive/refs/heads/main.zip) and extract it.
2. Double-click **`Start.cmd`**.
3. Select an `.msi` or `.exe` installer.
4. Review the package ID, version, silent arguments and output directory.
5. Click **Créer le paquet .nupkg** (*Create package*). The current interface is in French.

The output file uses the format `packageid.version.nupkg`.

### Example

For `Everything-1.4.1.1032.x64-Setup.exe`, the detector may suggest `everything`, version `1.4.1.1032`, and `/S`. The output is `everything.1.4.1.1032.nupkg`.

Confirm silent switches using vendor documentation and a test installation.

## Validating packages

Run the built-in **structural test**, which does not install any application:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\SelfTest.ps1"
```

To validate an **actual installation**, use a Windows test machine with Chocolatey installed:

```powershell
choco install everything --version 1.4.1.1032 --source="C:\Packages" -y --no-progress
```

Adjust the path and package ID. Check exit codes and logs, and test upgrade/uninstall scenarios before wider deployment.

## Repository layout

```text
Start.cmd                 GUI launcher
ChocolateyPackager.ps1    Windows Forms application
InstallerDetector.ps1     MSI / EXE static analysis
PackageBuilder.ps1        Package generation and verification
SelfTest.ps1              Non-destructive structural tests
QUICKSTART.txt            FR/EN quick start
```

Generated packages include `packageid.nuspec`, `tools/chocolateyInstall.ps1`, the embedded installer and `tools/packager-info.json`.

## Current limitations (0.3.0)

- **There is no universal silent switch for EXE installers.** Detection is a suggestion, not a guarantee. Check vendor documentation when results are uncertain.
- Bundling a web installer does not remove its runtime network dependencies.
- The built-in tests verify **package structure and integrity**, not actual installations. Windows + Chocolatey end-to-end tests are still needed.
- Custom uninstall logic for each application is not generated yet.
- Check third-party licensing and redistribution rights before sharing packages that include proprietary installers.

## Roadmap

- Automated Windows installation tests across multiple setup engines.
- Uninstall and upgrade helpers.
- Improved silent-switch detection with evidence and confidence levels.
- Script previews and publishing to Chocolatey/NuGet feeds.

Questions and contributions: [GitHub Issues](https://github.com/neosoda/ChocolateyPackager/issues).

<sub>Independent community project; not affiliated with Chocolatey Software. **0.3.0 beta**: validate on a test machine before deployment.</sub>