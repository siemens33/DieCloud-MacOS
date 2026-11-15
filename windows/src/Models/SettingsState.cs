using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DieCloud.Models;

public sealed class SettingsState
{
    public const string DefaultDiscordClientID = "1305221998971486258";
    public static readonly int[] EqualizerFrequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

    public static readonly Dictionary<string, double[]> EqualizerPresets = new()
    {
        ["flat"] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        ["bassBoost"] = [6, 5, 4, 3, 1, 0, 0, 0, 1, 2],
        ["electronic"] = [4, 3, 2, 0, -1, 2, 4, 3, 4, 5],
        ["rock"] = [4, 2, 1, -1, -2, 1, 3, 4, 4, 3],
        ["vocal"] = [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        ["acoustic"] = [2, 2, 1, 2, 3, 2, 1, 2, 3, 3]
    };

    public bool ModernDesign { get; set; } = true;
    public bool Theme { get; set; } = true;
    public bool RoundedCards { get; set; } = true;
    public bool ArtworkHover { get; set; } = true;
    public bool Focus { get; set; } = false;
    public bool AdBlock { get; set; } = true;
    public bool DiscordRPC { get; set; } = false;
    public string DiscordClientID { get; set; } = DefaultDiscordClientID;
    public string Accent { get; set; } = "mono"; // mono, amber, blue, system
    public double Volume { get; set; } = 0.8;
    public bool IsMuted { get; set; } = false;
    public bool EqualizerEnabled { get; set; } = false;
    public bool EqualizerNormalization { get; set; } = false;
    public double[] EqualizerBands { get; set; } = new double[10];
    public bool WelcomeShown { get; set; } = false;

    // VPN Properties matching macOS
    public bool VPNEnabled { get; set; } = false;
    public string VPNConfig { get; set; } = "";
    public string VpnSubscriptionKey { get; set; } = "";
    public string SelectedVpnServerUri { get; set; } = "";
    public bool VpnAutoConnect { get; set; } = false;
    public List<VPNServer> VpnServers { get; set; } = new();

    [JsonIgnore]
    public string EffectiveDiscordClientID
    {
        get
        {
            var trimmed = (DiscordClientID ?? "").Trim();
            return string.IsNullOrEmpty(trimmed) ? DefaultDiscordClientID : trimmed;
        }
    }

    private static readonly string SettingsDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DieCloud");
    private static readonly string SettingsFilePath = Path.Combine(SettingsDirectory, "settings.json");

    public static SettingsState Load()
    {
        try
        {
            if (File.Exists(SettingsFilePath))
            {
                var json = File.ReadAllText(SettingsFilePath);
                var loaded = JsonSerializer.Deserialize<SettingsState>(json);
                if (loaded != null)
                {
                    if (loaded.EqualizerBands == null || loaded.EqualizerBands.Length != 10)
                        loaded.EqualizerBands = new double[10];
                    loaded.VpnServers ??= new();
                    return loaded;
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading settings: {ex.Message}");
        }

        var fresh = new SettingsState();
        fresh.Save();
        return fresh;
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(SettingsDirectory);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsFilePath, json);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error saving settings: {ex.Message}");
        }
    }

    public void ResetDesign()
    {
        ModernDesign = true;
        Theme = true;
        RoundedCards = true;
        ArtworkHover = true;
        Accent = "mono";
        Save();
    }

    public string ToBridgeJson()
    {
        var dict = new Dictionary<string, object>
        {
            ["modernDesign"] = ModernDesign,
            ["theme"] = Theme,
            ["roundedCards"] = RoundedCards,
            ["artworkHover"] = ArtworkHover,
            ["focus"] = Focus,
            ["adBlock"] = AdBlock,
            ["discordRPC"] = DiscordRPC,
            ["accent"] = Accent,
            ["volume"] = Math.Clamp(Volume, 0.0, 1.0),
            ["isMuted"] = IsMuted,
            ["equalizerEnabled"] = EqualizerEnabled,
            ["equalizerBands"] = EqualizerBands,
            ["equalizerNormalization"] = EqualizerNormalization
        };
        return JsonSerializer.Serialize(dict);
    }
}
