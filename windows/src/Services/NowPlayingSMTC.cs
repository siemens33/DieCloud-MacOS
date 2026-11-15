using System;

namespace DieCloud.Services;

public sealed class NowPlayingSMTC : IDisposable
{
    public event Action? OnPlay;
    public event Action? OnPause;
    public event Action? OnNext;
    public event Action? OnPrevious;

    public NowPlayingSMTC(IntPtr windowHandle)
    {
        // Safe stub for maximum portability across Wine, older Windows, and Win11
    }

    public void UpdatePlaybackState(bool isPlaying)
    {
    }

    public void UpdateMetadata(string title, string artist, string artworkUrl)
    {
    }

    public void Dispose()
    {
    }
}
