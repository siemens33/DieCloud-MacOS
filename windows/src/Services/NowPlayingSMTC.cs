using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using Windows.Media;
using Windows.Storage.Streams;

namespace DieCloud.Services;

public sealed class NowPlayingSMTC
{
    private readonly SystemMediaTransportControls? _smtc;

    public event Action? OnPlay;
    public event Action? OnPause;
    public event Action? OnNext;
    public event Action? OnPrevious;

    public NowPlayingSMTC(IntPtr windowHandle)
    {
        try
        {
            var interopGuid = typeof(ISystemMediaTransportControlsInterop).GUID;
            var interop = (ISystemMediaTransportControlsInterop)WindowsRuntimeHelper.GetActivationFactory("Windows.Media.SystemMediaTransportControls", interopGuid);
            var guid = typeof(SystemMediaTransportControls).GUID;
            interop.GetForWindow(windowHandle, ref guid, out var rawSmtc);
            _smtc = (SystemMediaTransportControls)rawSmtc;

            if (_smtc != null)
            {
                _smtc.IsPlayEnabled = true;
                _smtc.IsPauseEnabled = true;
                _smtc.IsNextEnabled = true;
                _smtc.IsPreviousEnabled = true;
                _smtc.IsEnabled = true;

                _smtc.ButtonPressed += Smtc_ButtonPressed;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SMTC initialization warning: {ex.Message}");
        }
    }

    private void Smtc_ButtonPressed(SystemMediaTransportControls sender, SystemMediaTransportControlsButtonPressedEventArgs args)
    {
        switch (args.Button)
        {
            case SystemMediaTransportControlsButton.Play:
                OnPlay?.Invoke();
                break;
            case SystemMediaTransportControlsButton.Pause:
                OnPause?.Invoke();
                break;
            case SystemMediaTransportControlsButton.Next:
                OnNext?.Invoke();
                break;
            case SystemMediaTransportControlsButton.Previous:
                OnPrevious?.Invoke();
                break;
        }
    }

    public void UpdatePlaybackState(bool isPlaying)
    {
        if (_smtc != null)
        {
            _smtc.PlaybackStatus = isPlaying ? MediaPlaybackStatus.Playing : MediaPlaybackStatus.Paused;
        }
    }

    public void UpdateMetadata(string title, string artist, string artworkUrl)
    {
        if (_smtc == null) return;

        var updater = _smtc.DisplayUpdater;
        updater.Type = MediaPlaybackType.Music;
        updater.MusicProperties.Title = string.IsNullOrWhiteSpace(title) ? "SoundCloud" : title;
        updater.MusicProperties.Artist = artist ?? "";

        if (!string.IsNullOrEmpty(artworkUrl) && Uri.TryCreate(artworkUrl, UriKind.Absolute, out var uri))
        {
            try
            {
                updater.Thumbnail = RandomAccessStreamReference.CreateFromUri(uri);
            }
            catch
            {
                updater.Thumbnail = null;
            }
        }
        else
        {
            updater.Thumbnail = null;
        }

        updater.Update();
    }

    [System.Runtime.InteropServices.ComImport]
    [System.Runtime.InteropServices.Guid("43BF72E3-82C4-47B9-9055-B0F014B864A4")]
    [System.Runtime.InteropServices.InterfaceType(System.Runtime.InteropServices.ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISystemMediaTransportControlsInterop
    {
        void GetForWindow(IntPtr appWindow, [System.Runtime.InteropServices.In] ref Guid riid, [System.Runtime.InteropServices.Out] out object ppv);
    }
}

internal static class WindowsRuntimeHelper
{
    [System.Runtime.InteropServices.DllImport("api-ms-win-core-winrt-l1-1-0.dll", CallingConvention = System.Runtime.InteropServices.CallingConvention.StdCall)]
    private static extern int RoGetActivationFactory(IntPtr activatableClassId, [System.Runtime.InteropServices.In] ref Guid iid, out IntPtr factory);

    [System.Runtime.InteropServices.DllImport("api-ms-win-core-winrt-string-l1-1-0.dll", CallingConvention = System.Runtime.InteropServices.CallingConvention.StdCall)]
    private static extern int WindowsCreateString([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string sourceString, int length, out IntPtr hstring);

    [System.Runtime.InteropServices.DllImport("api-ms-win-core-winrt-string-l1-1-0.dll", CallingConvention = System.Runtime.InteropServices.CallingConvention.StdCall)]
    private static extern int WindowsDeleteString(IntPtr hstring);

    public static object GetActivationFactory(string typeName, Guid iid)
    {
        WindowsCreateString(typeName, typeName.Length, out var hstr);
        try
        {
            int hr = RoGetActivationFactory(hstr, ref iid, out var factoryPtr);
            if (hr != 0) throw new InvalidOperationException($"RoGetActivationFactory failed with HR {hr:X8}");
            return System.Runtime.InteropServices.Marshal.GetObjectForIUnknown(factoryPtr);
        }
        finally
        {
            if (hstr != IntPtr.Zero) WindowsDeleteString(hstr);
        }
    }
}
