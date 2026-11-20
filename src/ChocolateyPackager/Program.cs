using System.Windows.Forms;

namespace ChocolateyPackager;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 3 && args[0].Equals("--self-test", StringComparison.OrdinalIgnoreCase) &&
            args[1].Equals("--report", StringComparison.OrdinalIgnoreCase))
            return SmokeTests.Run(args[2]);

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm());
        return 0;
    }
}
