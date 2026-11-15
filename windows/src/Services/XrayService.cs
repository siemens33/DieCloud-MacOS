using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DieCloud.Services;

public sealed class XrayService : IDisposable
{
    public const int SocksPort = 10808;
    public const int HttpPort = 10809;

    private Process? _process;
    private readonly string _xrayPath;
    private readonly string _configPath;

    public bool IsRunning => _process is { HasExited: false };

    public XrayService()
    {
        var appDir = AppDomain.CurrentDomain.BaseDirectory;
        _xrayPath = Path.Combine(appDir, "resources", "xray-windows-64.exe");
        if (!File.Exists(_xrayPath))
        {
            _xrayPath = Path.Combine(appDir, "xray.exe");
        }

        var dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DieCloud");
        Directory.CreateDirectory(dataDir);
        _configPath = Path.Combine(dataDir, "xray-config.json");
    }

    public bool Start(string proxyUri)
    {
        Stop();

        if (string.IsNullOrWhiteSpace(proxyUri)) return false;
        if (!File.Exists(_xrayPath))
        {
            Debug.WriteLine($"Xray executable not found at {_xrayPath}");
            return false;
        }

        try
        {
            var configJson = GenerateConfig(proxyUri.Trim());
            if (string.IsNullOrEmpty(configJson)) return false;

            File.WriteAllText(_configPath, configJson);

            var startInfo = new ProcessStartInfo
            {
                FileName = _xrayPath,
                Arguments = $"run -c \"{_configPath}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            _process = Process.Start(startInfo);
            return _process != null && !_process.HasExited;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error starting Xray: {ex.Message}");
            return false;
        }
    }

    public void Stop()
    {
        try
        {
            if (_process is { HasExited: false })
            {
                _process.Kill(true);
                _process.WaitForExit(1000);
            }
        }
        catch { }
        finally
        {
            _process?.Dispose();
            _process = null;
        }
    }

    private static string? GenerateConfig(string rawUri)
    {
        try
        {
            if (rawUri.StartsWith("{") && rawUri.EndsWith("}"))
            {
                return rawUri; // Raw JSON config
            }

            // Generate standard Xray client configuration
            var root = new JsonObject
            {
                ["log"] = new JsonObject { ["loglevel"] = "none" },
                ["inbounds"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["port"] = SocksPort,
                        ["listen"] = "127.0.0.1",
                        ["protocol"] = "socks",
                        ["settings"] = new JsonObject { ["udp"] = true }
                    },
                    new JsonObject
                    {
                        ["port"] = HttpPort,
                        ["listen"] = "127.0.0.1",
                        ["protocol"] = "http"
                    }
                }
            };

            var outbounds = new JsonArray();
            var uri = new Uri(rawUri);

            if (rawUri.StartsWith("vless://", StringComparison.OrdinalIgnoreCase))
            {
                var user = uri.UserInfo;
                var host = uri.Host;
                var port = uri.Port;
                var query = System.Web.HttpUtility.ParseQueryString(uri.Query);

                var vnext = new JsonObject
                {
                    ["address"] = host,
                    ["port"] = port,
                    ["users"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["id"] = user,
                            ["encryption"] = query["encryption"] ?? "none",
                            ["flow"] = query["flow"] ?? ""
                        }
                    }
                };

                var streamSettings = new JsonObject
                {
                    ["network"] = query["type"] ?? "tcp",
                    ["security"] = query["security"] ?? "none"
                };

                if (query["security"] == "reality")
                {
                    streamSettings["realitySettings"] = new JsonObject
                    {
                        ["publicKey"] = query["pbk"] ?? "",
                        ["serverName"] = query["sni"] ?? "",
                        ["fingerprint"] = query["fp"] ?? "chrome",
                        ["shortId"] = query["sid"] ?? "",
                        ["spiderX"] = query["spx"] ?? ""
                    };
                }

                outbounds.Add(new JsonObject
                {
                    ["protocol"] = "vless",
                    ["settings"] = new JsonObject { ["vnext"] = new JsonArray { vnext } },
                    ["streamSettings"] = streamSettings
                });
            }
            else
            {
                // Fallback direct outbound
                outbounds.Add(new JsonObject { ["protocol"] = "freedom" });
            }

            outbounds.Add(new JsonObject { ["protocol"] = "freedom", ["tag"] = "direct" });
            root["outbounds"] = outbounds;

            return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to generate Xray config: {ex.Message}");
            return null;
        }
    }

    public void Dispose()
    {
        Stop();
    }
}
