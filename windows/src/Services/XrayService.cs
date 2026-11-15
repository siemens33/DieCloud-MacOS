using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using DieCloud.Models;

namespace DieCloud.Services;

public sealed class XrayService : IDisposable
{
    public const int LocalHttpPort = 17890;
    private const string XrayDownloadUrl = "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-windows-64.zip";

    private Process? _process;
    private string _xrayPath = "";
    private readonly string _configPath;
    private readonly string _binDir;
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(60) };

    public bool IsRunning => _process is { HasExited: false };
    public string CurrentServerName { get; private set; } = "";

    public XrayService()
    {
        var dataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DieCloud");
        _binDir = Path.Combine(dataDir, "bin");
        Directory.CreateDirectory(_binDir);
        _configPath = Path.Combine(dataDir, "xray-config.json");

        LocateOrSetXrayPath();
    }

    private void LocateOrSetXrayPath()
    {
        var appDir = AppDomain.CurrentDomain.BaseDirectory;
        string[] candidates = [
            Path.Combine(appDir, "xray.exe"),
            Path.Combine(appDir, "resources", "xray-windows-64.exe"),
            Path.Combine(appDir, "resources", "xray.exe"),
            Path.Combine(_binDir, "xray.exe")
        ];

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                _xrayPath = candidate;
                return;
            }
        }
        _xrayPath = Path.Combine(_binDir, "xray.exe");
    }

    public async Task<bool> EnsureXrayAvailableAsync(Action<string>? statusCallback = null)
    {
        LocateOrSetXrayPath();
        if (File.Exists(_xrayPath)) return true;

        statusCallback?.Invoke("Загрузка Xray-core (11 МБ)...");
        try
        {
            var zipBytes = await HttpClient.GetByteArrayAsync(XrayDownloadUrl);
            using var ms = new MemoryStream(zipBytes);
            using var archive = new ZipArchive(ms, ZipArchiveMode.Read);

            var entry = archive.GetEntry("xray.exe");
            if (entry != null)
            {
                Directory.CreateDirectory(_binDir);
                var targetPath = Path.Combine(_binDir, "xray.exe");
                entry.ExtractToFile(targetPath, overwrite: true);
                _xrayPath = targetPath;
                statusCallback?.Invoke("Xray-core успешно установлен");
                return true;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to download Xray-core: {ex.Message}");
            statusCallback?.Invoke($"Ошибка загрузки Xray: {ex.Message}");
        }

        return File.Exists(_xrayPath);
    }

    /// <summary>
    /// Starts Xray with direct routing (pass-through) on port 17890 if no VPN is active.
    /// This allows WebView2 to always bind to 127.0.0.1:17890 seamlessly.
    /// </summary>
    public bool StartDirectMode()
    {
        Stop();
        if (!File.Exists(_xrayPath)) return false;

        try
        {
            var directConfig = new JsonObject
            {
                ["log"] = new JsonObject { ["loglevel"] = "warning" },
                ["inbounds"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["listen"] = "127.0.0.1",
                        ["port"] = LocalHttpPort,
                        ["protocol"] = "http",
                        ["settings"] = new JsonObject { ["timeout"] = 30 }
                    }
                },
                ["outbounds"] = new JsonArray
                {
                    new JsonObject { ["protocol"] = "freedom", ["tag"] = "direct" }
                }
            };

            File.WriteAllText(_configPath, directConfig.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return LaunchProcess();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error starting direct Xray: {ex.Message}");
            return false;
        }
    }

    public bool Start(VPNServer server)
    {
        Stop();
        LocateOrSetXrayPath();
        if (!File.Exists(_xrayPath)) return false;

        try
        {
            var configJson = GenerateConfig(server);
            if (string.IsNullOrEmpty(configJson)) return false;

            File.WriteAllText(_configPath, configJson);
            if (LaunchProcess())
            {
                CurrentServerName = server.Name;
                return true;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error starting Xray with server: {ex.Message}");
        }

        return false;
    }

    public bool StartRaw(string rawUriOrJson)
    {
        var servers = SubscriptionParser.Parse(rawUriOrJson);
        if (servers.Count > 0)
        {
            return Start(servers[0]);
        }
        return false;
    }

    private bool LaunchProcess()
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = _xrayPath,
                Arguments = $"run -c \"{_configPath}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            _process = Process.Start(startInfo);
            if (_process == null || _process.HasExited) return false;

            // Healthcheck: wait for local port up to 2 seconds
            return WaitForPort(LocalHttpPort, 2000);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"LaunchProcess error: {ex.Message}");
            return false;
        }
    }

    private static bool WaitForPort(int port, int timeoutMs)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs)
        {
            try
            {
                using var client = new TcpClient();
                var result = client.BeginConnect("127.0.0.1", port, null, null);
                if (result.AsyncWaitHandle.WaitOne(100))
                {
                    client.EndConnect(result);
                    return true;
                }
            }
            catch { }
            Thread.Sleep(50);
        }
        return false;
    }

    public void Stop()
    {
        try
        {
            if (_process is { HasExited: false })
            {
                _process.Kill(true);
                _process.WaitForExit(800);
            }
        }
        catch { }
        finally
        {
            _process?.Dispose();
            _process = null;
            CurrentServerName = "";
        }
    }

    public static async Task<int?> MeasurePingAsync(VPNServer server, int timeoutMs = 2000)
    {
        if (string.IsNullOrEmpty(server.Host) || server.Port <= 0) return null;

        var sw = Stopwatch.StartNew();
        try
        {
            using var client = new TcpClient();
            using var cts = new CancellationTokenSource(timeoutMs);
            await client.ConnectAsync(server.Host, server.Port, cts.Token);
            sw.Stop();
            var ms = (int)sw.ElapsedMilliseconds;
            server.PingMS = ms;
            return ms;
        }
        catch
        {
            server.PingMS = null;
            return null;
        }
    }

    private static string? GenerateConfig(VPNServer server)
    {
        try
        {
            var outbound = OutboundObject(server.RawURI);
            if (outbound == null) return null;

            var root = new JsonObject
            {
                ["log"] = new JsonObject { ["loglevel"] = "warning" },
                ["inbounds"] = new JsonArray
                {
                    new JsonObject
                    {
                        ["listen"] = "127.0.0.1",
                        ["port"] = LocalHttpPort,
                        ["protocol"] = "http",
                        ["settings"] = new JsonObject { ["timeout"] = 30 }
                    }
                },
                ["outbounds"] = new JsonArray
                {
                    outbound,
                    new JsonObject { ["protocol"] = "freedom", ["tag"] = "direct" }
                }
            };

            return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Failed to generate Xray config: {ex.Message}");
            return null;
        }
    }

    private static JsonObject? OutboundObject(string uri)
    {
        if (uri.StartsWith("vmess://", StringComparison.OrdinalIgnoreCase))
        {
            return VmessOutbound(uri);
        }

        if (!Uri.TryCreate(uri, UriKind.Absolute, out var c)) return null;
        var scheme = c.Scheme.ToLowerInvariant();
        var host = c.Host;
        var port = c.Port > 0 ? c.Port : (scheme == "socks" ? 1080 : 443);

        var query = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrEmpty(c.Query))
        {
            foreach (var part in c.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=', 2);
                query[Uri.UnescapeDataString(kv[0])] = kv.Length > 1 ? Uri.UnescapeDataString(kv[1]) : "";
            }
        }
        string GetParam(string key, string fallback = "") => query.TryGetValue(key, out var v) ? v : fallback;

        var network = GetParam("type", "tcp");
        var security = GetParam("security", GetParam("tls") == "tls" ? "tls" : "none");

        var stream = new JsonObject
        {
            ["network"] = network,
            ["security"] = security
        };

        if (security is "tls" or "reality")
        {
            var tls = new JsonObject
            {
                ["serverName"] = GetParam("sni", host)
            };
            if (security == "reality")
            {
                tls["publicKey"] = GetParam("pbk", "");
                tls["shortId"] = GetParam("sid", "");
                tls["fingerprint"] = GetParam("fp", "chrome");
                stream["realitySettings"] = tls;
            }
            else
            {
                stream["tlsSettings"] = tls;
            }
        }

        if (network == "ws")
        {
            stream["wsSettings"] = new JsonObject
            {
                ["path"] = GetParam("path", "/"),
                ["headers"] = new JsonObject { ["Host"] = GetParam("host", host) }
            };
        }

        if (scheme == "vless")
        {
            var user = c.UserInfo;
            return new JsonObject
            {
                ["protocol"] = "vless",
                ["tag"] = "proxy",
                ["settings"] = new JsonObject
                {
                    ["vnext"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["address"] = host,
                            ["port"] = port,
                            ["users"] = new JsonArray
                            {
                                new JsonObject
                                {
                                    ["id"] = user,
                                    ["encryption"] = GetParam("encryption", "none"),
                                    ["flow"] = GetParam("flow", "")
                                }
                            }
                        }
                    }
                },
                ["streamSettings"] = stream
            };
        }

        if (scheme == "trojan")
        {
            var password = c.UserInfo;
            return new JsonObject
            {
                ["protocol"] = "trojan",
                ["tag"] = "proxy",
                ["settings"] = new JsonObject
                {
                    ["servers"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["address"] = host,
                            ["port"] = port,
                            ["password"] = password
                        }
                    }
                },
                ["streamSettings"] = stream
            };
        }

        if (scheme is "socks" or "ss")
        {
            return new JsonObject
            {
                ["protocol"] = "socks",
                ["tag"] = "proxy",
                ["settings"] = new JsonObject
                {
                    ["servers"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["address"] = host,
                            ["port"] = port
                        }
                    }
                }
            };
        }

        return null;
    }

    private static JsonObject? VmessOutbound(string uri)
    {
        try
        {
            var encoded = uri["vmess://".Length..].Trim();
            var normalized = encoded.Replace("-", "+").Replace("_", "/");
            int pad = (4 - normalized.Length % 4) % 4;
            if (pad > 0) normalized += new string('=', pad);

            var jsonBytes = Convert.FromBase64String(normalized);
            using var doc = JsonDocument.Parse(jsonBytes);
            var j = doc.RootElement;

            var host = j.TryGetProperty("add", out var add) ? add.GetString() ?? "" : "";
            var id = j.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
            int port = 443;
            if (j.TryGetProperty("port", out var p))
            {
                if (p.ValueKind == JsonValueKind.Number) port = p.GetInt32();
                else if (p.ValueKind == JsonValueKind.String && int.TryParse(p.GetString(), out var parsedPort)) port = parsedPort;
            }

            var network = j.TryGetProperty("net", out var net) ? net.GetString() ?? "tcp" : "tcp";
            var tls = j.TryGetProperty("tls", out var tlsProp) ? tlsProp.GetString() ?? "" : "";

            var stream = new JsonObject
            {
                ["network"] = network,
                ["security"] = string.IsNullOrEmpty(tls) ? "none" : "tls"
            };
            if (!string.IsNullOrEmpty(tls))
            {
                stream["tlsSettings"] = new JsonObject
                {
                    ["serverName"] = j.TryGetProperty("sni", out var sni) ? sni.GetString() ?? host : host
                };
            }
            if (network == "ws")
            {
                stream["wsSettings"] = new JsonObject
                {
                    ["path"] = j.TryGetProperty("path", out var path) ? path.GetString() ?? "/" : "/",
                    ["headers"] = new JsonObject
                    {
                        ["Host"] = j.TryGetProperty("host", out var h) ? h.GetString() ?? host : host
                    }
                };
            }

            int alterId = 0;
            if (j.TryGetProperty("aid", out var aid))
            {
                if (aid.ValueKind == JsonValueKind.Number) alterId = aid.GetInt32();
                else if (aid.ValueKind == JsonValueKind.String && int.TryParse(aid.GetString(), out var parsedAid)) alterId = parsedAid;
            }

            return new JsonObject
            {
                ["protocol"] = "vmess",
                ["tag"] = "proxy",
                ["settings"] = new JsonObject
                {
                    ["vnext"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["address"] = host,
                            ["port"] = port,
                            ["users"] = new JsonArray
                            {
                                new JsonObject
                                {
                                    ["id"] = id,
                                    ["alterId"] = alterId,
                                    ["security"] = j.TryGetProperty("scy", out var scy) ? scy.GetString() ?? "auto" : "auto"
                                }
                            }
                        }
                    }
                },
                ["streamSettings"] = stream
            };
        }
        catch
        {
            return null;
        }
    }

    public void Dispose()
    {
        Stop();
    }
}
