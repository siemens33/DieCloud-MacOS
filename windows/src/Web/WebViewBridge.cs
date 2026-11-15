using System;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using DieCloud.Models;

namespace DieCloud.Web;

public sealed class WebViewBridge
{
    private CoreWebView2? _coreWebView2;
    private readonly SettingsState _settings;

    public event Action<string, string, string, string>? OnMetaReceived;
    public event Action<bool, double, double>? OnPlaybackStateReceived;
    public event Action<double, bool>? OnVolumeReceived;
    public event Action? OnEscapeReceived;

    public WebViewBridge(SettingsState settings)
    {
        _settings = settings;
    }

    public async Task InitializeAsync(Microsoft.Web.WebView2.Wpf.WebView2 webViewControl, bool useProxy)
    {
        var userDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DieCloud", "WebView2Data");
        Directory.CreateDirectory(userDataFolder);

        var options = new CoreWebView2EnvironmentOptions();
        var extraArgs = "--no-sandbox --disable-features=Translate,RendererAppContainer";
        if (useProxy)
        {
            extraArgs += " --proxy-server=socks5://127.0.0.1:10808";
        }
        options.AdditionalBrowserArguments = extraArgs;

        var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder, options);
        await webViewControl.EnsureCoreWebView2Async(env);

        _coreWebView2 = webViewControl.CoreWebView2;

        // Configure settings
        _coreWebView2.Settings.IsStatusBarEnabled = false;
        _coreWebView2.Settings.AreDevToolsEnabled = true;
        _coreWebView2.Settings.IsSwipeNavigationEnabled = true;

        // Inject theme-engine.js on every document creation
        var scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "resources", "theme-engine.js");
        if (File.Exists(scriptPath))
        {
            var script = await File.ReadAllTextAsync(scriptPath);
            await _coreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);
        }

        // Setup AdBlock filter
        SetupAdBlock();

        // Listen for WebMessages from theme-engine.js
        _coreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;
    }

    private void SetupAdBlock()
    {
        if (_coreWebView2 == null) return;

        // Add filter to block typical audio / banner ad requests
        _coreWebView2.AddWebResourceRequestedFilter("*ad*", CoreWebView2WebResourceContext.All);
        _coreWebView2.AddWebResourceRequestedFilter("*doubleclick.net*", CoreWebView2WebResourceContext.All);
        _coreWebView2.AddWebResourceRequestedFilter("*google-analytics.com*", CoreWebView2WebResourceContext.All);
        _coreWebView2.AddWebResourceRequestedFilter("*scorecardresearch.com*", CoreWebView2WebResourceContext.All);

        _coreWebView2.WebResourceRequested += (sender, args) =>
        {
            if (!_settings.AdBlock) return;

            var uri = args.Request.Uri;
            if (IsAdUrl(uri))
            {
                args.Response = _coreWebView2.Environment.CreateWebResourceResponse(
                    Stream.Null, 204, "No Content", "Content-Type: text/plain");
            }
        };
    }

    private static bool IsAdUrl(string url)
    {
        return url.Contains("doubleclick.net") ||
               url.Contains("google-analytics.com") ||
               url.Contains("scorecardresearch.com") ||
               url.Contains("adnxs.com") ||
               url.Contains("/ad/") ||
               url.Contains("audio-ads");
    }

    private void CoreWebView2_WebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            var json = e.WebMessageAsJson;
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (!root.TryGetProperty("type", out var typeProp)) return;
            var type = typeProp.GetString();

            if (type == "meta" && root.TryGetProperty("payload", out var payload))
            {
                var title = payload.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                var artist = payload.TryGetProperty("artist", out var a) ? a.GetString() ?? "" : "";
                var artwork = payload.TryGetProperty("artwork", out var art) ? art.GetString() ?? "" : "";
                var trackURL = payload.TryGetProperty("trackURL", out var u) ? u.GetString() ?? "" : "";

                OnMetaReceived?.Invoke(title, artist, artwork, trackURL);
            }
            else if (type == "state" && root.TryGetProperty("payload", out var statePayload))
            {
                bool playing = statePayload.TryGetProperty("playing", out var p) && p.GetBoolean();
                double pos = statePayload.TryGetProperty("position", out var posVal) ? posVal.GetDouble() : 0;
                double dur = statePayload.TryGetProperty("duration", out var durVal) ? durVal.GetDouble() : 0;

                OnPlaybackStateReceived?.Invoke(playing, pos, dur);
            }
            else if (type == "volume" && root.TryGetProperty("payload", out var volPayload))
            {
                double vol = volPayload.TryGetProperty("volume", out var v) ? v.GetDouble() : 0.8;
                bool muted = volPayload.TryGetProperty("muted", out var m) && m.GetBoolean();

                OnVolumeReceived?.Invoke(vol, muted);
            }
            else if (type == "escape")
            {
                OnEscapeReceived?.Invoke();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error processing WebMessage: {ex.Message}");
        }
    }

    public async Task PushAllSettingsAsync()
    {
        if (_coreWebView2 == null) return;
        var json = _settings.ToBridgeJson();
        await _coreWebView2.ExecuteScriptAsync($"window.__diecloude?.setAll({json});");
    }

    public async Task ExecuteScriptAsync(string script)
    {
        if (_coreWebView2 == null) return;
        await _coreWebView2.ExecuteScriptAsync(script);
    }
}
