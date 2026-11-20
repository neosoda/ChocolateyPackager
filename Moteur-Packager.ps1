#requires -Version 5.1
<#
 .SYNOPSIS
  Fabrique un paquet Chocolatey autonome depuis un MSI ou EXE SANS installer Chocolatey.
 .DESCRIPTION
  Ne lance pas l'installateur. Analyse syntaxique/statique, hash SHA256,
  construction OPC, verification des parties et publication dans le depot.
  Il FAUT faire une installation reelle sur une VM avant diffusion.
 .EXAMPLE
  .\Moteur-Packager.ps1 -Installer 'C:\Temp\Everything-1.4.1.1032.x64-Setup.exe' -Id everything -Version 1.4.1.1032 -SilentArgs /S -OutputDirectory 'C:\ChocoDepot'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Version,
    [string]$SilentArgs,
    [string]$Title,
    [string]$Authors,
    [string]$Description,
    [string]$ProjectUrl,
    [string]$Tags = 'interne hors-ligne offline',
    [ValidateSet('any','x64','x86')][string]$Architecture = 'any',
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName WindowsBase

function XmlEscape([string]$Text) { return [Security.SecurityElement]::Escape($Text) }
function PSQuote([string]$Text) { return "'" + $Text.Replace("'", "''") + "'" }
function Write-Utf8NoBom([string]$File, [string]$Content) {
    [IO.File]::WriteAllText($File, $Content, ([Text.UTF8Encoding]::new($false)))
}
function Add-CMILPackagePart {
    param([IO.Packaging.Package]$Package, [string]$PartName, [string]$SourceFile, [string]$Mime = 'application/octet-stream')
    $uri = [IO.Packaging.PackUriHelper]::CreatePartUri(([Uri]::new(('/' + $PartName), [UriKind]::Relative)))
    $part = $Package.CreatePart($uri, $Mime, [IO.Packaging.CompressionOption]::Maximum)
    $inputStream = [IO.File]::OpenRead($SourceFile)
    try {
        $outputStream = $part.GetStream([IO.FileMode]::Create, [IO.FileAccess]::Write)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
    return $uri
}
function Read-CMILPartHash {
    param([IO.Packaging.Package]$Package, [string]$PartName)
    $uri = [IO.Packaging.PackUriHelper]::CreatePartUri(([Uri]::new(('/' + $PartName), [UriKind]::Relative)))
    if (-not $Package.PartExists($uri)) { throw "Partie absente du .nupkg : $PartName" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = $Package.GetPart($uri).GetStream([IO.FileMode]::Open, [IO.FileAccess]::Read)
        try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

if ($env:OS -ne 'Windows_NT') { throw 'Cette version necessite Windows PowerShell 5.1.' }
$detectorFile = Join-Path $PSScriptRoot 'Detecteur-Installateur.ps1'
if (-not (Test-Path -LiteralPath $detectorFile -PathType Leaf)) { throw 'Detecteur-Installateur.ps1 absent. Extraire toute l archive.' }
. $detectorFile

if ($Id -cnotmatch '^[a-z0-9][a-z0-9._-]{0,79}$') { throw 'ID invalide (80 caracteres maximum, minuscules, chiffres et tirets).' }
if ($Id.EndsWith('-cmil')) { throw 'Suffixe -cmil abandonne : utilisez un identifiant sans ce suffixe.' }
if ($Version -cnotmatch '^\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$') { throw 'Version invalide (ex : 1.4.1.1032).' }
if ($SilentArgs -match '[\r\n]') { throw 'Arguments silencieux sur une seule ligne uniquement.' }
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $Id }
if ($Title.Length -gt 200) { throw 'Titre trop long (maximum 200 caracteres).' }
if ($Description -and $Description.Length -gt 4000) { throw 'Description trop longue (maximum 4000 caracteres).' }
if ($Authors -and $Authors.Length -gt 200) { throw 'Champ auteurs trop long (maximum 200 caracteres).' }
if ($Tags -match '[\r\n,]' -or $Tags.Length -gt 240) { throw 'Tags invalides : ni virgule ni saut de ligne, 240 caracteres maximum.' }
if ($ProjectUrl) {
    $parsedUrl = $null
    if (-not [Uri]::TryCreate($ProjectUrl, [UriKind]::Absolute, [ref]$parsedUrl) -or $parsedUrl.Scheme -ne 'https') {
        throw 'URL du projet invalide : une adresse HTTPS est requise.'
    }
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Depot de destination introuvable : $OutputDirectory" }

$analysis = Get-CMILInstallerAnalysis -Path $Installer
if ($analysis.Signature -eq 'HashMismatch') { throw 'Signature Authenticode corrompue, paquet refuse.' }
if ([string]::IsNullOrWhiteSpace($Authors)) { if ($analysis.Publisher) { $Authors = $analysis.Publisher } else { $Authors = 'Interne' } }
if ([string]::IsNullOrWhiteSpace($Description)) { $Description = 'Paquet interne avec installateur embarque. Test en VM requis avant diffusion.' }
if ($analysis.Type -eq 'exe' -and [string]::IsNullOrWhiteSpace($SilentArgs)) {
    throw 'Arguments silencieux EXE absents. Analyser puis valider avant la publication.'
}
if ($analysis.Type -eq 'msi' -and [string]::IsNullOrWhiteSpace($SilentArgs)) { $SilentArgs = '/qn /norestart REBOOT=ReallySuppress' }
$Installer = $analysis.Path
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
$filename = "$Id.$Version.nupkg"
$destination = Join-Path $OutputDirectory $filename
if (Test-Path -LiteralPath $destination) { throw "Paquet deja present : $destination. Incrementer la version ; aucun ecrasement autorise." }

$sourceSha = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToUpperInvariant()
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('Choco-Packager-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $temporary 'tools'
$bundle = Join-Path $temporary $filename
$installerName = 'installer.' + $analysis.Type
$installerCopy = Join-Path $tools $installerName
$temporaryDest = $null
[void](New-Item -ItemType Directory -Path $tools -Force)

try {
    Copy-Item -LiteralPath $Installer -Destination $installerCopy -ErrorAction Stop
    $copiedSha = (Get-FileHash -LiteralPath $installerCopy -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($sourceSha -ne $copiedSha) { throw 'Empreinte de la copie locale incorrecte.' }

    $projectUrlNode = if ($ProjectUrl) { '    <projectUrl>' + (XmlEscape $ProjectUrl) + '</projectUrl>' } else { '' }
    $nuspec = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>$(XmlEscape $Id)</id>
    <version>$(XmlEscape $Version)</version>
    <title>$(XmlEscape $Title)</title>
    <authors>$(XmlEscape $Authors)</authors>
    <owners>$(XmlEscape $Authors)</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>$(XmlEscape $Description)</description>
$projectUrlNode
    <tags>$(XmlEscape $Tags) $(XmlEscape $Architecture)</tags>
  </metadata>
</package>
"@
    $nuspecFile = Join-Path $temporary ($Id + '.nuspec')
    Write-Utf8NoBom -File $nuspecFile -Content $nuspec
    [xml]$validXml = [IO.File]::ReadAllText($nuspecFile)
    if ($validXml.package.metadata.id -ne $Id) { throw 'Manifest nuspec invalide.' }

    $archCheck = ''
    if ($Architecture -eq 'x64') { $archCheck = 'if (-not [Environment]::Is64BitOperatingSystem) { throw "Ce paquet exige Windows x64." }' }
    # Pour un paquet x86, Windows x64 est compatible : ne pas le bloquer.

    $installerScript = @"
`$ErrorActionPreference = 'Stop'
$archCheck
`$packageName = $(PSQuote $Id)
`$installer = Join-Path `$PSScriptRoot $(PSQuote $installerName)
if (-not (Test-Path -LiteralPath `$installer -PathType Leaf)) { throw 'Installateur embarque manquant.' }
`$realHash = (Get-FileHash -LiteralPath `$installer -Algorithm SHA256).Hash.ToUpperInvariant()
if (`$realHash -ne $(PSQuote $sourceSha)) { throw 'Empreinte SHA256 non conforme. Installation annulee.' }
`$packageArgs = @{
    packageName    = `$packageName
    fileType       = $(PSQuote $analysis.Type)
    file           = `$installer
    silentArgs     = $(PSQuote $SilentArgs)
    validExitCodes = @(0,3010,1641)
}
Install-ChocolateyInstallPackage @packageArgs
"@
    $scriptFile = Join-Path $tools 'chocolateyInstall.ps1'
    Write-Utf8NoBom -File $scriptFile -Content $installerScript
    if ($analysis.Type -eq 'exe') { [IO.File]::WriteAllBytes((Join-Path $tools 'installer.exe.ignore'), [byte[]]@()) }

    $manifest = [ordered]@{
        generator = 'Chocolatey Packager v0.3.0'
        createdUtc = [DateTime]::UtcNow.ToString('o')
        id = $Id; version = $Version
        originalFile = [IO.Path]::GetFileName($Installer)
        originalSHA256 = $sourceSha
        silentArgs = $SilentArgs
        authors = $Authors
        projectUrl = $ProjectUrl
        installerEngine = $analysis.Engine
        detectionConfidence = $analysis.Confidence
        detectionEvidence = $analysis.Evidence
        signatureStatus = $analysis.Signature
        architecture = $Architecture
        validation = 'Structure verifiee. Installation reelle FOG/Chocolatey non testee.'
    }
    $manifestFile = Join-Path $tools 'packager-info.json'
    Write-Utf8NoBom -File $manifestFile -Content ($manifest | ConvertTo-Json -Depth 4)

    # OPC : paquet NuGet/Chocolatey generable avec WindowsBase, sans choco/nuget.
    $package = [IO.Packaging.Package]::Open($bundle, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite)
    try {
        $package.PackageProperties.Creator = 'Chocolatey Packager'
        $package.PackageProperties.Identifier = $Id
        $package.PackageProperties.Version = $Version
        $package.PackageProperties.Description = 'Paquet interne autonome MSI/EXE'
        $nuspecUri = Add-CMILPackagePart -Package $package -PartName ($Id + '.nuspec') -SourceFile $nuspecFile -Mime 'application/octet-stream'
        [void]$package.CreateRelationship($nuspecUri, [IO.Packaging.TargetMode]::Internal, 'http://schemas.microsoft.com/packaging/2010/07/manifest')
        [void](Add-CMILPackagePart -Package $package -PartName 'tools/chocolateyInstall.ps1' -SourceFile $scriptFile)
        [void](Add-CMILPackagePart -Package $package -PartName ('tools/' + $installerName) -SourceFile $installerCopy)
        [void](Add-CMILPackagePart -Package $package -PartName 'tools/packager-info.json' -SourceFile $manifestFile)
        if ($analysis.Type -eq 'exe') {
            [void](Add-CMILPackagePart -Package $package -PartName 'tools/installer.exe.ignore' -SourceFile (Join-Path $tools 'installer.exe.ignore'))
        }
    } finally { $package.Close() }

    # Verification en relisant vraiment l installateur inclus, pas uniquement le ZIP ou sa taille.
    $check = [IO.Packaging.Package]::Open($bundle, [IO.FileMode]::Open, [IO.FileAccess]::Read)
    try {
        foreach ($partName in @(($Id + '.nuspec'),'tools/chocolateyInstall.ps1',('tools/' + $installerName),'tools/packager-info.json')) {
            $partUri = [IO.Packaging.PackUriHelper]::CreatePartUri(([Uri]::new(('/' + $partName), [UriKind]::Relative)))
            if (-not $check.PartExists($partUri)) { throw "Partie absente du paquet : $partName" }
        }
        $relationships = @($check.GetRelationshipsByType('http://schemas.microsoft.com/packaging/2010/07/manifest'))
        if ($relationships.Count -ne 1) { throw 'Relation du manifeste nuget absente ou multiple.' }
        $embeddedHash = Read-CMILPartHash -Package $check -PartName ('tools/' + $installerName)
        if ($embeddedHash -ne $sourceSha) { throw 'SHA256 du binaire contenu dans le .nupkg incorrect.' }
    } finally { $check.Close() }

    # Validation independante avant publication : rejette les manifestes et scripts invalides.
    $validator = Join-Path $PSScriptRoot 'Validateur-Paquet.ps1'
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw 'Validateur-Paquet.ps1 absent : publication refusee.' }
    . $validator
    $validation = Test-CMILPackage -Path $bundle
    if (-not $validation.IsValid) {
        $details = ($validation.Issues | Where-Object { $_.Level -eq 'Erreur' } | ForEach-Object { $_.Code + ': ' + $_.Message }) -join '; '
        throw "Validation du .nupkg echouee : $details"
    }

    # Copie provisoire sur le MEME partage, controle integrite puis publication atomique.
    $temporaryDest = Join-Path $OutputDirectory ('.' + $filename + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $bundle -Destination $temporaryDest -ErrorAction Stop
    $hashBundle = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash
    $hashDest = (Get-FileHash -LiteralPath $temporaryDest -Algorithm SHA256).Hash
    if ($hashBundle -ne $hashDest) { throw 'Erreur SHA256 pendant la copie sur le depot.' }
    if (Test-Path -LiteralPath $destination) { throw 'Une autre creation a publie la meme version : arret sans ecrasement.' }
    Move-Item -LiteralPath $temporaryDest -Destination $destination -ErrorAction Stop
    $temporaryDest = $null

    Write-Output ([pscustomobject]@{
        PackagePath = $destination
        Id = $Id; Version = $Version
        InstallerSHA256 = $sourceSha
        PackageSHA256 = $hashBundle
        ValidationIssues = @($validation.Issues)
        Note = 'Contenu et integrite controles ; installation Windows/FOG non encore testee.'
    })
} finally {
    if ($temporaryDest -and (Test-Path -LiteralPath $temporaryDest)) {
        Remove-Item -LiteralPath $temporaryDest -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}