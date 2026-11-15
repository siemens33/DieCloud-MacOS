using System;
using System.IO;
using System.Text.Json;
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
        var script = LoadThemeEngineScript();
        script = script.Replace("__SETTINGS__", _settings.ToBridgeJson());
        await _coreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);

        // Synchronize settings upon navigation completed
        _coreWebView2.NavigationCompleted += async (_, e) =>
        {
            if (e.IsSuccess)
            {
                await PushAllSettingsAsync();
            }
        };

        // Setup AdBlock filter
        SetupAdBlock();

        // Listen for WebMessages from theme-engine.js
        _coreWebView2.WebMessageReceived += CoreWebView2_WebMessageReceived;

        // Navigate to SoundCloud AFTER environment is fully initialized
        webViewControl.Source = new Uri("https://soundcloud.com");
    }

    private static string LoadThemeEngineScript()
    {
        // 1. Try local file in resources/
        var localPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "resources", "theme-engine.js");
        if (File.Exists(localPath))
        {
            try { return File.ReadAllText(localPath); } catch { }
        }

        // 2. Try embedded resource
        var asm = typeof(WebViewBridge).Assembly;
        foreach (var resName in asm.GetManifestResourceNames())
        {
            if (resName.EndsWith("theme-engine.js", StringComparison.OrdinalIgnoreCase))
            {
                using var stream = asm.GetManifestResourceStream(resName);
                if (stream != null)
                {
                    using var reader = new StreamReader(stream);
                    return reader.ReadToEnd();
                }
            }
        }

        return "console.warn('DieCloud: theme-engine.js not found');";
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
        var lower = url.ToLowerInvariant();
        return lower.Contains("doubleclick.net") ||
               lower.Contains("google-analytics.com") ||
               lower.Contains("googlesyndication.com") ||
               lower.Contains("googleadservices.com") ||
               lower.Contains("scorecardresearch.com") ||
               lower.Contains("amazon-adsystem.com") ||
               lower.Contains("moatads.com") ||
               lower.Contains("adnxs.com") ||
               lower.Contains("/ad/") ||
               lower.Contains("audio-ads");
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

            var container = root.TryGetProperty("payload", out var p) ? p : root;

            if (type == "meta")
            {
                var title = container.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                var artist = container.TryGetProperty("artist", out var a) ? a.GetString() ?? "" : "";
                var artwork = container.TryGetProperty("artwork", out var art) ? art.GetString() ?? "" : "";
                var trackURL = container.TryGetProperty("trackURL", out var u) ? u.GetString() ?? "" : "";

                OnMetaReceived?.Invoke(title, artist, artwork, trackURL);
            }
            else if (type == "state")
            {
                bool playing = container.TryGetProperty("playing", out var pVal) && pVal.GetBoolean();
                double pos = container.TryGetProperty("position", out var posVal) ? posVal.GetDouble() : 0;
                double dur = container.TryGetProperty("duration", out var durVal) ? durVal.GetDouble() : 0;

                OnPlaybackStateReceived?.Invoke(playing, pos, dur);
            }
            else if (type == "volume")
            {
                double vol = container.TryGetProperty("volume", out var v) ? v.GetDouble() : 0.8;
                bool muted = container.TryGetProperty("muted", out var m) && m.GetBoolean();

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
        await _coreWebView2.ExecuteScriptAsync($"window.__diecloude?.setAll?.({json});");
    }

    public async Task ExecuteScriptAsync(string script)
    {
        if (_coreWebView2 == null) return;
        await _coreWebView2.ExecuteScriptAsync(script);
    }
}
