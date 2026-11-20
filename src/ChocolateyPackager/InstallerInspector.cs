using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace ChocolateyPackager;

/// <summary>
/// Reads MSI metadata and bounded samples of EXE files without launching them.
/// The PE machine type describes the executable stub, not necessarily the payload architecture.
/// </summary>
public static class InstallerInspector
{
    private static readonly string[] MsiKeys = ["ProductName", "ProductVersion", "Manufacturer", "ProductCode", "UpgradeCode"];

    public static InstallerAnalysis Analyze(string path)
    {
        var file = new FileInfo(path);
        if (!file.Exists || file.Length == 0) throw new InvalidOperationException("Installateur introuvable ou vide.");
        var extension = file.Extension.ToLowerInvariant();
        if (extension != ".exe" && extension != ".msi")
            throw new InvalidOperationException("Sélectionnez un fichier .msi ou .exe.");

        var filename = Path.GetFileNameWithoutExtension(file.Name);
        var name = Regex.Replace(filename, @"(?i)[-_. ]v?\d+\.\d+(?:\.\d+){0,2}.*$", "");
        name = Regex.Replace(name, @"(?i)([-_. ](?:setup|installer|install|x64|x86|amd64|arm64|win64))+$", "")
            .Trim('-', '_', ' ', '.');
        if (name.Length == 0) name = filename;

        var match = Regex.Match(filename, @"(?i)(?:^|[-_. ])v?(\d+\.\d+(?:\.\d+){0,2})(?:$|[-_. ])");
        var version = match.Success ? match.Groups[1].Value : "";
        var architecture = Regex.IsMatch(filename, @"(?i)(?:^|[-_. ])(?:arm64)(?:$|[-_. ])") ? "arm64"
            : Regex.IsMatch(filename, @"(?i)(?:^|[-_. ])(?:x64|amd64|win64)(?:$|[-_. ])") ? "x64" : "any";
        var warnings = new List<string>();
        var publisher = "";
        var engine = "Non identifié";
        var args = "";
        var confidence = "Inconnue";
        var evidence = "Aucun marqueur exploitable";
        string? productCode = null;
        string? upgradeCode = null;

        if (extension == ".msi")
        {
            var fields = MsiKeys.ToDictionary(key => key, key => ReadMsiProperty(file.FullName, key));
            productCode = fields["ProductCode"];
            upgradeCode = fields["UpgradeCode"];
            if (string.IsNullOrWhiteSpace(productCode))
                throw new InvalidOperationException("Le MSI ne fournit pas de ProductCode lisible.");
            if (!string.IsNullOrWhiteSpace(fields["ProductName"])) name = fields["ProductName"];
            if (Regex.IsMatch(fields["ProductVersion"], @"^\d+\.\d+(\.\d+){0,2}$"))
                version = fields["ProductVersion"];
            publisher = fields["Manufacturer"];
            engine = "Windows Installer (MSI)";
            args = "/qn /norestart REBOOT=ReallySuppress";
            confidence = "Standard MSI";
            evidence = "Propriétés Windows Installer lues en mode lecture seule.";
        }
        else
        {
            var machine = ReadPeMachine(file.FullName);
            if (machine == 0) throw new InvalidOperationException("EXE invalide : signature PE absente ou incorrecte.");
            var info = FileVersionInfo.GetVersionInfo(file.FullName);
            publisher = info.CompanyName ?? "";
            if (string.IsNullOrWhiteSpace(version))
            {
                foreach (var candidate in new[] { info.ProductVersion, info.FileVersion })
                {
                    var m = Regex.Match(candidate ?? "", @"^\s*(\d+\.\d+(?:\.\d+){0,2})");
                    if (m.Success) { version = m.Groups[1].Value; break; }
                }
            }
            if (name.Equals(filename, StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(info.ProductName))
                name = info.ProductName;

            var sample = ReadBoundedSample(file.FullName);
            if (Regex.IsMatch(filename, @"(?i)^everything(?:[-_. ]|$)"))
            {
                engine = "Everything (voidtools)";
                args = "/S";
                confidence = "Éditeur connu";
                evidence = "Nom Everything ; paramètre /S à confirmer avec la version installée.";
            }
            else if (Regex.IsMatch(sample, @"(?i)\.wixburn|WixBundle|WixBurn|Burn.{0,50}Bundle"))
            {
                engine = "WiX Burn";
                args = "/quiet /norestart";
                confidence = "Probable";
                evidence = "Marqueur WiX Burn détecté.";
            }
            else if (Regex.IsMatch(sample, @"(?i)Inno Setup Setup Data|Inno Setup Setup Loader|Inno Setup.{0,50}Copyright"))
            {
                engine = "Inno Setup";
                args = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-";
                confidence = "Probable";
                evidence = "Marqueur Inno Setup détecté.";
            }
            else if (Regex.IsMatch(sample, @"(?i)Nullsoft\.NSIS\.exehead|Nullsoft Install System|NSIS Error"))
            {
                engine = "NSIS";
                args = "/S";
                confidence = "Probable";
                evidence = "Marqueur NSIS détecté ; /S est sensible à la casse.";
            }
            else if (Regex.IsMatch(sample, @"(?i)InstallShield|InstallScript Engine|ISSetup\.dll"))
            {
                engine = "InstallShield";
                confidence = "Partielle";
                evidence = "Options variables selon le projet InstallShield.";
            }
            else if (Regex.IsMatch(sample, @"(?i)Advanced Installer"))
            {
                engine = "Advanced Installer";
                confidence = "Partielle";
                evidence = "Bootstrapper à identifier auprès de l'éditeur.";
            }

            warnings.Add($"L'architecture PE du lanceur est 0x{machine:X4} ; elle ne garantit pas l'architecture du logiciel installé.");
            if (string.IsNullOrEmpty(args))
                warnings.Add("Options silencieuses inconnues : renseigner les paramètres documentés par l'éditeur.");
            warnings.Add("Analyse statique uniquement : valider le résultat sur une VM Windows.");
        }

        var signature = SignatureVerifier.Check(file.FullName);
        if (signature == "Signature incorrecte")
            warnings.Add("ATTENTION : signature Windows incorrecte : ne pas diffuser cet installateur.");
        if (string.IsNullOrWhiteSpace(version))
            warnings.Add("Version non détectée : la saisir manuellement.");
        if (string.IsNullOrWhiteSpace(publisher))
            warnings.Add("Éditeur non identifié : vérifier sa provenance et ses droits de redistribution.");

        return new InstallerAnalysis(
            file.FullName, name, PackageRules.ToPackageId(name), version, publisher,
            extension.TrimStart('.'), architecture, engine, args, confidence, evidence,
            signature, productCode, upgradeCode, file.Length, warnings);
    }

    private static ushort ReadPeMachine(string path)
    {
        using var stream = File.OpenRead(path);
        if (stream.Length < 256) return 0;
        using var reader = new BinaryReader(stream);
        if (reader.ReadUInt16() != 0x5A4D) return 0;
        stream.Position = 0x3C;
        var peOffset = reader.ReadInt32();
        if (peOffset < 64 || peOffset > stream.Length - 6) return 0;
        stream.Position = peOffset;
        if (reader.ReadUInt32() != 0x00004550) return 0;
        return reader.ReadUInt16();
    }

    private static string ReadBoundedSample(string path)
    {
        const int block = 4 * 1024 * 1024;
        using var stream = File.OpenRead(path);
        var chunks = new StringBuilder();
        var positions = stream.Length > block ? new[] { 0L, Math.Max(0L, stream.Length - block) } : new[] { 0L };
        foreach (var position in positions.Distinct())
        {
            stream.Position = position;
            var buffer = new byte[(int)Math.Min(block, stream.Length - position)];
            stream.ReadExactly(buffer);
            chunks.Append(Encoding.Latin1.GetString(buffer));
            chunks.Append(Encoding.Unicode.GetString(buffer, 0, buffer.Length - buffer.Length % 2));
        }
        return chunks.ToString();
    }

    private static string ReadMsiProperty(string path, string property)
    {
        if (!MsiKeys.Contains(property)) throw new ArgumentException("Propriété MSI non autorisée.");
        IntPtr database = IntPtr.Zero, view = IntPtr.Zero, record = IntPtr.Zero;
        try
        {
            if (MsiOpenDatabase(path, IntPtr.Zero, out database) != 0)
                throw new InvalidOperationException("Impossible d'ouvrir la base MSI.");
            var sql = $"SELECT \u0060Value\u0060 FROM \u0060Property\u0060 WHERE \u0060Property\u0060 = '{property}'";
            if (MsiDatabaseOpenView(database, sql, out view) != 0 ||
                MsiViewExecute(view, IntPtr.Zero) != 0 ||
                MsiViewFetch(view, out record) != 0)
                return "";
            uint size = 256;
            var value = new StringBuilder((int)size + 1);
            var code = MsiRecordGetString(record, 1, value, ref size);
            if (code == 234)
            {
                value = new StringBuilder(checked((int)size + 1));
                code = MsiRecordGetString(record, 1, value, ref size);
            }
            return code == 0 ? value.ToString() : "";
        }
        finally
        {
            if (record != IntPtr.Zero) MsiCloseHandle(record);
            if (view != IntPtr.Zero) MsiCloseHandle(view);
            if (database != IntPtr.Zero) MsiCloseHandle(database);
        }
    }

    [DllImport("msi.dll", EntryPoint = "MsiOpenDatabaseW", CharSet = CharSet.Unicode)]
    private static extern uint MsiOpenDatabase(string path, IntPtr persistence, out IntPtr database);
    [DllImport("msi.dll", EntryPoint = "MsiDatabaseOpenViewW", CharSet = CharSet.Unicode)]
    private static extern uint MsiDatabaseOpenView(IntPtr database, string query, out IntPtr view);
    [DllImport("msi.dll")]
    private static extern uint MsiViewExecute(IntPtr view, IntPtr record);
    [DllImport("msi.dll")]
    private static extern uint MsiViewFetch(IntPtr view, out IntPtr record);
    [DllImport("msi.dll", EntryPoint = "MsiRecordGetStringW", CharSet = CharSet.Unicode)]
    private static extern uint MsiRecordGetString(IntPtr record, uint field, StringBuilder buffer, ref uint size);
    [DllImport("msi.dll")]
    private static extern uint MsiCloseHandle(IntPtr handle);
}

/// <summary>
/// Offline Authenticode trust check; does not download certificate revocation data.
/// A status other than "Valide" must not be interpreted as verification.
/// </summary>
internal static class SignatureVerifier
{
    private static readonly Guid VerifyAction = new("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WinTrustFileInfo
    {
        public uint Size;
        public IntPtr Path;
        public IntPtr FileHandle;
        public IntPtr KnownSubject;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WinTrustData
    {
        public uint Size;
        public IntPtr PolicyCallbackData;
        public IntPtr SipClientData;
        public uint UIChoice;
        public uint RevocationChecks;
        public uint UnionChoice;
        public IntPtr FileInfo;
        public uint StateAction;
        public IntPtr StateData;
        public IntPtr UrlReference;
        public uint ProvFlags;
        public uint UIContext;
        public IntPtr SignatureSettings;
    }

    [DllImport("wintrust.dll", PreserveSig = true)]
    private static extern int WinVerifyTrust(IntPtr hwnd, [In] ref Guid actionId, IntPtr trustData);

    public static string Check(string file)
    {
        var pathPtr = IntPtr.Zero;
        var infoPtr = IntPtr.Zero;
        var dataPtr = IntPtr.Zero;
        try
        {
            pathPtr = Marshal.StringToCoTaskMemUni(file);
            var fileInfo = new WinTrustFileInfo { Size = (uint)Marshal.SizeOf<WinTrustFileInfo>(), Path = pathPtr };
            infoPtr = Marshal.AllocHGlobal(Marshal.SizeOf<WinTrustFileInfo>());
            Marshal.StructureToPtr(fileInfo, infoPtr, false);
            var data = new WinTrustData
            {
                Size = (uint)Marshal.SizeOf<WinTrustData>(),
                UIChoice = 2, // WTD_UI_NONE
                RevocationChecks = 0,
                UnionChoice = 1, // WTD_CHOICE_FILE
                FileInfo = infoPtr,
                ProvFlags = 0x00001000 // WTD_CACHE_ONLY_URL_RETRIEVAL
            };
            dataPtr = Marshal.AllocHGlobal(Marshal.SizeOf<WinTrustData>());
            Marshal.StructureToPtr(data, dataPtr, false);
            var action = VerifyAction;
            var status = WinVerifyTrust(IntPtr.Zero, ref action, dataPtr);
            return unchecked((uint)status) switch
            {
                0 => "Valide (hors ligne)",
                0x80096010 => "Signature incorrecte", // TRUST_E_BAD_DIGEST
                0x800B0100 => "Non signé", // TRUST_E_NOSIGNATURE
                0x800B0109 => "Non approuvé (certificat)", // CERT_E_UNTRUSTEDROOT
                0x800B0101 => "Certificat expiré",
                _ => $"Non vérifiée (0x{status:X8})"
            };
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException or MarshalDirectiveException)
        {
            return "Vérification indisponible";
        }
        finally
        {
            if (dataPtr != IntPtr.Zero) Marshal.FreeHGlobal(dataPtr);
            if (infoPtr != IntPtr.Zero) Marshal.FreeHGlobal(infoPtr);
            if (pathPtr != IntPtr.Zero) Marshal.FreeCoTaskMem(pathPtr);
        }
    }
}
