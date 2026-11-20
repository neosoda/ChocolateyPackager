#requires -Version 5.1
<#
.SYNOPSIS
  Validation statique, sans extraction ni execution, d'un paquet Chocolatey.
.DESCRIPTION
  Controle le manifeste nuspec, les parties OPC, la syntaxe PowerShell et
  l'integrite de l'installateur quand un manifeste packager-info.json existe.
  Ne prouve PAS qu'une installation fonctionne : test en VM indispensable.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName WindowsBase

function Get-PackagePartText {
    param([IO.Packaging.Package]$Package, [string]$PartName, [int]$MaxBytes = 1048576)
    $uri = [IO.Packaging.PackUriHelper]::CreatePartUri([Uri]::new('/' + $PartName, [UriKind]::Relative))
    $part = $Package.GetPart($uri)
    $stream = $part.GetStream([IO.FileMode]::Open, [IO.FileAccess]::Read)
    try {
        if ($stream.CanSeek -and $stream.Length -gt $MaxBytes) { throw "Fichier interne trop volumineux : $PartName" }
        $reader = [IO.StreamReader]::new($stream, ([Text.UTF8Encoding]::new($false)), $true, 4096, $true)
        try {
            $builder = New-Object Text.StringBuilder
            $buffer = New-Object char[] 4096
            while (($count = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                [void]$builder.Append($buffer, 0, $count)
                if ($builder.Length -gt $MaxBytes) { throw "Fichier interne trop volumineux : $PartName" }
            }
            return $builder.ToString()
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-PackagePartHash {
    param([IO.Packaging.Package]$Package, [string]$PartName)
    $uri = [IO.Packaging.PackUriHelper]::CreatePartUri([Uri]::new('/' + $PartName, [UriKind]::Relative))
    $stream = $Package.GetPart($uri).GetStream([IO.FileMode]::Open, [IO.FileAccess]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Test-PackagerPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $issues = New-Object 'System.Collections.Generic.List[object]'
    $id = ''; $version = ''
    $package = $null
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Paquet introuvable : $Path" }
        $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
        $package = [IO.Packaging.Package]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read)
        $parts = @($package.GetParts() | ForEach-Object { [Uri]::UnescapeDataString($_.Uri.OriginalString.TrimStart('/')) })
        foreach ($part in $parts) {
            if ($part -match '(^|/)\.\.(/|$)' -or $part -match '^[A-Za-z]:' -or $part.Contains('\')) {
                $issues.Add([pscustomobject]@{ Level='Erreur'; Code='PATH'; Message="Chemin interne suspect : $part" })
            }
        }

        $manifestRels = @($package.GetRelationshipsByType('http://schemas.microsoft.com/packaging/2010/07/manifest'))
        if ($manifestRels.Count -ne 1) {
            $issues.Add([pscustomobject]@{ Level='Erreur'; Code='RELATION'; Message='Relation NuGet du manifeste absente ou multiple.' })
        }
        $nuspecs = @($parts | Where-Object { $_ -match '^[^/]+\.nuspec$' })
        if ($nuspecs.Count -ne 1) {
            $issues.Add([pscustomobject]@{ Level='Erreur'; Code='NUSPEC'; Message='Un unique manifeste .nuspec racine est requis.' })
        } else {
            if ($manifestRels.Count -eq 1 -and
                [Uri]::UnescapeDataString($manifestRels[0].TargetUri.OriginalString.TrimStart('/')) -cne $nuspecs[0]) {
                $issues.Add([pscustomobject]@{ Level='Erreur'; Code='RELATION_TARGET'; Message='Relation NuGet vers un autre fichier que le nuspec.' })
            }
            try {
                $xmlText = Get-PackagePartText -Package $package -PartName $nuspecs[0]
                $settings = New-Object Xml.XmlReaderSettings
                $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
                $settings.XmlResolver = $null
                $xmlReader = [Xml.XmlReader]::Create(([IO.StringReader]::new($xmlText)), $settings)
                try {
                    $xml = New-Object Xml.XmlDocument
                    $xml.XmlResolver = $null
                    $xml.Load($xmlReader)
                } finally { $xmlReader.Dispose() }
                $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
                $ns.AddNamespace('n', $xml.DocumentElement.NamespaceURI)
                $meta = $xml.SelectSingleNode('/n:package/n:metadata', $ns)
                if ($null -eq $meta) { throw 'Section metadata absente.' }
                $idNode = $meta.SelectSingleNode('n:id', $ns)
                $versionNode = $meta.SelectSingleNode('n:version', $ns)
                $authors = $meta.SelectSingleNode('n:authors', $ns)
                $description = $meta.SelectSingleNode('n:description', $ns)
                if ($idNode) { $id = $idNode.InnerText.Trim() }
                if ($versionNode) { $version = $versionNode.InnerText.Trim() }
                if ($id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='ID'; Message="Identifiant Chocolatey invalide : $id" })
                }
                if ($version -notmatch '^\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$') {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='VERSION'; Message="Version invalide : $version" })
                }
                if (-not $authors -or [string]::IsNullOrWhiteSpace($authors.InnerText)) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='AUTHORS'; Message='Auteurs absents du nuspec.' })
                }
                if (-not $description -or [string]::IsNullOrWhiteSpace($description.InnerText)) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='DESCRIPTION'; Message='Description absente du nuspec.' })
                }
                $urlNode = $meta.SelectSingleNode('n:projectUrl', $ns)
                if (-not $urlNode) {
                    $issues.Add([pscustomobject]@{ Level='Conseil'; Code='PROJECT_URL'; Message='Ajouter le site officiel du logiciel si disponible.' })
                } elseif ($urlNode.InnerText -notmatch '^https://') {
                    $issues.Add([pscustomobject]@{ Level='Avertissement'; Code='PROJECT_URL'; Message='Une URL HTTPS est recommandee.' })
                }
            } catch {
                $issues.Add([pscustomobject]@{ Level='Erreur'; Code='XML'; Message=$_.Exception.Message })
            }
        }

        if ($parts -cnotcontains 'tools/chocolateyInstall.ps1') {
            $issues.Add([pscustomobject]@{ Level='Erreur'; Code='SCRIPT'; Message='tools/chocolateyInstall.ps1 manquant.' })
        } else {
            try {
                $scriptContent = Get-PackagePartText -Package $package -PartName 'tools/chocolateyInstall.ps1'
                $tokens = $null; $parseErrors = $null
                [void][Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$parseErrors)
                foreach ($parseError in $parseErrors) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='POWERSHELL'; Message=$parseError.Message })
                }
                if ($scriptContent -match '(?i)\b(Invoke-Expression|iex)\b') {
                    $issues.Add([pscustomobject]@{ Level='Avertissement'; Code='SCRIPT_RISK'; Message='Invoke-Expression detecte : revoir le script avant diffusion.' })
                }
            } catch {
                $issues.Add([pscustomobject]@{ Level='Erreur'; Code='SCRIPT_READ'; Message=$_.Exception.Message })
            }
        }

        if ($parts -ccontains 'tools/packager-info.json') {
            try {
                $info = Get-PackagePartText -Package $package -PartName 'tools/packager-info.json' | ConvertFrom-Json -ErrorAction Stop
                if ([string]$info.id -cne $id -or [string]$info.version -cne $version) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='MANIFEST'; Message='Identite incoherente entre nuspec et packager-info.json.' })
                }
                $installerParts = @($parts | Where-Object { $_ -match '^tools/installer\.(exe|msi)$' })
                if ($installerParts.Count -ne 1) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='INSTALLER'; Message='Installateur embarque manquant ou ambigu.' })
                } elseif ([string]$info.originalSHA256 -notmatch '^[A-Fa-f0-9]{64}$') {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='HASH_FORMAT'; Message='Empreinte SHA-256 absente ou invalide.' })
                } elseif ((Get-PackagePartHash -Package $package -PartName $installerParts[0]) -cne ([string]$info.originalSHA256).ToUpperInvariant()) {
                    $issues.Add([pscustomobject]@{ Level='Erreur'; Code='HASH_MISMATCH'; Message='Empreinte SHA-256 de l installateur differente du manifeste.' })
                }
                if ($installerParts.Count -eq 1 -and $installerParts[0] -eq 'tools/installer.exe' -and $parts -cnotcontains 'tools/installer.exe.ignore') {
                    $issues.Add([pscustomobject]@{ Level='Avertissement'; Code='EXE_SHIM'; Message='installer.exe.ignore absent : risque de shim Chocolatey non souhaite.' })
                }
            } catch {
                $issues.Add([pscustomobject]@{ Level='Erreur'; Code='MANIFEST_READ'; Message=$_.Exception.Message })
            }
        } else {
            $issues.Add([pscustomobject]@{ Level='Conseil'; Code='NO_MANIFEST'; Message='Aucun packager-info.json : integrite interne non attestee par ce validateur.' })
        }
    } catch {
        $issues.Add([pscustomobject]@{ Level='Erreur'; Code='PACKAGE_OPEN'; Message=$_.Exception.Message })
    } finally {
        if ($null -ne $package) { $package.Close() }
    }
    return [pscustomobject]@{
        IsValid = (@($issues | Where-Object { $_.Level -eq 'Erreur' }).Count -eq 0)
        Id = $id; Version = $version
        Status = 'Validation statique uniquement. Installation Windows non testee.'
        Issues = @($issues.ToArray())
    }
}

