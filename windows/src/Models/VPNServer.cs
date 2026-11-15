using System;

namespace DieCloud.Models;

public sealed class VPNServer
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
    public string Scheme { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; } = 443;
    public string RawURI { get; set; } = "";
    public int? PingMS { get; set; }

    public string PingDisplay => PingMS.HasValue ? $"{PingMS.Value} ms" : "—";
    public string ProtocolDisplay => Scheme.ToUpperInvariant();
}
