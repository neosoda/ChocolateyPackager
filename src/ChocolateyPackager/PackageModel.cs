using System.Text.RegularExpressions;

namespace ChocolateyPackager;

public sealed record InstallerAnalysis(
    string Path,
    string Name,
    string Id,
    string Version,
    string Publisher,
    string Type,
    string Architecture,
    string Engine,
    string SilentArgs,
    string Confidence,
    string Evidence,
    string Signature,
    string? ProductCode,
    string? UpgradeCode,
    long SizeBytes,
    IReadOnlyList<string> Warnings);

public sealed record PackageOptions(
    string InstallerPath,
    string Id,
    string Version,
    string Title,
    string Authors,
    string Description,
    string ProjectUrl,
    string SilentArgs,
    string Architecture,
    string OutputDirectory);

public sealed record ValidationIssue(string Severity, string Code, string Message);

public sealed record ValidationResult(
    bool IsValid,
    string Id,
    string Version,
    IReadOnlyList<ValidationIssue> Issues)
{
    public string Format()
    {
        var header = IsValid ? "Validation statique réussie." : "Échec de la validation statique.";
        return header + Environment.NewLine
            + "Un test d'installation Windows/Chocolatey reste indispensable."
            + Environment.NewLine + Environment.NewLine
            + (Issues.Count == 0
                ? "Aucune anomalie structurelle détectée."
                : string.Join(Environment.NewLine, Issues.Select(x => $"[{x.Severity}] {x.Code} : {x.Message}")));
    }
}

public static partial class PackageRules
{
    [GeneratedRegex(@"^[a-z0-9][a-z0-9._-]{0,79}$", RegexOptions.CultureInvariant)]
    private static partial Regex IdPattern();

    [GeneratedRegex(@"^\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$", RegexOptions.CultureInvariant)]
    private static partial Regex VersionPattern();

    public static void Check(PackageOptions options)
    {
        if (!File.Exists(options.InstallerPath))
            throw new InvalidOperationException("L'installateur sélectionné n'existe plus.");
        if (!IdPattern().IsMatch(options.Id))
            throw new InvalidOperationException("Identifiant incorrect : 1 à 80 caractères (a-z, 0-9, ., _, -).");
        if (!VersionPattern().IsMatch(options.Version))
            throw new InvalidOperationException("Version incorrecte (ex. : 1.4.1.1032).");
        if (!new[] { "exe", "msi" }.Contains(Path.GetExtension(options.InstallerPath).TrimStart('.').ToLowerInvariant()))
            throw new InvalidOperationException("Seuls les installateurs EXE et MSI sont pris en charge.");
        if (!new[] { "any", "x86", "x64", "arm64" }.Contains(options.Architecture))
            throw new InvalidOperationException("Architecture non reconnue.");
        if (string.IsNullOrWhiteSpace(options.Title) || options.Title.Length > 200)
            throw new InvalidOperationException("Le titre est obligatoire (200 caractères maximum).");
        if (string.IsNullOrWhiteSpace(options.Authors) || options.Authors.Length > 200)
            throw new InvalidOperationException("L'éditeur est obligatoire (200 caractères maximum).");
        if (string.IsNullOrWhiteSpace(options.Description) || options.Description.Length > 4000)
            throw new InvalidOperationException("La description est obligatoire (4 000 caractères maximum).");
        if (options.SilentArgs.Contains('\r') || options.SilentArgs.Contains('\n'))
            throw new InvalidOperationException("Les arguments silencieux doivent tenir sur une ligne.");
        if (Path.GetExtension(options.InstallerPath).Equals(".exe", StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrWhiteSpace(options.SilentArgs))
            throw new InvalidOperationException("Pour un EXE, confirmez les arguments d'installation silencieuse.");
        if (options.ProjectUrl.Length > 0 &&
            (!Uri.TryCreate(options.ProjectUrl, UriKind.Absolute, out var uri) ||
             uri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(uri.UserInfo)))
            throw new InvalidOperationException("L'URL du logiciel doit être en HTTPS, sans identifiants intégrés.");
        if (!Directory.Exists(options.OutputDirectory))
            throw new InvalidOperationException("Le dossier de destination n'existe pas.");
    }

    public static string ToPackageId(string name)
    {
        var normalized = name.Normalize(System.Text.NormalizationForm.FormD);
        normalized = Regex.Replace(normalized, @"\p{Mn}", "");
        normalized = Regex.Replace(normalized.ToLowerInvariant(), @"[^a-z0-9._-]+", "-").Trim('-', '_', '.');
        return normalized.Length > 80 ? normalized[..80].Trim('-', '_', '.') : normalized;
    }
}
