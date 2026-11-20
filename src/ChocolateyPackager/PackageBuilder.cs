using System.IO.Compression;
using System.Security;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ChocolateyPackager;

/// <summary>
/// Builds a NuGet OPC ZIP archive directly with .NET, without launching choco,
/// powershell.exe, or the selected installer on the packaging machine.
/// </summary>
public static class PackageBuilder
{
    public static string Create(PackageOptions options)
    {
        PackageRules.Check(options);
        var inspection = InstallerInspector.Analyze(options.InstallerPath);
        if (inspection.Signature == "Signature incorrecte")
            throw new InvalidOperationException("Signature Authenticode incorrecte : génération bloquée.");

        var installerType = Path.GetExtension(options.InstallerPath).TrimStart('.').ToLowerInvariant();
        var filename = options.Id + "." + options.Version + ".nupkg";
        var destination = Path.Combine(options.OutputDirectory, filename);
        if (File.Exists(destination))
            throw new IOException("Un package portant cette version existe déjà ; il ne sera pas écrasé.");

        using var source = File.OpenRead(options.InstallerPath);
        var sourceHash = Convert.ToHexString(SHA256.HashData(source));
        source.Position = 0;

        var projectUrlElement = options.ProjectUrl.Length == 0
            ? "" : $"    <projectUrl>{EscapeXml(options.ProjectUrl)}</projectUrl>";
        var nuspec = $"""
            <?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
              <metadata>
                <id>{EscapeXml(options.Id)}</id>
                <version>{EscapeXml(options.Version)}</version>
                <title>{EscapeXml(options.Title)}</title>
                <authors>{EscapeXml(options.Authors)}</authors>
                <owners>{EscapeXml(options.Authors)}</owners>
                <requireLicenseAcceptance>false</requireLicenseAcceptance>
                <description>{EscapeXml(options.Description)}</description>
            {projectUrlElement}
                <tags>offline installer windows {options.Architecture}</tags>
              </metadata>
            </package>
            """;

        var archCheck = options.Architecture == "x64"
            ? "if (-not [Environment]::Is64BitOperatingSystem) { throw 'Ce package exige un OS 64 bits.' }"
            : "";
        var installerName = "installer." + installerType;
        var script = $$"""
            $ErrorActionPreference = 'Stop'
            {{archCheck}}
            $packageName = {{QuotePowerShell(options.Id)}}
            $installer = Join-Path $PSScriptRoot {{QuotePowerShell(installerName)}}
            if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Installateur manquant.' }
            $realHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($realHash -ne {{QuotePowerShell(sourceHash)}}) { throw 'SHA-256 incorrect. Installation annulee.' }
            $packageArgs = @{
                packageName    = $packageName
                fileType       = {{QuotePowerShell(installerType)}}
                file           = $installer
                silentArgs     = {{QuotePowerShell(options.SilentArgs)}}
                validExitCodes = @(0,3010,1641)
            }
            Install-ChocolateyInstallPackage @packageArgs
            """;

        var manifest = JsonSerializer.Serialize(new
        {
            generator = "ChocolateyPackager",
            generatorVersion = "0.4.0",
            createdUtc = DateTimeOffset.UtcNow,
            id = options.Id,
            version = options.Version,
            authors = options.Authors,
            originalFile = Path.GetFileName(options.InstallerPath),
            originalSHA256 = sourceHash,
            silentArgs = options.SilentArgs,
            installerEngine = inspection.Engine,
            detectionConfidence = inspection.Confidence,
            signatureStatus = inspection.Signature,
            architecture = options.Architecture,
            validation = "Statique seulement. Installation et désinstallation non testées."
        }, new JsonSerializerOptions { WriteIndented = true });

        var temp = Path.Combine(options.OutputDirectory, "." + filename + "." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var zip = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: false))
            {
                WriteText(zip, "[Content_Types].xml", ContentTypes);
                WriteText(zip, "_rels/.rels", ManifestRelationship(options.Id + ".nuspec"));
                WriteText(zip, options.Id + ".nuspec", nuspec);
                WriteText(zip, "tools/chocolateyInstall.ps1", script);
                WriteText(zip, "tools/packager-info.json", manifest);
                if (installerType == "exe")
                    WriteText(zip, "tools/installer.exe.ignore", "");
                var binaryEntry = zip.CreateEntry("tools/" + installerName, CompressionLevel.Optimal);
                using var target = binaryEntry.Open();
                source.CopyTo(target);
            }

            var validation = PackageValidator.Validate(temp);
            if (!validation.IsValid)
            {
                var errors = string.Join("; ", validation.Issues
                    .Where(x => x.Severity == "Erreur").Select(x => x.Code + ": " + x.Message));
                throw new InvalidDataException("Package non valide : " + errors);
            }

            // Rename within the destination volume; never replace an existing package.
            File.Move(temp, destination);
            return destination;
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    private static string EscapeXml(string value) =>
        SecurityElement.Escape(value) ?? "";

    private static string QuotePowerShell(string value) =>
        "'" + value.Replace("'", "''", StringComparison.Ordinal) + "'";

    private static void WriteText(ZipArchive zip, string name, string value)
    {
        var entry = zip.CreateEntry(name, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        writer.Write(value);
    }

    private static string ManifestRelationship(string name) =>
        $"""
        <?xml version="1.0" encoding="utf-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Type="http://schemas.microsoft.com/packaging/2010/07/manifest" Target="/{name}" Id="R1" />
        </Relationships>
        """;

    private const string ContentTypes = """
        <?xml version="1.0" encoding="utf-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
          <Default Extension="nuspec" ContentType="application/octet-stream" />
          <Default Extension="ps1" ContentType="application/octet-stream" />
          <Default Extension="exe" ContentType="application/octet-stream" />
          <Default Extension="msi" ContentType="application/octet-stream" />
          <Default Extension="ignore" ContentType="application/octet-stream" />
          <Default Extension="json" ContentType="application/json" />
        </Types>
        """;
}
