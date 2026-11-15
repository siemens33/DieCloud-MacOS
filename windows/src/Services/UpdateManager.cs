using System;
using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;

namespace DieCloud.Services;

public sealed class UpdateManager
{
    private const string CurrentVersion = "5.0.0";
    private const string ReleasesApiUrl = "https://api.github.com/repos/siemens33/DieCloud-MacOS/releases?per_page=10";
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(10) };

    static UpdateManager()
    {
        HttpClient.DefaultRequestHeaders.Add("User-Agent", "DieCloud-Windows/" + CurrentVersion);
        HttpClient.DefaultRequestHeaders.Add("Accept", "application/vnd.github+json");
    }

    public async Task CheckForUpdatesAsync(Window owner, bool silentWhenCurrent)
    {
        try
        {
            var json = await HttpClient.GetStringAsync(ReleasesApiUrl);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.ValueKind != JsonValueKind.Array)
            {
                if (!silentWhenCurrent) ShowMessage(owner, "Обновлений нет", "GitHub вернул пустой список релизов.");
                return;
            }

            foreach (var release in root.EnumerateArray())
            {
                bool isDraft = release.TryGetProperty("draft", out var d) && d.GetBoolean();
                bool isPrerelease = release.TryGetProperty("prerelease", out var pr) && pr.GetBoolean();
                if (isDraft || isPrerelease) continue;

                var tagName = release.TryGetProperty("tag_name", out var tag) ? tag.GetString() ?? "" : "";
                var cleanTag = tagName.TrimStart('v', 'V').Trim();
                if (string.IsNullOrEmpty(cleanTag)) continue;

                if (IsNewer(cleanTag, CurrentVersion))
                {
                    var body = release.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";
                    var htmlUrl = release.TryGetProperty("html_url", out var u) ? u.GetString() ?? "https://github.com/siemens33/DieCloud-MacOS/releases" : "";

                    var msg = $"Доступна новая версия DieCloud v{cleanTag}!\n\n" +
                              $"Текущая версия: v{CurrentVersion}\n\n" +
                              (string.IsNullOrWhiteSpace(body) ? "" : "Что нового:\n" + Truncate(body, 600) + "\n\n") +
                              "Открыть страницу загрузки обновления?";

                    var result = MessageBox.Show(owner, msg, "Обновление DieCloud", MessageBoxButton.YesNo, MessageBoxImage.Information);
                    if (result == MessageBoxResult.Yes)
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = htmlUrl,
                            UseShellExecute = true
                        });
                    }
                    return;
                }
                else
                {
                    // Found latest stable release and it's not newer
                    break;
                }
            }

            if (!silentWhenCurrent)
            {
                MessageBox.Show(owner, $"У вас установлена самая актуальная версия DieCloud (v{CurrentVersion}).",
                                "DieCloud", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            if (!silentWhenCurrent)
            {
                MessageBox.Show(owner, $"Не удалось проверить наличие обновлений: {ex.Message}",
                                "Обновление DieCloud", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
    }

    private static bool IsNewer(string remote, string current)
    {
        try
        {
            var rParts = remote.Split('.');
            var cParts = current.Split('.');
            int maxLen = Math.Max(rParts.Length, cParts.Length);

            for (int i = 0; i < maxLen; i++)
            {
                int rVal = i < rParts.Length && int.TryParse(rParts[i], out var r) ? r : 0;
                int cVal = i < cParts.Length && int.TryParse(cParts[i], out var c) ? c : 0;

                if (rVal > cVal) return true;
                if (rVal < cVal) return false;
            }
        }
        catch { }
        return false;
    }

    private static void ShowMessage(Window owner, string title, string message)
    {
        MessageBox.Show(owner, message, title, MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private static string Truncate(string text, int maxLen) =>
        text.Length <= maxLen ? text : text[..maxLen] + "…";
}
