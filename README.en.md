<div align="center">

# 📦 Chocolatey Packager

**Turn a Windows MSI or EXE installer into a self-contained Chocolatey package using a simple desktop GUI.**

[![Version](https://img.shields.io/badge/version-0.3.0-blue?style=flat-square)](https://github.com/neosoda/ChocolateyPackager)
![Windows](https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square&logo=powershell)
![Status](https://img.shields.io/badge/status-beta-orange?style=flat-square)

[Français](README.md) · **English**

</div>

---

## Why this project?

Building a Chocolatey package should not require a complicated toolchain. **Chocolatey Packager** is a lightweight, portable Windows application: select a `.msi` or `.exe`, review its metadata and silent-install arguments, then generate a `.nupkg` with the installer embedded.

Originally built for **software deployment in school computer labs** with internal repositories and restricted internet access, it is equally useful for homelabs and enterprise IT teams. **FOG is optional**; the packager works independently.

## ✨ Features in v0.3.0

| Feature | Description |
| --- | --- |
| 🪟 Windows GUI | WinForms app with file picker and drag-and-drop |
| 🔎 Static analysis | MSI metadata extraction and EXE signature scanning **without executing the installer** |
| 🧩 Silent switches | Suggestions for MSI (`/qn`), Inno Setup, NSIS, WiX Burn and Everything; partial identification of other engines |
| 🏷️ Clean IDs | Package ID normalization, with the former `-cmil` suffix removed |
| 📦 Embedded installers | NuSpec manifest, Chocolatey install script and bundled MSI/EXE |
| 🔐 SHA-256 | Integrity checks for the source file, packaged installer and destination copy |
| 🗂️ Local or SMB output | Choose any writable folder; existing package versions are never silently overwritten |
| 🧪 Structural tests | A non-destructive test script for package generation |

**Chocolatey, NuGet, Docker and Python are not required on the machine _building_ packages.** The app uses Windows PowerShell 5.1 and built-in Windows/.NET components.

> [!IMPORTANT]
> **Beta v0.3.0.** A structurally valid package does **not** guarantee a successful or silent installation. EXE arguments inferred from signatures must be verified against vendor documentation and tested in a VM. Installer analysis never executes the selected binary.

## 🧰 Development branch additions

The existing packaging workflow remains available. The GUI now provides editable **publisher, description and HTTPS project URL** fields; the `.nuspec` escapes XML-sensitive characters.

An independent **offline validator** (`Validateur-Paquet.ps1`) now runs **before publication** to check manifest and install-script presence, PowerShell syntax, required metadata, internal manifest consistency and the bundled installer's SHA-256. Blocking errors prevent publication. A **Valider un .nupkg** button also inspects existing packages.

On Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Validateur-Paquet.ps1" -PackagePath "C:\Packages\example.1.0.0.nupkg"
```

Read [Validation and VM testing (French)](docs/VALIDATION.md) and [References and licensing](docs/REFERENCES.md). **These additions have not been executed in a real Windows environment in this contribution.** Structural validation never proves that a vendor's silent-install switches work.

## 🚀 Quick start

1. Use **[Code → Download ZIP](https://github.com/neosoda/ChocolateyPackager/archive/refs/heads/main.zip)** or clone the repository.
2. Extract **all** files into one directory on **Windows 10/11 or Windows Server** with **Windows PowerShell 5.1**.
3. Double-click **`Lancer.cmd`**.
4. Select or drag in an MSI or EXE installer.
5. Review the package ID, version, **silent arguments** and output directory.
6. Click **Créer le paquet .nupkg** (*Create package*).

The output is `packageid.version.nupkg` in the selected directory. The current GUI is in French.

### Example: Everything

| Field | Example |
| --- | --- |
| Package ID | `everything` |
| Version | `1.4.1.1032` |
| EXE silent arguments | `/S` |
| Output | `C:\Chocolatey-Packages` or an SMB share |
| Package | `everything.1.4.1.1032.nupkg` |

**Still test the actual installation in a disposable VM.**

## 🏗️ Under the hood

```text
Lancer.cmd
   └── CMIL-Packager.ps1              WinForms GUI
        ├── Detecteur-Installateur.ps1 static installer analysis
        └── Moteur-Packager.ps1        NuSpec + Chocolatey script + MSI/EXE
                                     SHA-256 checks + package output
```

A generated `.nupkg` includes:

```text
myapp.1.2.3.nupkg
├── myapp.nuspec
└── tools/
    ├── chocolateyInstall.ps1
    ├── installer.exe (or installer.msi)
    └── packager-info.json
```

Package generation is **offline**, but embedding a **web installer** does not remove the installer's runtime download requirements. Prefer complete/offline installers.

## 🧪 Validation

Run the bundled structural tests from the project directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Test-Automatique.ps1"
```

The tests create a **fake EXE** to inspect detection, NuSpec creation, packaged files and hashes. They **do not** install software or validate Chocolatey/FOG behavior.

On a **Windows test VM with Chocolatey installed**, try your newly generated package:

```powershell
choco install everything --version 1.4.1.1032 --source="C:\Chocolatey-Packages" -y --no-progress
```

Replace the path with your output repository. Inspect Chocolatey logs, exit codes, application state and potential reboot behavior. Validate upgrades and removal before mass deployment.

## 🏢 Internal repository & FOG integration

The repository can be a directory containing `.nupkg` files, e.g. `\\FILESERVER\Deploy$\CHOCOLATEY`. No organization-specific server name is hardcoded into the application.

For a **FOG 1.6 installation with Software/Chocolatey management** configured, an example software record uses:

| FOG field | Value |
| --- | --- |
| Backend | `Chocolatey` |
| Package | `everything` |
| Source | `\\FILESERVER\Deploy$\CHOCOLATEY` |
| Desired state | `Present` |

**Target requirements:** Chocolatey installed/configured, FOG Software module enabled and repository access from the **agent's security context** (often `SYSTEM`, authenticating as the computer account over SMB). This project does not install Chocolatey or configure FOG automatically.

For larger deployments, a dedicated internal **HTTP(S) Chocolatey/NuGet repository** is generally preferable to a plain SMB folder.

## ⚠️ Current limitations

- There is **no universal silent switch for arbitrary EXEs**. InstallShield, Advanced Installer and others may require vendor-specific parameters; the app deliberately avoids guessing where evidence is weak.
- Wrapping a **web bootstrapper** does not create a fully offline installation.
- v0.3.0 **does not generate full custom uninstall logic for every EXE**; upgrades and removals need separate validation.
- File-name-based metadata may be wrong. **Review IDs, versions, licensing and vendor provenance.**
- Included tests check **package structure only**. Real Windows + Chocolatey + FOG end-to-end validation is still required.
- Respect installer redistribution rights; do not publish proprietary installers, credentials or private infrastructure information.

## 🗺️ Roadmap

- [ ] Validate real Chocolatey installs across multiple installer engines.
- [ ] Add uninstall and upgrade helpers.
- [ ] Improve silent-switch detection with vendor references and explicit confidence levels.
- [ ] Add Windows CI tests and a NuSpec/package preview.
- [ ] Support controlled publication to internal HTTP(S) feeds.

## 🤝 Contributing

Bug reports, difficult installer cases and pull requests are welcome. Use [GitHub Issues](https://github.com/neosoda/ChocolateyPackager/issues), and keep commercial binaries, credentials and internal details out of public tickets.

---

<sub>Chocolatey Packager is an independent community project, not affiliated with Chocolatey Software, FOG Project or installer vendors. Current version: **0.3.0 beta**.</sub>