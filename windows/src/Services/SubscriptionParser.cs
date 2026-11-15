using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using DieCloud.Models;

namespace DieCloud.Services;

public static class SubscriptionParser
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(15) };

    public static async Task<string> FetchTextAsync(string urlOrKey)
    {
        var trimmed = urlOrKey.Trim();
        if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var bytes = await HttpClient.GetByteArrayAsync(trimmed);
                return DecodeText(bytes);
            }
            catch (Exception ex)
            {
                throw new Exception($"Не удалось загрузить подписку: {ex.Message}");
            }
        }
        return trimmed;
    }

    public static string DecodeText(byte[] data)
    {
        var text = Encoding.UTF8.GetString(data).Trim();
        if (text.Contains("://")) return text;

        try
        {
            var normalized = text.Replace("-", "+").Replace("_", "/");
            int pad = (4 - normalized.Length % 4) % 4;
            if (pad > 0) normalized += new string('=', pad);

            var decodedBytes = Convert.FromBase64String(normalized);
            var decodedStr = Encoding.UTF8.GetString(decodedBytes);
            if (decodedStr.Contains("://")) return decodedStr;
        }
        catch { }

        return text;
    }

    public static List<VPNServer> Parse(string text)
    {
        var servers = new List<VPNServer>();
        var lines = text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line) || line.StartsWith("#")) continue;

            var server = ParseLine(line);
            if (server != null)
            {
                servers.Add(server);
            }
        }
        return servers;
    }

    private static VPNServer? ParseLine(string line)
    {
        if (line.StartsWith("vmess://", StringComparison.OrdinalIgnoreCase))
        {
            return ParseVMess(line);
        }

        try
        {
            if (!Uri.TryCreate(line, UriKind.Absolute, out var uri)) return null;
            var scheme = uri.Scheme.ToLowerInvariant();
            if (scheme != "vless" && scheme != "trojan" && scheme != "socks" && scheme != "ss") return null;

            var host = uri.Host;
            var port = uri.Port > 0 ? uri.Port : (scheme == "socks" ? 1080 : 443);
            if (string.IsNullOrEmpty(host)) return null;

            string name = $"{host}:{port}";
            if (!string.IsNullOrEmpty(uri.Fragment))
            {
                var unescaped = Uri.UnescapeDataString(uri.Fragment.TrimStart('#'));
                if (!string.IsNullOrWhiteSpace(unescaped)) name = unescaped;
            }

            return new VPNServer
            {
                Name = name,
                Scheme = scheme == "ss" ? "socks" : scheme,
                Host = host,
                Port = port,
                RawURI = line
            };
        }
        catch
        {
            return null;
        }
    }

    private static VPNServer? ParseVMess(string line)
    {
        try
        {
            var encoded = line["vmess://".Length..].Trim();
            var normalized = encoded.Replace("-", "+").Replace("_", "/");
            int pad = (4 - normalized.Length % 4) % 4;
            if (pad > 0) normalized += new string('=', pad);

            var jsonBytes = Convert.FromBase64String(normalized);
            var json = Encoding.UTF8.GetString(jsonBytes);

            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var host = root.TryGetProperty("add", out var addProp) ? addProp.GetString() ?? "" : "";
            if (string.IsNullOrEmpty(host)) return null;

            int port = 443;
            if (root.TryGetProperty("port", out var portProp))
            {
                if (portProp.ValueKind == JsonValueKind.Number) port = portProp.GetInt32();
                else if (portProp.ValueKind == JsonValueKind.String && int.TryParse(portProp.GetString(), out var p)) port = p;
            }

            var name = root.TryGetProperty("ps", out var psProp) ? psProp.GetString() : null;
            if (string.IsNullOrWhiteSpace(name)) name = $"{host}:{port}";

            return new VPNServer
            {
                Name = name,
                Scheme = "vmess",
                Host = host,
                Port = port,
                RawURI = line
            };
        }
        catch
        {
            return null;
        }
    }
}
