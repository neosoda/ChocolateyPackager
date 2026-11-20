using System.Drawing;
using System.Windows.Forms;

namespace ChocolateyPackager;

public sealed class MainForm : Form
{
    private readonly TextBox _installer = NewBox(readOnly: true);
    private readonly TextBox _id = NewBox();
    private readonly TextBox _version = NewBox();
    private readonly TextBox _title = NewBox();
    private readonly TextBox _authors = NewBox();
    private readonly TextBox _description = NewBox(multiline: true);
    private readonly TextBox _projectUrl = NewBox();
    private readonly TextBox _silentArgs = NewBox();
    private readonly TextBox _output = NewBox();
    private readonly TextBox _details = NewBox(readOnly: true, multiline: true);
    private readonly ComboBox _arch = new() { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
    private readonly Label _status = new() { Text = "Prêt — choisissez un installateur.", AutoSize = true, ForeColor = Color.FromArgb(75, 91, 113) };
    private readonly Button _build = NewButton("Créer le package .nupkg", primary: true);
    private readonly Button _analyze = NewButton("Analyser");
    private readonly Button _browse = NewButton("Parcourir…");
    private readonly Button _verify = NewButton("Valider un .nupkg");
    private readonly Button _selectOutput = NewButton("Dossier…");
    private InstallerAnalysis? _analysis;

    public MainForm()
    {
        Text = "Chocolatey Packager — Windows Package Builder";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(710, 540);
        Size = new Size(970, 870);
        BackColor = Color.FromArgb(248, 250, 254);
        Font = new Font("Segoe UI", 10f);
        AutoScaleMode = AutoScaleMode.Dpi;

        _arch.Items.AddRange(["any", "x86", "x64", "arm64"]);
        _arch.SelectedIndex = 0;
        _build.Enabled = false;
        _output.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Chocolatey-Packages");
        _details.ScrollBars = ScrollBars.Vertical;
        _details.Height = 105;
        _details.BackColor = Color.FromArgb(239, 244, 252);
        _details.Text = "Aucun fichier analysé. Le programme ne lance jamais l'installateur sélectionné.";

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(25, 18, 25, 20),
            ColumnCount = 2,
            GrowStyle = TableLayoutPanelGrowStyle.AddRows
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        Controls.Add(root);
        var row = 0;

        var heading = new Label
        {
            Text = "Chocolatey Packager",
            Font = new Font("Segoe UI Semibold", 23f, FontStyle.Bold),
            ForeColor = Color.FromArgb(26, 65, 122),
            Height = 55,
            AutoSize = false,
            Dock = DockStyle.Fill
        };
        AddWide(heading, 65);
        AddWide(new Label
        {
            Text = "Convertissez un EXE ou MSI en package Chocolatey autonome. Aucun moteur PowerShell externe requis pour créer le paquet.",
            AutoSize = true,
            MaximumSize = new Size(850, 0),
            ForeColor = Color.FromArgb(74, 87, 106)
        }, 52);

        var fileRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, Height = 45 };
        fileRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        fileRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        fileRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 115));
        _installer.Dock = DockStyle.Fill;
        fileRow.Controls.Add(_installer, 0, 0);
        fileRow.Controls.Add(_browse, 1, 0);
        fileRow.Controls.Add(_analyze, 2, 0);
        AddWide(Field("INSTALLATEUR MSI / EXE", fileRow, 78), 85);

        AddPair(Field("IDENTIFIANT DU PACKAGE", _id), Field("VERSION", _version));
        AddPair(Field("NOM DU LOGICIEL", _title), Field("ÉDITEUR / AUTEUR", _authors));
        AddPair(Field("SITE OFFICIEL HTTPS (OPTIONNEL)", _projectUrl), Field("ARCHITECTURE", _arch));
        AddWide(Field("DESCRIPTION DU PACKAGE", _description, 105), 112);
        AddWide(Field("PARAMÈTRES D'INSTALLATION SILENCIEUSE", _silentArgs), 82);
        AddWide(Field("ANALYSE ET AVERTISSEMENTS", _details, 155), 165);

        var folderRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Height = 43 };
        folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 135));
        _output.Dock = DockStyle.Fill;
        folderRow.Controls.Add(_output, 0, 0);
        folderRow.Controls.Add(_selectOutput, 1, 0);
        AddWide(Field("DOSSIER DE DESTINATION", folderRow, 77), 84);

        _build.Height = 47;
        _verify.Height = 47;
        _build.Dock = DockStyle.Fill;
        _verify.Dock = DockStyle.Fill;
        AddPair(_build, _verify, 62);
        AddWide(_status, 44);

        _browse.Click += (_, _) => ChooseInstaller();
        _analyze.Click += async (_, _) => await AnalyzeAsync(_installer.Text);
        _selectOutput.Click += (_, _) => ChooseOutput();
        _build.Click += async (_, _) => await BuildAsync();
        _verify.Click += async (_, _) => await ValidateAsync();

        AllowDrop = true;
        _installer.AllowDrop = true;
        DragEnter += FileDragEnter;
        DragDrop += FileDragDrop;
        _installer.DragEnter += FileDragEnter;
        _installer.DragDrop += FileDragDrop;

        void AddWide(Control control, int height)
        {
            control.Margin = new Padding(4, 2, 4, 4);
            control.Dock = DockStyle.Fill;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
            root.Controls.Add(control, 0, row);
            root.SetColumnSpan(control, 2);
            row++;
        }

        void AddPair(Control left, Control right, int height = 79)
        {
            left.Margin = new Padding(4, 2, 9, 6);
            right.Margin = new Padding(9, 2, 4, 6);
            left.Dock = DockStyle.Fill;
            right.Dock = DockStyle.Fill;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
            root.Controls.Add(left, 0, row);
            root.Controls.Add(right, 1, row);
            row++;
        }
    }

    private static Control Field(string title, Control input, int height = 72)
    {
        var field = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Height = height,
            Margin = new Padding(1),
        };
        field.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        field.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        field.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        field.Controls.Add(new Label
        {
            Text = title,
            ForeColor = Color.FromArgb(49, 70, 99),
            Font = new Font("Segoe UI Semibold", 9f, FontStyle.Bold),
            AutoSize = false,
            Dock = DockStyle.Fill
        }, 0, 0);
        input.Dock = DockStyle.Fill;
        field.Controls.Add(input, 0, 1);
        return field;
    }

    private static TextBox NewBox(bool readOnly = false, bool multiline = false) => new()
    {
        ReadOnly = readOnly,
        Multiline = multiline,
        Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.FixedSingle,
        Font = new Font("Segoe UI", 10.3f),
        BackColor = readOnly ? Color.FromArgb(242, 246, 253) : Color.White,
        ScrollBars = multiline ? ScrollBars.Vertical : ScrollBars.None
    };

    private static Button NewButton(string title, bool primary = false)
    {
        var result = new Button
        {
            Text = title,
            Dock = DockStyle.Fill,
            FlatStyle = FlatStyle.Flat,
            BackColor = primary ? Color.FromArgb(33, 91, 195) : Color.FromArgb(227, 236, 250),
            ForeColor = primary ? Color.White : Color.FromArgb(30, 66, 119),
            Font = new Font("Segoe UI Semibold", 9.4f, FontStyle.Bold),
            Cursor = Cursors.Hand,
            Margin = new Padding(5)
        };
        result.FlatAppearance.BorderSize = 0;
        return result;
    }

    private void ChooseInstaller()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Installateurs Windows (*.exe;*.msi)|*.exe;*.msi",
            Title = "Sélectionner un installateur",
            CheckFileExists = true
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            _ = AnalyzeAsync(dialog.FileName);
    }

    private void FileDragEnter(object? sender, DragEventArgs e)
    {
        var files = e.Data?.GetData(DataFormats.FileDrop) as string[];
        e.Effect = files is { Length: > 0 } && IsInstaller(files[0])
            ? DragDropEffects.Copy : DragDropEffects.None;
    }

    private void FileDragDrop(object? sender, DragEventArgs e)
    {
        var files = e.Data?.GetData(DataFormats.FileDrop) as string[];
        if (files is { Length: > 0 } && IsInstaller(files[0]))
            _ = AnalyzeAsync(files[0]);
    }

    private static bool IsInstaller(string path) =>
        Path.GetExtension(path).Equals(".msi", StringComparison.OrdinalIgnoreCase)
        || Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase);

    private void ChooseOutput()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choisir le dossier contenant les packages",
            UseDescriptionForTitle = true
        };
        if (Directory.Exists(_output.Text)) dialog.InitialDirectory = _output.Text;
        if (dialog.ShowDialog(this) == DialogResult.OK) _output.Text = dialog.SelectedPath;
    }

    private async Task AnalyzeAsync(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) { ShowError("Choisissez un installateur."); return; }
        Busy(true, "Analyse statique de l'installateur…");
        _installer.Text = path;
        _analysis = null;
        try
        {
            var result = await Task.Run(() => InstallerInspector.Analyze(path));
            _analysis = result;
            _id.Text = result.Id;
            _title.Text = result.Name;
            _version.Text = result.Version;
            _authors.Text = string.IsNullOrWhiteSpace(result.Publisher) ? "Package maintainer" : result.Publisher;
            _description.Text = $"Package Chocolatey pour {result.Name}. À tester en VM avant déploiement.";
            _projectUrl.Text = "";
            _arch.SelectedItem = result.Architecture;
            _silentArgs.Text = result.SilentArgs;
            _details.Text =
                $"Moteur : {result.Engine} | Confiance : {result.Confidence}" + Environment.NewLine +
                $"Signature : {result.Signature} | Architecture déclarée : {result.Architecture}" + Environment.NewLine +
                result.Evidence + Environment.NewLine +
                (result.ProductCode is null ? "" : $"ProductCode : {result.ProductCode}" + Environment.NewLine) +
                (result.UpgradeCode is null ? "" : $"UpgradeCode : {result.UpgradeCode}" + Environment.NewLine) +
                string.Join(Environment.NewLine, result.Warnings.Select(x => "ATTENTION : " + x));
            Status("Analyse terminée. Vérifiez les informations avant de créer le package.");
        }
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Busy(false); }
    }

    private async Task BuildAsync()
    {
        if (_analysis is null) { ShowError("Analysez un installateur avant de créer un package."); return; }
        try
        {
            var output = _output.Text.Trim();
            if (!Directory.Exists(output))
            {
                if (MessageBox.Show(this, "Créer le dossier de destination ?", "Dossier absent",
                        MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                Directory.CreateDirectory(output);
            }
            var settings = new PackageOptions(_installer.Text, _id.Text.Trim().ToLowerInvariant(),
                _version.Text.Trim(), _title.Text.Trim(), _authors.Text.Trim(), _description.Text.Trim(),
                _projectUrl.Text.Trim(), _silentArgs.Text.Trim(),
                _arch.SelectedItem?.ToString() ?? "any", output);
            PackageRules.Check(settings);

            if (_analysis.Signature == "Signature incorrecte")
                throw new InvalidOperationException("Cet installateur possède une signature incorrecte.");
            if (_analysis.Type == "exe" &&
                MessageBox.Show(this,
                    $"Moteur : {_analysis.Engine}\nArguments : {settings.SilentArgs}\n\n" +
                    "Les paramètres n'ont PAS été testés. Confirmez-vous leur utilisation ?",
                    "Confirmation des arguments EXE", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
                return;

            Busy(true, "Génération et vérification SHA-256…");
            var path = await Task.Run(() => PackageBuilder.Create(settings));
            Status("Package créé et validé statiquement : " + path);
            if (MessageBox.Show(this,
                    "Package généré :\n" + path + "\n\nL'installation doit être testée sur une VM Windows.\n\nAfficher le dossier ?",
                    "Package créé", MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        }
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Busy(false); }
    }

    private async Task ValidateAsync()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Packages Chocolatey (*.nupkg)|*.nupkg",
            Title = "Vérifier un package Chocolatey"
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        Busy(true, "Validation statique du .nupkg…");
        try
        {
            var result = await Task.Run(() => PackageValidator.Validate(dialog.FileName));
            _details.Text = result.Format();
            Status(result.IsValid ? "Package valide structurellement. Test en VM requis."
                : "Package invalide. Examinez les erreurs ci-dessus.");
            if (!result.IsValid) MessageBox.Show(this, result.Format(), "Validation du package",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch (Exception ex) { ShowError(ex.Message); }
        finally { Busy(false); }
    }

    private void Busy(bool active, string? message = null)
    {
        _browse.Enabled = !active;
        _analyze.Enabled = !active;
        _selectOutput.Enabled = !active;
        _verify.Enabled = !active;
        _build.Enabled = !active && _analysis is not null;
        UseWaitCursor = active;
        if (active && message is not null) Status(message);
    }

    private void Status(string message) => _status.Text = message;

    private void ShowError(string error)
    {
        Status("Erreur : " + error);
        MessageBox.Show(this, error, "Chocolatey Packager", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }
}
