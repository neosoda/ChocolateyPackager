#requires -Version 5.1
<#
  Chocolatey Packager v0.3.0 - Interface Windows portable.
  Analyse locale MSI/EXE, generation de .nupkg autonomes, sans installation.
  AUCUN installateur selectionne n'est execute ou probe via /?.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'Detecteur-Installateur.ps1')

$script:Engine = Join-Path $PSScriptRoot 'Moteur-Packager.ps1'
$script:Validator = Join-Path $PSScriptRoot 'Validateur-Paquet.ps1'
if (-not (Test-Path -LiteralPath $script:Validator -PathType Leaf)) { throw 'Validateur-Paquet.ps1 manquant.' }
. $script:Validator
$script:ConfiguredDepot = [Environment]::GetEnvironmentVariable('CHOCOLATEY_PACKAGER_DEPOT', 'Process')
$script:DefaultDepot = if ($script:ConfiguredDepot -and (Test-Path -LiteralPath $script:ConfiguredDepot -PathType Container)) {
    $script:ConfiguredDepot
} else {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Chocolatey-Packages'
}
$script:CurrentAnalysis = $null
$script:OutputPackage = $null

function Add-Label {
    param([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H = 23,[int]$Size = 9,[bool]$Bold = $false)
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text
    $l.SetBounds($X,$Y,$W,$H)
    $l.Font = [Drawing.Font]::new('Segoe UI', [single]$Size, $(if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }))
    $l.ForeColor = [Drawing.Color]::FromArgb(64,73,86)
    $script:form.Controls.Add($l)
    return $l
}
function Add-TextBox {
    param([int]$X,[int]$Y,[int]$W,[int]$H = 30)
    $t = New-Object Windows.Forms.TextBox
    $t.SetBounds($X,$Y,$W,$H)
    $t.Font = [Drawing.Font]::new('Segoe UI', 10)
    $t.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $script:form.Controls.Add($t)
    return $t
}
function Add-Button {
    param([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H = 32)
    $b = New-Object Windows.Forms.Button
    $b.Text = $Text
    $b.SetBounds($X,$Y,$W,$H)
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 1
    $b.Font = [Drawing.Font]::new('Segoe UI', 9)
    $b.BackColor = [Drawing.Color]::FromArgb(241,244,248)
    $script:form.Controls.Add($b)
    return $b
}
function Show-Problem([string]$Message) {
    [void][Windows.Forms.MessageBox]::Show($Message,'CMIL Packager','OK','Warning')
}
function Show-Analysis {
    param($Analysis)
    $script:CurrentAnalysis = $Analysis
    $script:txtId.Text = $Analysis.Id
    $script:txtVersion.Text = $Analysis.Version
    $script:txtArgs.Text = $Analysis.SilentArgs
    if ($Analysis.Publisher) { $script:txtPublisher.Text = $Analysis.Publisher } else { $script:txtPublisher.Text = 'Interne' }
    $script:txtDescription.Text = 'Paquet deploiement pour ' + $Analysis.Name + '. A tester sur VM avant toute diffusion.'
    $script:txtProjectUrl.Text = ''
    $script:lblEngine.Text = 'Moteur : ' + $Analysis.Engine
    $script:lblConfidence.Text = 'Fiabilite : ' + $Analysis.Confidence
    $script:lblSignature.Text = 'Signature : ' + $Analysis.Signature
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('Observation : ' + $Analysis.Evidence)
    if ($Analysis.ProductCode) { $lines.Add('Code produit MSI : ' + $Analysis.ProductCode) }
    if ($Analysis.UpgradeCode) { $lines.Add('Code mise a niveau MSI : ' + $Analysis.UpgradeCode) }
    foreach ($w in $Analysis.Warnings) { $lines.Add('ATTENTION : ' + $w) }
    if ($Analysis.Type -eq 'msi') { $lines.Add('MSI : options silencieuses standard. Tester les proprietes requises sur VM.') }
    $script:txtDetails.Text = $lines -join "`r`n"
    if ($Analysis.Type -eq 'exe' -and -not $Analysis.SilentArgs) {
        $script:lblStatus.Text = 'Installateur reconnu partiellement : ajoutez les arguments officiels avant de creer.'
        $script:lblStatus.ForeColor = [Drawing.Color]::FromArgb(147,89,24)
    } else {
        $script:lblStatus.Text = 'Analyse terminee. Verifiez les parametres puis creez le paquet.'
        $script:lblStatus.ForeColor = [Drawing.Color]::FromArgb(37,95,68)
    }
}
function Analyze-SelectedFile {
    $path = $script:txtInstaller.Text.Trim()
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Show-Problem 'Selectionnez un fichier MSI ou EXE existant.'; return }
    try {
        $script:lblStatus.Text = 'Analyse statique en cours...'
        $script:form.Refresh()
        $analysis = Get-CMILInstallerAnalysis -Path $path
        Show-Analysis $analysis
    } catch {
        $script:CurrentAnalysis = $null
        $script:lblStatus.Text = 'Impossible d analyser ce fichier.'
        Show-Problem $_.Exception.Message
    }
}
function Choose-Installer {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Choisir un installateur Windows'
    $dialog.Filter = 'Installateurs MSI et EXE (*.msi;*.exe)|*.msi;*.exe'
    $dialog.CheckFileExists = $true
    if ($dialog.ShowDialog($script:form) -eq [Windows.Forms.DialogResult]::OK) {
        $script:txtInstaller.Text = $dialog.FileName
        Analyze-SelectedFile
    }
    $dialog.Dispose()
}
function Choose-Depot {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Choisir le depot Chocolatey (dossier ou partage interne)'
    if (Test-Path -LiteralPath $script:txtOutput.Text -PathType Container) { $dialog.SelectedPath = $script:txtOutput.Text }
    if ($dialog.ShowDialog($script:form) -eq [Windows.Forms.DialogResult]::OK) { $script:txtOutput.Text = $dialog.SelectedPath }
    $dialog.Dispose()
}

$script:form = New-Object Windows.Forms.Form
$script:form.Text = 'Chocolatey Packager v0.3.0'
$availableHeight = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
$windowHeight = [Math]::Min(850, [Math]::Max(510, $availableHeight - 80))
$script:form.ClientSize = [Drawing.Size]::new(790,$windowHeight)
$script:form.AutoScroll = $true
$script:form.AutoScrollMinSize = [Drawing.Size]::new(770,850)
$script:form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
$script:form.MaximizeBox = $false
$script:form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
$script:form.BackColor = [Drawing.Color]::White
$script:form.Font = [Drawing.Font]::new('Segoe UI', 10)
$script:form.AllowDrop = $true

$title = Add-Label 'Chocolatey Packager' 22 14 740 34 17 $true
$title.ForeColor = [Drawing.Color]::FromArgb(20,72,128)
$sub = Add-Label 'Un MSI / EXE  •  Detection des arguments silencieux  •  Paquet hors ligne' 24 52 735 24 9
$sub.ForeColor = [Drawing.Color]::FromArgb(94,104,116)

$null = Add-Label 'INSTALLATEUR' 24 92 600 24 9 $true
$script:txtInstaller = Add-TextBox 24 119 595
$script:txtInstaller.ReadOnly = $true
$btnBrowse = Add-Button 'Parcourir...' 633 117 132 33
$btnBrowse.Add_Click({ Choose-Installer })

$script:lblEngine = Add-Label 'Moteur : -' 24 159 335 25 9
$script:lblConfidence = Add-Label 'Fiabilite : -' 370 159 180 25 9
$script:lblSignature = Add-Label 'Signature : -' 555 159 230 25 9

$null = Add-Label 'IDENTIFIANT DU PAQUET' 24 205 360 23 9 $true
$null = Add-Label 'VERSION' 406 205 350 23 9 $true
$script:txtId = Add-TextBox 24 230 365
$script:txtVersion = Add-TextBox 406 230 359

$null = Add-Label 'EDITEUR / AUTEUR DU PAQUET' 24 278 360 23 9 $true
$script:txtPublisher = Add-TextBox 24 303 365
$null = Add-Label 'SITE OFFICIEL (HTTPS, FACULTATIF)' 406 278 359 23 9 $true
$script:txtProjectUrl = Add-TextBox 406 303 359
$null = Add-Label 'DESCRIPTION' 24 346 600 23 9 $true
$script:txtDescription = Add-TextBox 24 372 741 42
$script:txtDescription.Multiline = $true
$script:txtDescription.ScrollBars = [Windows.Forms.ScrollBars]::Vertical
$null = Add-Label 'ARGUMENTS D INSTALLATION SILENCIEUSE' 24 427 620 23 9 $true
$script:txtArgs = Add-TextBox 24 453 570
$script:btnAnalyze = Add-Button 'Analyser' 608 452 157 33
$script:btnAnalyze.Add_Click({ Analyze-SelectedFile })
$script:txtDetails = New-Object Windows.Forms.TextBox
$script:txtDetails.SetBounds(24,497,741,100)
$script:txtDetails.Multiline = $true
$script:txtDetails.ReadOnly = $true
$script:txtDetails.ScrollBars = [Windows.Forms.ScrollBars]::Vertical
$script:txtDetails.BackColor = [Drawing.Color]::FromArgb(246,248,251)
$script:txtDetails.Font = [Drawing.Font]::new('Consolas',9)
$script:txtDetails.Text = 'Selectionnez un EXE ou un MSI. L analyse n execute jamais l installateur.'
$script:form.Controls.Add($script:txtDetails)

$null = Add-Label 'DEPOT DE DESTINATION' 24 607 630 24 9 $true
$script:txtOutput = Add-TextBox 24 635 595
$script:txtOutput.Text = $script:DefaultDepot
$btnFolder = Add-Button 'Parcourir...' 633 633 132 33
$btnFolder.Add_Click({ Choose-Depot })

$script:btnCreate = Add-Button 'CREER LE PAQUET .NUPKG' 24 700 552 48
$script:btnCreate.BackColor = [Drawing.Color]::FromArgb(15,90,166)
$script:btnCreate.ForeColor = [Drawing.Color]::White
$script:btnCreate.FlatAppearance.BorderSize = 0
$script:btnCreate.Font = [Drawing.Font]::new('Segoe UI',11,[Drawing.FontStyle]::Bold)

$script:btnValidate = Add-Button 'VALIDER UN .NUPKG' 586 700 179 48
$script:btnValidate.BackColor = [Drawing.Color]::FromArgb(231,239,248)
$script:btnValidate.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Choisir un paquet Chocolatey a verifier'
    $dialog.Filter = 'Packages Chocolatey (*.nupkg)|*.nupkg'
    try {
        if ($dialog.ShowDialog($script:form) -ne [Windows.Forms.DialogResult]::OK) { return }
        $result = Test-CMILPackage -Path $dialog.FileName
        $lines = @($result.Issues | ForEach-Object { '[' + $_.Level + '] ' + $_.Code + ' : ' + $_.Message })
        if ($lines.Count -eq 0) { $lines = @('Aucun probleme structurel detecte.') }
        $prefix = if ($result.IsValid) { 'VALIDATION STATIQUE REUSSIE' } else { 'VALIDATION ECHOUEE' }
        $script:txtDetails.Text = $prefix + "`r`n" + ($lines -join "`r`n")
        $script:lblStatus.Text = $prefix + ' : ' + $dialog.FileName + ' | Test reel en VM requis.'
        if ($result.IsValid) { $script:lblStatus.ForeColor = [Drawing.Color]::DarkGreen } else { $script:lblStatus.ForeColor = [Drawing.Color]::DarkRed }
    } catch { Show-Problem $_.Exception.Message }
    finally { $dialog.Dispose() }
})

$script:lblStatus = Add-Label 'Pret : choisissez un installateur.' 24 773 740 60 9
$script:lblStatus.ForeColor = [Drawing.Color]::FromArgb(91,104,117)

foreach ($target in @($script:form,$script:txtInstaller)) {
    $target.AllowDrop = $true
    $target.Add_DragEnter({
        param($s,$e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = [Windows.Forms.DragDropEffects]::Copy }
    })
    $target.Add_DragDrop({
        param($s,$e)
        $paths = [string[]]$e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
        if ($paths.Count -gt 0 -and [IO.Path]::GetExtension($paths[0]).ToLowerInvariant() -in @('.exe','.msi')) {
            $script:txtInstaller.Text = $paths[0]
            Analyze-SelectedFile
        }
    })
}

$script:btnCreate.Add_Click({
    $id = $script:txtId.Text.Trim().ToLowerInvariant()
    $ver = $script:txtVersion.Text.Trim()
    $args = $script:txtArgs.Text.Trim()
    $authors = $script:txtPublisher.Text.Trim()
    $description = $script:txtDescription.Text.Trim()
    $projectUrl = $script:txtProjectUrl.Text.Trim()
    $depot = $script:txtOutput.Text.Trim()
    $file = $script:txtInstaller.Text.Trim()
    if (-not $script:CurrentAnalysis -or $script:CurrentAnalysis.Path -ne $file) { Show-Problem 'Analysez d abord le fichier choisi.'; return }
    if (-not (Test-Path -LiteralPath $script:Engine -PathType Leaf)) { Show-Problem 'Moteur-Packager.ps1 est absent du dossier. Decompressez toute l archive.'; return }
    if ($id -cnotmatch '^[a-z0-9][a-z0-9._-]{0,79}$' -or $id.EndsWith('-cmil')) { Show-Problem 'ID incorrect : minuscules, chiffres, tirets, sans suffixe -cmil.'; return }
    if ($ver -cnotmatch '^\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$') { Show-Problem 'Version invalide (ex : 1.4.1.1032).'; return }
    if ($args -match '[\r\n]') { Show-Problem 'Arguments sur une seule ligne.'; return }
    if ([string]::IsNullOrWhiteSpace($authors) -or [string]::IsNullOrWhiteSpace($description)) { Show-Problem 'Editeur et description obligatoires.'; return }
    if ($script:CurrentAnalysis.Type -eq 'exe' -and [string]::IsNullOrWhiteSpace($args)) { Show-Problem 'Arguments EXE inconnus : renseignez les options confirmees par l editeur.'; return }
    if (-not (Test-Path -LiteralPath $depot -PathType Container)) {
        $answer = [Windows.Forms.MessageBox]::Show("Le dossier n existe pas :`r`n$depot`r`n`r`nLe creer ?",'Depot inexistant','YesNo','Question')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        try { $null = New-Item -ItemType Directory -Path $depot -Force } catch { Show-Problem $_.Exception.Message; return }
    }
    $targetFile = Join-Path $depot "$id.$ver.nupkg"
    if (Test-Path -LiteralPath $targetFile) { Show-Problem "Paquet deja present :`r`n$targetFile`r`nIncrementer la version pour ne pas ecraser un paquet publie."; return }
    if ($script:CurrentAnalysis.Signature -eq 'HashMismatch') { Show-Problem 'Signature de l installateur non valide : publication interdite.'; return }
    if ($script:CurrentAnalysis.Type -eq 'exe') {
        $text = "Moteur : $($script:CurrentAnalysis.Engine)`r`nArguments : $args`r`n`r`nLes options EXE sont des recommandations statiques, NON testees. Vous devrez essayer le paquet sur une VM avant diffusion.`r`n`r`nCreer le .nupkg ?"
        if ([Windows.Forms.MessageBox]::Show($text,'Confirmation des options EXE','YesNo','Warning') -ne [Windows.Forms.DialogResult]::Yes) { return }
    }
    $script:btnCreate.Enabled = $false
    $script:form.UseWaitCursor = $true
    $script:lblStatus.Text = 'Creation et controles SHA256 en cours : ne fermez pas la fenetre...'
    $script:form.Refresh()
    try {
        $result = & $script:Engine -Installer $file -Id $id -Version $ver -SilentArgs $args -Title $script:CurrentAnalysis.Name -Authors $authors -Description $description -ProjectUrl $projectUrl -Architecture $script:CurrentAnalysis.Architecture -OutputDirectory $depot
        if (-not (Test-Path -LiteralPath $result.PackagePath -PathType Leaf)) { throw 'Le paquet a disparu apres sa creation.' }
        $script:OutputPackage = $result.PackagePath
        $script:lblStatus.ForeColor = [Drawing.Color]::FromArgb(37,118,67)
        $script:lblStatus.Text = 'PAQUET CREE ET VALIDE STATIQUEMENT : ' + $result.PackagePath
        $prompt = "Paquet valide structurellement :`r`n$($result.PackagePath)`r`n`r`nFOG : Package = $id`r`nSource = $depot`r`n`r`nTester ensuite sur VM-TEST avant diffusion.`r`n`r`nAfficher le dossier ?"
        if ([Windows.Forms.MessageBox]::Show($prompt,'Paquet cree','YesNo','Information') -eq [Windows.Forms.DialogResult]::Yes) {
            Start-Process explorer.exe -ArgumentList ('/select,"' + $result.PackagePath + '"')
        }
    } catch {
        $script:lblStatus.ForeColor = [Drawing.Color]::DarkRed
        $script:lblStatus.Text = 'Echec de creation : ' + $_.Exception.Message
        Show-Problem $_.Exception.Message
    } finally {
        $script:form.UseWaitCursor = $false
        $script:btnCreate.Enabled = $true
    }
})

[void]$script:form.ShowDialog()
$script:form.Dispose()