using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace DieCloud;

public static class Program
{
    private const string MutexName = "Global\\DieCloud_Windows_SingleInstance_Mutex";

    [STAThread]
    public static void Main(string[] args)
    {
        using var mutex = new Mutex(true, MutexName, out bool isNewInstance);
        if (!isNewInstance)
        {
            // Activate existing instance
            var hWnd = FindWindow(null, "DieCloud");
            if (hWnd != IntPtr.Zero)
            {
                ShowWindow(hWnd, SW_RESTORE);
                SetForegroundWindow(hWnd);
            }
            return;
        }

        var app = new App();
        app.InitializeComponent();
        app.Run();
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
