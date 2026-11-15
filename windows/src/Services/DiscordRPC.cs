using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using DieCloud.Models;

namespace DieCloud.Services;

public sealed class DiscordRPC : IDisposable
{
    public sealed class Playback
    {
        public string Title { get; set; } = "";
        public string Artist { get; set; } = "";
        public string Artwork { get; set; } = "";
        public string TrackURL { get; set; } = "";
        public bool Playing { get; set; }
        public double Position { get; set; }
        public double Duration { get; set; }
    }

    private string _clientId;
    private bool _enabled;
    private bool _ready;
    private NamedPipeClientStream? _pipe;
    private CancellationTokenSource? _cts;
    private Playback _playback = new();
    private string _lastActivity = "";
    private DateTime _lastSentAt = DateTime.MinValue;
    private readonly object _lock = new();

    public DiscordRPC(string clientId = SettingsState.DefaultDiscordClientID)
    {
        _clientId = string.IsNullOrWhiteSpace(clientId) ? SettingsState.DefaultDiscordClientID : clientId.Trim();
    }

    public void SetClientID(string value)
    {
        var trimmed = (value ?? "").Trim();
        var digits = new string(Array.FindAll(trimmed.ToCharArray(), char.IsDigit));
        var newId = string.IsNullOrEmpty(digits) ? SettingsState.DefaultDiscordClientID : digits;

        lock (_lock)
        {
            if (_clientId == newId) return;
            _clientId = newId;

            if (_enabled)
            {
                Disconnect();
                StartConnectionLoop();
            }
        }
    }

    public void SetEnabled(bool value)
    {
        lock (_lock)
        {
            if (_enabled == value) return;
            _enabled = value;

            if (_enabled)
            {
                StartConnectionLoop();
            }
            else
            {
                if (_ready) SendActivity(null);
                Disconnect();
            }
        }
    }

    public void Update(Playback playback)
    {
        lock (_lock)
        {
            _playback = playback;
            Publish();
        }
    }

    private void StartConnectionLoop()
    {
        Disconnect();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        Task.Run(async () =>
        {
            while (!token.IsCancellationRequested && _enabled)
            {
                for (int i = 0; i < 10; i++)
                {
                    if (token.IsCancellationRequested || !_enabled) break;
                    try
                    {
                        var pipe = new NamedPipeClientStream(".", $"discord-ipc-{i}", PipeDirection.InOut, PipeOptions.Asynchronous);
                        using var timeoutCts = new CancellationTokenSource(TimeSpan.FromMilliseconds(500));
                        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(token, timeoutCts.Token);

                        await pipe.ConnectAsync(linkedCts.Token);
                        _pipe = pipe;

                        // Handshake
                        var handshake = new JsonObject
                        {
                            ["v"] = 1,
                            ["client_id"] = _clientId
                        };
                        await SendFrameAsync(0, handshake.ToJsonString(), token);

                        // Frame reading loop
                        await ReceiveLoopAsync(pipe, token);
                    }
                    catch
                    {
                        // Try next pipe index
                    }
                }

                if (token.IsCancellationRequested || !_enabled) break;
                await Task.Delay(5000, token).ConfigureAwait(false);
            }
        }, token);
    }

    private async Task ReceiveLoopAsync(NamedPipeClientStream pipe, CancellationToken token)
    {
        var header = new byte[8];
        while (!token.IsCancellationRequested && pipe.IsConnected)
        {
            int read = await pipe.ReadAsync(header, 0, 8, token);
            if (read < 8) break;

            int opcode = BitConverter.ToInt32(header, 0);
            int length = BitConverter.ToInt32(header, 4);
            if (length is < 0 or > 1_048_576) break;

            var payload = new byte[length];
            int totalRead = 0;
            while (totalRead < length)
            {
                int r = await pipe.ReadAsync(payload, totalRead, length - totalRead, token);
                if (r <= 0) break;
                totalRead += r;
            }
            if (totalRead < length) break;

            if (opcode == 1) // Frame
            {
                var json = Encoding.UTF8.GetString(payload);
                using var doc = JsonDocument.Parse(json);
                if (doc.RootElement.TryGetProperty("evt", out var evt) && evt.GetString() == "READY")
                {
                    lock (_lock)
                    {
                        _ready = true;
                        _lastActivity = "";
                        Publish();
                    }
                }
            }
            else if (opcode == 2) // Close
            {
                break;
            }
            else if (opcode == 3) // Ping
            {
                await SendFrameAsync(4, Encoding.UTF8.GetString(payload), token);
            }
        }
    }

    private void Publish()
    {
        if (!_ready || !_enabled) return;

        if (!_playback.Playing || string.IsNullOrWhiteSpace(_playback.Title))
        {
            if (_lastActivity != "clear")
            {
                SendActivity(null);
                _lastActivity = "clear";
            }
            return;
        }

        var activity = new JsonObject
        {
            ["details"] = Truncate(_playback.Title, 128),
            ["state"] = Truncate(string.IsNullOrEmpty(_playback.Artist) ? "SoundCloud" : _playback.Artist, 128)
        };

        if (IsValidSoundCloudUrl(_playback.TrackURL))
        {
            activity["buttons"] = new JsonArray
            {
                new JsonObject
                {
                    ["label"] = "Open on SoundCloud",
                    ["url"] = _playback.TrackURL
                }
            };
        }

        if (!string.IsNullOrEmpty(_playback.Artwork) && _playback.Artwork.StartsWith("https://"))
        {
            activity["assets"] = new JsonObject
            {
                ["large_image"] = _playback.Artwork
            };
        }

        double pos = double.IsFinite(_playback.Position) ? Math.Max(0, _playback.Position) : 0;
        double dur = double.IsFinite(_playback.Duration) ? Math.Max(0, _playback.Duration) : 0;

        string key = $"{_playback.Title}\n{_playback.Artist}\n{_playback.Artwork}\n{_playback.TrackURL}\n{dur}";
        if (key == _lastActivity && (DateTime.UtcNow - _lastSentAt).TotalSeconds < 15) return;

        if (dur > pos && dur < 604800)
        {
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            activity["timestamps"] = new JsonObject
            {
                ["start"] = (long)(now - pos),
                ["end"] = (long)(now + dur - pos)
            };
        }

        SendActivity(activity);
        _lastActivity = key;
        _lastSentAt = DateTime.UtcNow;
    }

    private void SendActivity(JsonObject? activity)
    {
        var frame = new JsonObject
        {
            ["cmd"] = "SET_ACTIVITY",
            ["args"] = new JsonObject
            {
                ["pid"] = Environment.ProcessId,
                ["activity"] = activity ?? (JsonNode?)null
            },
            ["nonce"] = Guid.NewGuid().ToString()
        };

        _ = SendFrameAsync(1, frame.ToJsonString(), CancellationToken.None);
    }

    private async Task SendFrameAsync(int opcode, string json, CancellationToken token)
    {
        var pipe = _pipe;
        if (pipe == null || !pipe.IsConnected) return;

        try
        {
            byte[] data = Encoding.UTF8.GetBytes(json);
            byte[] header = new byte[8];
            BitConverter.GetBytes(opcode).CopyTo(header, 0);
            BitConverter.GetBytes(data.Length).CopyTo(header, 4);

            await pipe.WriteAsync(header, 0, 8, token);
            await pipe.WriteAsync(data, 0, data.Length, token);
            await pipe.FlushAsync(token);
        }
        catch
        {
            // Socket disconnected
        }
    }

    private static bool IsValidSoundCloudUrl(string url)
    {
        if (string.IsNullOrEmpty(url) || url.Length > 512) return false;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        return (uri.Scheme == "https" || uri.Scheme == "http") &&
               (uri.Host == "soundcloud.com" || uri.Host.EndsWith(".soundcloud.com"));
    }

    private static string Truncate(string value, int maxLen) =>
        value.Length <= maxLen ? value : value[..maxLen];

    private void Disconnect()
    {
        _ready = false;
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;

        try { _pipe?.Dispose(); } catch { }
        _pipe = null;
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}
