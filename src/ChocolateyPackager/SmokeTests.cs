using System.IO.Compression;
using System.Text;

namespace ChocolateyPackager;

/// <summary>
/// A non-destructive smoke test for the compiled Windows EXE.
/// Creates a synthetic PE header and archives it; never launches the fake installer.
/// </summary>
public static class SmokeTests
{
    public static int Run(string reportPath)
    {
        var messages = new List<string>();
        var work = Path.Combine(Path.GetTempPath(), "ChocolateyPackager-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(work);
            var file = Path.Combine(work, "InnoDemo-2.3.4.x64-Setup.exe");
            var bytes = new byte[4096];
            bytes[0] = 0x4D; bytes[1] = 0x5A; // MZ
            bytes[0x3C] = 0x80;
            bytes[0x80] = 0x50; bytes[0x81] = 0x45; // PE\0\0
            bytes[0x84] = 0x4C; bytes[0x85] = 0x01; // IMAGE_FILE_MACHINE_I386
            Encoding.ASCII.GetBytes("Inno Setup Setup Data").CopyTo(bytes, 512);
            File.WriteAllBytes(file, bytes);

            var analysis = InstallerInspector.Analyze(file);
            Assert(analysis.Id == "innodemo", "Identifiant attendu : innodemo.");
            Assert(analysis.Version == "2.3.4", "Version attendue : 2.3.4.");
            Assert(analysis.Engine == "Inno Setup", "Détection Inno Setup absente.");
            Assert(analysis.SilentArgs.Contains("/VERYSILENT"), "Arguments Inno Setup absents.");
            messages.Add("[OK] Détection statique du fichier PE fictif.");

            var result = PackageBuilder.Create(new PackageOptions(
                file, analysis.Id, analysis.Version, analysis.Name,
                "Éditeur & Tests", "Package de test non exécutable.",
                "https://example.org", analysis.SilentArgs, "x64", work));
            Assert(File.Exists(result), "Fichier .nupkg non généré.");
            var validation = PackageValidator.Validate(result);
            Assert(validation.IsValid, validation.Format());

            using (var zip = ZipFile.OpenRead(result))
            {
                var nuspec = zip.GetEntry("innodemo.nuspec")
                    ?? throw new Exception("Manifeste NuSpec absent.");
                using var reader = new StreamReader(nuspec.Open());
                var xml = reader.ReadToEnd();
                Assert(xml.Contains("Éditeur &amp; Tests"), "Échappement XML incorrect.");
                Assert(xml.Contains("https://example.org"), "URL NuSpec absente.");
            }
            messages.Add("[OK] .nupkg créé, XML échappé et SHA-256 vérifié.");

            var invalid = Path.Combine(work, "broken.nupkg");
            File.WriteAllText(invalid, "not a ZIP package");
            Assert(!PackageValidator.Validate(invalid).IsValid, "Package corrompu accepté.");
            messages.Add("[OK] Refus d'un package corrompu.");
            messages.Add("Aucun logiciel n'a été installé ou désinstallé.");
            return WriteReport(reportPath, messages, true);
        }
        catch (Exception ex)
        {
            messages.Add("[ERREUR] " + ex);
            return WriteReport(reportPath, messages, false);
        }
        finally
        {
            try { if (Directory.Exists(work)) Directory.Delete(work, recursive: true); }
            catch { /* Never suppress test result for a temporary cleanup failure. */ }
        }

        static void Assert(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }

    private static int WriteReport(string path, IEnumerable<string> lines, bool success)
    {
        var report = string.Join(Environment.NewLine, lines) +
            Environment.NewLine + (success ? "RESULT: PASS" : "RESULT: FAIL") + Environment.NewLine;
        Console.WriteLine(report);
        File.WriteAllText(path, report, new UTF8Encoding(false));
        return success ? 0 : 1;
    }
}
