using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;

namespace DieCloud;

public static class Program
{
    private const string MutexName = "Global\\DieCloud_Windows_SingleInstance_Mutex";

    [STAThread]
    public static void Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            LogCrash(e.ExceptionObject?.ToString() ?? "Unknown unhandled exception");
        };

        try
        {
            using var mutex = new Mutex(true, MutexName, out bool isNewInstance);
            if (!isNewInstance)
            {
                var hWnd = FindWindow(null, "DieCloud");
                if (hWnd != IntPtr.Zero)
                {
                    ShowWindow(hWnd, SW_RESTORE);
                    SetForegroundWindow(hWnd);
                }
                return;
            }

            var app = new App();
            app.DispatcherUnhandledException += (s, e) =>
            {
                LogCrash(e.Exception.ToString());
                e.Handled = true;
                MessageBox.Show("Ошибка запуска:\n" + e.Exception.Message, "DieCloud Error", MessageBoxButton.OK, MessageBoxImage.Error);
            };
            app.InitializeComponent();
            app.Run();
        }
        catch (Exception ex)
        {
            LogCrash(ex.ToString());
            MessageBox.Show("Критическая ошибка запуска:\n" + ex.Message, "DieCloud Fatal Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static void LogCrash(string msg)
    {
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DieCloud");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "crash.log"), $"[{DateTime.UtcNow:u}] {msg}\n\n");
            File.AppendAllText("crash.log", $"[{DateTime.UtcNow:u}] {msg}\n\n");
        }
        catch { }
    }

    private const int SW_RESTORE = 9;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string? lpClassName, string? lpWindowName);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
