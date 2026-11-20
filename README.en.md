<div align="center">

# Chocolatey Packager — Windows GUI Chocolatey Package Builder

**Create Chocolatey `.nupkg` packages from MSI and EXE installers with a graphical Windows package builder — no PowerShell scripting required.**

[![Version](https://img.shields.io/badge/version-0.4.0--beta.1-334155)](https://github.com/neosoda/ChocolateyPackager)
![Windows](https://img.shields.io/badge/Windows-10%2F11%2FServer-0078D4)
![.NET](https://img.shields.io/badge/.NET-10-512BD4)
![Status](https://img.shields.io/badge/status-beta-D97706)

[Français](README.md) · **English**

</div>

Looking for a **Chocolatey package builder GUI** or a way to **create a Chocolatey package from an EXE or MSI**? Chocolatey Packager is a portable Windows desktop tool for generating `.nupkg` files. Select an installer, review package metadata and suggested silent switches, then export the package to a local directory or network share. **Chocolatey is not required on the build machine**, but is needed on target machines that install the package.

## Download the portable Windows EXE — v0.4.0-beta.1

Chocolatey Packager is available as **ChocolateyPackager.exe**, a compiled **C# / .NET 10 Windows Forms** desktop application. It builds and validates Chocolatey packages with managed .NET code and **does not launch the repository's PowerShell scripts**. The published self-contained EXE does not require a separately installed .NET runtime.

**[Download ChocolateyPackager.exe](https://github.com/neosoda/ChocolateyPackager/releases/download/v0.4.0-beta.1/ChocolateyPackager.exe)** — [GitHub release and SHA-256 checksum](https://github.com/neosoda/ChocolateyPackager/releases/tag/v0.4.0-beta.1). The Windows x64 executable passed the build and non-destructive smoke tests on `main` ([release workflow](https://github.com/neosoda/ChocolateyPackager/actions/runs/44770344960)). Real Chocolatey installations still require VM testing.

See **[Build and test the single-file EXE](docs/EXECUTABLE.md)**.

The legacy PowerShell launcher (`Start.cmd`) remains available as a fallback until the native app is validated.

## Features

- Windows Forms GUI with file picker and drag-and-drop.
- MSI metadata inspection and static EXE signature analysis, **without launching the installer**.
- Suggested silent switches for MSI, Inno Setup, NSIS, WiX Burn and some known installers. Uncertain detections are clearly flagged.
- Self-contained packages with bundled installers, `.nuspec` manifests and `chocolateyInstall.ps1`.
- SHA-256 integrity checks during packaging and publication.
- Local or network-share output, without overwriting existing packages.

**Requirements:** Windows 10, 11 or Server with Windows PowerShell 5.1. Chocolatey, NuGet, Python and Docker are **not** required to *build* packages.

## Package validation and editable metadata

The GUI now offers editable **publisher, description and HTTPS project URL** fields, and displays the MSI **UpgradeCode** when available.

Before publication, `PackageValidator.ps1` checks the NuGet manifest relationship, XML metadata, PowerShell syntax, package structure and bundled installer SHA-256. Blocking errors stop publication. The GUI can also inspect an existing `.nupkg`.

Run a static validation without installing software:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Validate-Package.ps1" -PackagePath "C:\Packages\example.1.0.0.nupkg"
```

See [Validation and VM testing (FR)](docs/VALIDATION.md) and [References and licensing](docs/REFERENCES.md). **These features still require end-to-end Windows testing**; static validation cannot certify an actual installation.

## Create a Chocolatey package from an EXE or MSI (legacy script version)

1. Download [Chocolatey Packager for Windows (repository ZIP)](https://github.com/neosoda/ChocolateyPackager/archive/refs/heads/main.zip) and extract it.
2. Double-click **`Start.cmd`**.
3. Select an `.msi` or `.exe` installer.
4. Review the package ID, version, silent arguments and output directory.
5. Click **Créer le paquet .nupkg** (*Create package*). The current interface is in French.

The output file uses the format `packageid.version.nupkg`.

### Example

For `Everything-1.4.1.1032.x64-Setup.exe`, the detector may suggest `everything`, version `1.4.1.1032`, and `/S`. The output is `everything.1.4.1.1032.nupkg`.

Confirm silent switches using vendor documentation and a test installation.

## Validate and test a Chocolatey `.nupkg` package

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
PackageValidator.ps1      Static package validation
Validate-Package.ps1      Command-line .nupkg validation
SelfTest.ps1              Non-destructive structural tests
QUICKSTART.txt            FR/EN quick start
```

Generated packages include `packageid.nuspec`, `tools/chocolateyInstall.ps1`, the embedded installer and `tools/packager-info.json`.

## Frequently asked questions about Chocolatey package creation

**How do I convert an EXE or MSI installer into a Chocolatey package?** Run `Start.cmd`, pick your installer, review the package ID, version and silent installation arguments, then select **Create package .nupkg**.

**Do I need Chocolatey installed to build a package?** No. The packager uses Windows PowerShell 5.1 on the build machine. Chocolatey is needed on the computer where you install the generated package.

**Will the detected EXE silent switches always work?** No. Detection is static and must be verified on a disposable Windows test VM.

**Can I use this to deploy software across a business network?** The tool can output a package to a local folder or network share. Check deployment compatibility, access rights and software redistribution licenses first.

For more details: [official Chocolatey package creation documentation](https://docs.chocolatey.org/en-us/create/create-packages/), [validation guide](docs/VALIDATION.md) and [French README](README.md).

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