#requires -Version 5.1
# Chocolatey Packager v0.3.0 - Analyse statique uniquement : N'EXECUTE JAMAIS l'installateur.
Set-StrictMode -Version Latest

function ConvertTo-CMILPackageId {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $value = $Name.Normalize([Text.NormalizationForm]::FormD)
    $value = [regex]::Replace($value, '\p{Mn}', '')
    $value = $value.ToLowerInvariant()
    $value = [regex]::Replace($value, '[^a-z0-9._-]+', '-')
    $value = $value.Trim('-','_','.')
    $value = [regex]::Replace($value, '-cmil$', '') # ancien suffixe abandonne
    if ($value.Length -gt 80) { $value = $value.Substring(0,80).TrimEnd('-','_','.') }
    return $value
}

function Get-CMILMsiProperty {
    param([string]$Path, [string]$Property)
    $installer = $null; $db = $null; $view = $null; $record = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, [int]0))
        $sql = "SELECT Value FROM Property WHERE Property = '$Property'"
        $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($sql))
        $null = $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
        $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -ne $record) {
            return [string]$record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @([int]1))
        }
    } catch {
        return ''
    } finally {
        foreach ($o in @($record, $view, $db, $installer)) {
            if ($null -ne $o) {
                try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($o) } catch { }
            }
        }
    }
    return ''
}

function Test-CMILPortableExecutable {
    param([string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 256) { return $false }
        $reader = [IO.BinaryReader]::new($stream)
        try {
            $stream.Position = 0
            if ($reader.ReadUInt16() -ne 23117) { return $false } # MZ
            $stream.Position = 60
            $offset = $reader.ReadInt32()
            if ($offset -lt 64 -or $offset -gt ($stream.Length - 4)) { return $false }
            $stream.Position = $offset
            return ($reader.ReadUInt32() -eq 17744) # PE\0\0
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-CMILExeTextSample {
    param([string]$Path)
    # Lit au maximum 4 Mio au debut et 4 Mio a la fin : une grosse installation
    # ne charge donc pas des centaines de Mio en RAM. Le scan reste partiel.
    $max = 4 * 1024 * 1024
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $chunks = New-Object 'System.Collections.Generic.List[string]'
        $offsets = @(0L)
        if ($stream.Length -gt $max) { $offsets += [long][Math]::Max(0, $stream.Length - $max) }
        foreach ($offset in ($offsets | Select-Object -Unique)) {
            $stream.Position = $offset
            $count = [int][Math]::Min($max, $stream.Length - $offset)
            $buffer = New-Object byte[] $count
            $read = 0
            while ($read -lt $count) {
                $n = $stream.Read($buffer, $read, $count - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            if ($read -ne $count) { throw 'Lecture incomplete de l installateur.' }
            $chunks.Add([Text.Encoding]::GetEncoding(28591).GetString($buffer))
            $chunks.Add([Text.Encoding]::Unicode.GetString($buffer, 0, $buffer.Length - ($buffer.Length % 2)))
        }
        return ($chunks -join "`n")
    } finally { $stream.Dispose() }
}

function Get-CMILInstallerAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if ($env:OS -ne 'Windows_NT') { throw 'L analyse MSI/EXE est prevue pour Windows.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fichier introuvable : $Path" }
    $Path = (Resolve-Path -LiteralPath $Path).ProviderPath
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.exe', '.msi')) { throw 'Choisir un fichier .exe ou .msi.' }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) { throw 'Fichier vide.' }
    $leaf = [IO.Path]::GetFileNameWithoutExtension($Path)
    $name = [regex]::Replace($leaf, '(?i)[-_. ]v?\d+\.\d+(?:\.\d+){0,2}.*$', '')
    $name = [regex]::Replace($name, '(?i)([-_. ](?:setup|installer|install|x64|x86|amd64|win64))+$', '')
    $name = $name.Trim('-','_',' ','.')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $leaf }
    $version = ''
    if ($leaf -match '(?i)(?:^|[-_. ])v?(\d+\.\d+(?:\.\d+){0,2})(?:$|[-_. ])') { $version = $Matches[1] }
    $architecture = 'any'
    if ($leaf -match '(?i)(?:^|[-_. ])(?:x64|amd64|win64)(?:$|[-_. ])') { $architecture = 'x64' }
    $engine = 'Non identifie'
    $args = ''
    $confidence = 'Inconnue'
    $evidence = 'Pas de signature exploitable'
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $signature = 'Non verifiee'
    $productCode = ''
    $manufacturer = ''

    if ($extension -eq '.msi') {
        $msiName = Get-CMILMsiProperty -Path $Path -Property 'ProductName'
        $msiVersion = Get-CMILMsiProperty -Path $Path -Property 'ProductVersion'
        $manufacturer = Get-CMILMsiProperty -Path $Path -Property 'Manufacturer'
        $productCode = Get-CMILMsiProperty -Path $Path -Property 'ProductCode'
        if ([string]::IsNullOrWhiteSpace($productCode)) { throw 'Impossible de valider ce fichier MSI (ProductCode introuvable).' }
        if ($msiName) { $name = $msiName }
        if ($msiVersion -match '^\d+(?:\.\d+){1,3}$') { $version = $msiVersion }
        $engine = 'Windows Installer (MSI)'
        $args = '/qn /norestart REBOOT=ReallySuppress'
        $confidence = 'Standard MSI'
        $evidence = 'Base MSI validee, ProductCode present'
        # Conserver x64 quand le nom MSI indique explicitement x64. Pour x86 ou inconnu, 'any'.
        # x86 reste compatible avec Windows x64, contrairement a l'ancienne V2.
    } else {
        if (-not (Test-CMILPortableExecutable -Path $Path)) { throw 'EXE invalide : en-tete Windows PE absent ou corrompu.' }
        try {
            $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
            $manufacturer = [string]$info.CompanyName
            if (-not $version) {
                foreach ($candidate in @($info.ProductVersion, $info.FileVersion)) {
                    if ($candidate -match '^\s*(\d+\.\d+(?:\.\d+){0,2})') { $version = $Matches[1]; break }
                }
            }
            if ($name -eq $leaf -and -not [string]::IsNullOrWhiteSpace($info.ProductName)) { $name = [string]$info.ProductName }
        } catch { }
        $data = Get-CMILExeTextSample -Path $Path
        # Les signatures sont basees sur le moteur de l'installeur, jamais sur une execution de /?.
        if ($leaf -match '(?i)^everything(?:[-_. ]|$)') {
            $engine = 'Everything (voidtools)'
            $args = '/S'
            $confidence = 'Editeur documente'
            $evidence = 'Nom Everything ; /S documente par voidtools'
        } elseif ($data -match '(?i)\.wixburn|WixBundle|WixBurn|Burn.*Bundle') {
            $engine = 'WiX Burn'
            $args = '/quiet /norestart'
            $confidence = 'Probable'
            $evidence = 'Marqueur WiX Burn trouve dans le binaire'
        } elseif ($data -match '(?i)Inno Setup Setup Data|Inno Setup Setup Loader|Inno Setup.*Copyright') {
            $engine = 'Inno Setup'
            $args = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
            $confidence = 'Probable'
            $evidence = 'Signature Inno Setup detectee'
        } elseif ($data -match '(?i)Nullsoft\.NSIS\.exehead|Nullsoft Install System|NSIS Error|Nullsoft Install System') {
            $engine = 'NSIS (Nullsoft)'
            $args = '/S'
            $confidence = 'Probable'
            $evidence = 'Signature NSIS detectee ; /S sensible a la casse'
        } elseif ($data -match '(?i)InstallShield|InstallScript Engine|ISSetup\.dll') {
            $engine = 'InstallShield'
            $args = '' # modes Basic MSI / InstallScript variables : demande verification
            $confidence = 'Identification partielle'
            $evidence = 'Signature InstallShield ; options differentes selon le projet'
            $warnings.Add('InstallShield : /s seul peut ne pas suffire, rechercher les options de l editeur.')
        } elseif ($data -match '(?i)Advanced Installer') {
            $engine = 'Advanced Installer'
            $args = ''
            $confidence = 'Identification partielle'
            $evidence = 'Signature Advanced Installer ; parametres selon type de bootstrapper'
        } elseif ($data -match '(?i)Squirrel\.Windows|Update\.exe.*--processStart') {
            $engine = 'Squirrel.Windows'
            $args = ''
            $confidence = 'Identification partielle'
            $evidence = 'Signature Squirrel ; il faut verifier son workflow'
        }
        if (-not $args) { $warnings.Add('Options silencieuses a renseigner depuis la documentation de l editeur avant publication.') }
        $warnings.Add('Analyse statique partielle : aucun EXE n est execute ; le silence reel doit etre teste en VM.')
    }

    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ($null -ne $sig) { $signature = [string]$sig.Status }
    } catch { $signature = 'Verification indisponible' }
    if ($signature -eq 'HashMismatch') { $warnings.Add('ATTENTION : signature invalide (HashMismatch). Refuser la publication.') }
    if ($signature -eq 'NotSigned') { $warnings.Add('Fichier non signe : verifier sa provenance et son empreinte.') }

    $id = ConvertTo-CMILPackageId -Name $name
    if (-not $id) { $id = 'logiciel' }
    return [pscustomobject]@{
        Path = $Path; Name = $name; Id = $id; Version = $version
        Type = $extension.TrimStart('.'); Architecture = $architecture
        Engine = $engine; SilentArgs = $args; Confidence = $confidence
        Evidence = $evidence; Warnings = [string[]]$warnings.ToArray()
        Signature = $signature; ProductCode = $productCode; Publisher = $manufacturer
        SizeBytes = [long]$item.Length
    }
}