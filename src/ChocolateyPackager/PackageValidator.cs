using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;

namespace ChocolateyPackager;

/// <summary>
/// Non-executing validation of a NuGet/Chocolatey ZIP package.
/// Does not claim that real Windows installation or uninstall will succeed.
/// </summary>
public static class PackageValidator
{
    private static readonly XNamespace RelationshipNamespace =
        "http://schemas.openxmlformats.org/package/2006/relationships";
    private const string ManifestRelation = "http://schemas.microsoft.com/packaging/2010/07/manifest";

    public static ValidationResult Validate(string path)
    {
        var issues = new List<ValidationIssue>();
        var id = "";
        var version = "";
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var zip = new ZipArchive(fs, ZipArchiveMode.Read, leaveOpen: false);
            var parts = zip.Entries.ToDictionary(x => x.FullName, StringComparer.OrdinalIgnoreCase);

            if (parts.Count != zip.Entries.Count)
                Add("Erreur", "DUPLICATE", "Plusieurs fichiers portent le même nom (casse ignorée).");

            foreach (var entry in zip.Entries)
            {
                var name = entry.FullName;
                if (name.StartsWith('/', StringComparison.Ordinal) ||
                    name.Contains('\\') ||
                    name.Split('/').Any(x => x == ".." || x == ".") ||
                    name.Contains(':'))
                    Add("Erreur", "PATH", "Chemin interne suspect : " + name);
            }

            if (!parts.TryGetValue("[Content_Types].xml", out var contentTypes))
                Add("Erreur", "OPC_TYPES", "Fichier OPC [Content_Types].xml absent.");
            else
                try { _ = ParseXml(contentTypes); }
                catch (Exception e) { Add("Erreur", "OPC_TYPES", e.Message); }

            var manifestParts = zip.Entries.Where(x => x.FullName.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase)
                && !x.FullName.Contains('/')).ToList();
            if (manifestParts.Count != 1)
            {
                Add("Erreur", "NUSPEC", "Un unique manifeste .nuspec est requis à la racine.");
            }
            else
            {
                try
                {
                    var xml = ParseXml(manifestParts[0]);
                    var root = xml.Root;
                    if (root?.Name.LocalName != "package")
                        throw new InvalidDataException("Racine XML <package> absente.");
                    var metadata = root.Elements().FirstOrDefault(x => x.Name.LocalName == "metadata")
                        ?? throw new InvalidDataException("Section <metadata> absente.");
                    string Field(string name) => metadata.Elements().FirstOrDefault(x => x.Name.LocalName == name)?.Value.Trim() ?? "";
                    id = Field("id");
                    version = Field("version");
                    if (id.Length == 0 || id.Length > 80 || id.IndexOfAny(['/', '\\', ' ']) >= 0)
                        Add("Erreur", "ID", "Identifiant NuSpec invalide.");
                    if (version.Length == 0) Add("Erreur", "VERSION", "Version NuSpec manquante.");
                    if (Field("authors").Length == 0) Add("Erreur", "AUTHORS", "Éditeur absent.");
                    if (Field("description").Length == 0) Add("Erreur", "DESCRIPTION", "Description absente.");
                }
                catch (Exception e)
                {
                    Add("Erreur", "NUSPEC_XML", "NuSpec invalide : " + e.Message);
                }
            }

            if (!parts.TryGetValue("_rels/.rels", out var relationships))
                Add("Erreur", "RELATION", "Relation OPC du manifeste absente.");
            else
            {
                try
                {
                    var xml = ParseXml(relationships);
                    var matches = xml.Descendants(RelationshipNamespace + "Relationship")
                        .Where(x => (string?)x.Attribute("Type") == ManifestRelation).ToList();
                    if (matches.Count != 1)
                        Add("Erreur", "RELATION", "Relation NuGet du manifeste absente ou multiple.");
                    else if (manifestParts.Count == 1 &&
                             ((string?)matches[0].Attribute("Target"))?.TrimStart('/') != manifestParts[0].FullName)
                        Add("Erreur", "RELATION", "Relation NuGet vers un autre fichier que le manifeste.");
                }
                catch (Exception e)
                {
                    Add("Erreur", "RELATION_XML", "Relations OPC non valides : " + e.Message);
                }
            }

            if (!parts.TryGetValue("tools/chocolateyInstall.ps1", out var script))
                Add("Erreur", "SCRIPT", "Script chocolateyInstall.ps1 absent.");
            else
            {
                try
                {
                    var text = ReadText(script, 1024 * 1024);
                    if (text.Contains("Invoke-Expression", StringComparison.OrdinalIgnoreCase))
                        Add("Avertissement", "SCRIPT_RISK", "Invoke-Expression détecté : examiner manuellement le script.");
                    // The generated script is a known fixed template. This check is intentionally NOT
                    // advertised as a full PowerShell grammar parser.
                    if (text.Length == 0)
                        Add("Erreur", "SCRIPT_EMPTY", "Script d'installation vide.");
                }
                catch (Exception e) { Add("Erreur", "SCRIPT_READ", e.Message); }
            }

            if (parts.TryGetValue("tools/packager-info.json", out var manifest))
            {
                try
                {
                    using var info = JsonDocument.Parse(ReadText(manifest, 1024 * 1024));
                    var root = info.RootElement;
                    string Value(string key) => root.TryGetProperty(key, out var property)
                        ? property.GetString() ?? "" : "";
                    if (Value("id") != id || Value("version") != version)
                        Add("Erreur", "MANIFEST", "ID/version incohérents entre NuSpec et packager-info.json.");
                    var hash = Value("originalSHA256");
                    var installerParts = zip.Entries.Where(x => x.FullName.Equals("tools/installer.exe", StringComparison.OrdinalIgnoreCase) ||
                        x.FullName.Equals("tools/installer.msi", StringComparison.OrdinalIgnoreCase)).ToList();
                    if (installerParts.Count != 1)
                        Add("Erreur", "INSTALLER", "Installateur embarqué manquant ou ambigu.");
                    else if (hash.Length != 64 || !hash.All(Uri.IsHexDigit))
                        Add("Erreur", "HASH_FORMAT", "SHA-256 absent ou incorrect.");
                    else
                    {
                        using var stream = installerParts[0].Open();
                        var realHash = Convert.ToHexString(SHA256.HashData(stream));
                        if (!realHash.Equals(hash, StringComparison.OrdinalIgnoreCase))
                            Add("Erreur", "HASH_MISMATCH", "SHA-256 de l'installateur embarqué incorrect.");
                    }
                    if (installerParts.Count == 1 && installerParts[0].FullName.Equals("tools/installer.exe", StringComparison.OrdinalIgnoreCase) &&
                        !parts.ContainsKey("tools/installer.exe.ignore"))
                        Add("Avertissement", "EXE_SHIM", "Fichier installer.exe.ignore absent ; un shim inattendu peut être créé.");
                }
                catch (Exception e) { Add("Erreur", "MANIFEST_READ", e.Message); }
            }
            else
                Add("Conseil", "NO_MANIFEST", "Sans packager-info.json, impossible de comparer le SHA-256 du logiciel embarqué.");
        }
        catch (Exception e)
        {
            Add("Erreur", "PACKAGE_OPEN", "Impossible de lire le package : " + e.Message);
        }

        return new ValidationResult(!issues.Any(x => x.Severity == "Erreur"), id, version, issues);

        void Add(string severity, string code, string message) =>
            issues.Add(new ValidationIssue(severity, code, message));
    }

    private static XDocument ParseXml(ZipArchiveEntry entry)
    {
        if (entry.Length > 1024 * 1024) throw new InvalidDataException("XML trop volumineux.");
        using var stream = entry.Open();
        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = 1024 * 1024
        };
        using var reader = XmlReader.Create(stream, settings);
        return XDocument.Load(reader);
    }

    private static string ReadText(ZipArchiveEntry entry, int limit)
    {
        if (entry.Length > limit) throw new InvalidDataException("Fichier texte interne trop volumineux.");
        using var input = entry.Open();
        using var reader = new StreamReader(input, new UTF8Encoding(false, true), detectEncodingFromByteOrderMarks: true);
        var text = reader.ReadToEnd();
        if (text.Length > limit) throw new InvalidDataException("Fichier texte interne trop volumineux.");
        return text;
    }
}
