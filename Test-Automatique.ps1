#requires -Version 5.1
# Tests NON destructifs du packager ; utilise un FAUX EXE de test non executable.
# N'installe aucun programme et ne modifie aucun vrai depot.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Detecteur-Installateur.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ('cmil-packager-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work -Force
try {
    $filename = Join-Path $work 'InnoDemo-2.3.4.x64-Setup.exe'
    $buffer = New-Object byte[] 2048
    $buffer[0] = 0x4D; $buffer[1] = 0x5A # MZ
    $buffer[0x3c] = 0x80 # offset PE
    $buffer[0x80] = 0x50; $buffer[0x81] = 0x45 # PE\0\0
    $text = [Text.Encoding]::ASCII.GetBytes('Inno Setup Setup Data')
    [Array]::Copy($text,0,$buffer,512,$text.Length)
    [IO.File]::WriteAllBytes($filename,$buffer)

    $a = Get-CMILInstallerAnalysis -Path $filename
    if ($a.Id -ne 'innodemo') { throw "ID incorrect : $($a.Id)" }
    if ($a.Version -ne '2.3.4') { throw "Version incorrecte : $($a.Version)" }
    if ($a.Engine -ne 'Inno Setup') { throw "Moteur non detecte : $($a.Engine)" }
    if ($a.SilentArgs -notmatch '/VERYSILENT') { throw 'Option Inno introuvable.' }
    if ($a.Architecture -ne 'x64') { throw 'Architecture x64 non detectee.' }
    if ((ConvertTo-CMILPackageId 'Everything-CMIL') -ne 'everything') { throw 'Suffixe -cmil non elimine.' }
    Write-Host '[OK] Detection Inno / arguments / ID / version / architecture' -ForegroundColor Green

    $path = Join-Path $work 'fake.exe'
    [IO.File]::WriteAllText($path,'pas un exe')
    try { $null = Get-CMILInstallerAnalysis -Path $path; throw 'FAILLE : binaire invalide accepte' }
    catch { if ($_.Exception.Message -like 'FAILLE*') { throw } }
    Write-Host '[OK] Refus des EXE invalides' -ForegroundColor Green

    # Test structurel du .nupkg (le faux EXE est EMBALLE, jamais execute).
    $res = & (Join-Path $PSScriptRoot 'Moteur-Packager.ps1') -Installer $filename -Id innodemo -Version 2.3.4 -SilentArgs $a.SilentArgs -Architecture x64 -Authors 'Editeur & Tests' -Description 'Package artificiel cree uniquement pour les tests structurels.' -ProjectUrl 'https://example.org' -OutputDirectory $work
    if (-not (Test-Path -LiteralPath $res.PackagePath -PathType Leaf)) { throw 'Fichier .nupkg absent.' }
    Add-Type -AssemblyName WindowsBase
    $zip = [IO.Packaging.Package]::Open($res.PackagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read)
    try {
        foreach ($p in @('innodemo.nuspec','tools/chocolateyInstall.ps1','tools/installer.exe','tools/installer.exe.ignore','tools/packager-info.json')) {
            $uri = [IO.Packaging.PackUriHelper]::CreatePartUri([Uri]::new(('/'+$p),[UriKind]::Relative))
            if (-not $zip.PartExists($uri)) { throw "Fichier manquant du .nupkg : $p" }
        }
    } finally { $zip.Close() }
    if ($res.InstallerSHA256 -ne (Get-FileHash -LiteralPath $filename -Algorithm SHA256).Hash) { throw 'Empreinte source incoherente' }
    . (Join-Path $PSScriptRoot 'Validateur-Paquet.ps1')
    $validation = Test-CMILPackage -Path $res.PackagePath
    if (-not $validation.IsValid) { throw 'Validation du paquet genere echouee.' }
    $pkg = [IO.Packaging.Package]::Open($res.PackagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read)
    try {
        $manifest = Get-CMILPackagePartText -Package $pkg -PartName 'innodemo.nuspec'
        if ($manifest -notmatch 'Editeur &amp; Tests' -or $manifest -notmatch 'https://example.org') { throw 'Metadonnees NuSpec incorrectes ou mal echappees.' }
    } finally { $pkg.Close() }
    Write-Host '[OK] Validation independante et metadonnees XML echappees' -ForegroundColor Green
    $invalid = Join-Path $work 'corrompu.nupkg'
    [IO.File]::WriteAllText($invalid,'not-a-nuget-package')
    if ((Test-CMILPackage -Path $invalid).IsValid) { throw 'Paquet corrompu accepte par le validateur.' }
    Write-Host '[OK] Refus des packages corrompus' -ForegroundColor Green
    Write-Host '[OK] Generation OPC / NuSpec / script / binaire / empreinte SHA256' -ForegroundColor Green
    Write-Host 'Tests structurels reussis. ATTENTION : aucune installation Windows ou FOG testee.' -ForegroundColor Yellow
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}