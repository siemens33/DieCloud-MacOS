using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using DieCloud.Models;
using DieCloud.Services;

namespace DieCloud;

public partial class VpnWindow : Window
{
    private readonly SettingsState _settings;
    private readonly XrayService _xrayService;
    public event Action<bool, string>? OnProxyStateChanged;

    public VpnWindow(SettingsState settings, XrayService xrayService)
    {
        _settings = settings;
        _xrayService = xrayService;

        InitializeComponent();
        Loaded += VpnWindow_Loaded;
    }

    private void VpnWindow_Loaded(object sender, RoutedEventArgs e)
    {
        TxtSubscription.Text = _settings.VpnSubscriptionKey;
        ChkAutoConnect.IsChecked = _settings.VpnAutoConnect;

        RefreshServerList();

        // Select previously chosen server
        if (!string.IsNullOrEmpty(_settings.SelectedVpnServerUri))
        {
            var selected = _settings.VpnServers.FirstOrDefault(s => s.RawURI == _settings.SelectedVpnServerUri);
            if (selected != null) LstServers.SelectedItem = selected;
        }

        UpdateUiState();
    }

    private void RefreshServerList()
    {
        LstServers.ItemsSource = null;
        LstServers.ItemsSource = _settings.VpnServers;
    }

    private void UpdateUiState()
    {
        bool running = _xrayService.IsRunning && _settings.VPNEnabled;
        if (running)
        {
            StatusDot.Foreground = new SolidColorBrush(Color.FromRgb(40, 167, 69)); // Green
            TxtStatus.Text = string.IsNullOrEmpty(_xrayService.CurrentServerName)
                ? "VPN подключён"
                : $"Подключено: {_xrayService.CurrentServerName}";
            BtnToggleConnect.Content = "Отключить";
            BtnToggleConnect.Background = new SolidColorBrush(Color.FromRgb(220, 53, 69)); // Red
        }
        else
        {
            StatusDot.Foreground = new SolidColorBrush(Color.FromRgb(108, 117, 125)); // Gray
            TxtStatus.Text = "VPN выключен";
            BtnToggleConnect.Content = "Подключить";
            BtnToggleConnect.Background = new SolidColorBrush(Color.FromRgb(255, 85, 0)); // Accent
        }
    }

    private async void BtnRefreshKey_Click(object sender, RoutedEventArgs e)
    {
        var key = TxtSubscription.Text.Trim();
        if (string.IsNullOrEmpty(key))
        {
            TxtStatus.Text = "Вставьте ссылку подписки или конфигурационный ключ";
            return;
        }

        TxtStatus.Text = "Загрузка и разбор подписки...";
        BtnRefreshKey.IsEnabled = false;

        try
        {
            var rawText = await SubscriptionParser.FetchTextAsync(key);
            var parsed = SubscriptionParser.Parse(rawText);

            if (parsed.Count == 0)
            {
                TxtStatus.Text = "Серверы не найдены. Проверьте формат ключа.";
                return;
            }

            _settings.VpnSubscriptionKey = key;
            _settings.VpnServers = parsed;
            _settings.Save();

            RefreshServerList();
            TxtStatus.Text = $"Загружено {parsed.Count} серверов";

            // Automatically run ping on parsed servers
            _ = PingServersAsync(parsed);
        }
        catch (Exception ex)
        {
            TxtStatus.Text = $"Ошибка: {ex.Message}";
        }
        finally
        {
            BtnRefreshKey.IsEnabled = true;
        }
    }

    private async void BtnPingAll_Click(object sender, RoutedEventArgs e)
    {
        if (_settings.VpnServers.Count == 0) return;
        await PingServersAsync(_settings.VpnServers);
    }

    private async Task PingServersAsync(List<VPNServer> servers)
    {
        BtnPingAll.IsEnabled = false;
        TxtStatus.Text = "Проверка пинга всех серверов...";

        var tasks = servers.Select(s => XrayService.MeasurePingAsync(s, 2500)).ToList();
        await Task.WhenAll(tasks);

        RefreshServerList();
        BtnPingAll.IsEnabled = true;
        UpdateUiState();
    }

    private async void BtnToggleConnect_Click(object sender, RoutedEventArgs e)
    {
        if (_xrayService.IsRunning && _settings.VPNEnabled)
        {
            _xrayService.Stop();
            _settings.VPNEnabled = false;
            _settings.Save();
            UpdateUiState();
            OnProxyStateChanged?.Invoke(false, "");
            return;
        }

        var server = LstServers.SelectedItem as VPNServer ?? _settings.VpnServers.FirstOrDefault();
        if (server == null)
        {
            TxtStatus.Text = "Выберите сервер из списка";
            return;
        }

        await ConnectServerAsync(server);
    }

    private async void LstServers_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (LstServers.SelectedItem is VPNServer server)
        {
            await ConnectServerAsync(server);
        }
    }

    private async Task ConnectServerAsync(VPNServer server)
    {
        TxtStatus.Text = $"Подключение к {server.Name}...";
        BtnToggleConnect.IsEnabled = false;

        try
        {
            // Ensure Xray-core binary is available
            bool ready = await _xrayService.EnsureXrayAvailableAsync(msg => Dispatcher.Invoke(() => TxtStatus.Text = msg));
            if (!ready)
            {
                TxtStatus.Text = "Ошибка: не удалось найти или загрузить Xray-core";
                return;
            }

            bool ok = _xrayService.Start(server);
            if (ok)
            {
                _settings.VPNEnabled = true;
                _settings.SelectedVpnServerUri = server.RawURI;
                _settings.VPNConfig = server.RawURI;
                _settings.Save();

                UpdateUiState();
                OnProxyStateChanged?.Invoke(true, server.Name);
            }
            else
            {
                TxtStatus.Text = "Ошибка: Xray не смог подключиться к выбранному серверу";
            }
        }
        finally
        {
            BtnToggleConnect.IsEnabled = true;
        }
    }

    private void AutoConnect_Changed(object sender, RoutedEventArgs e)
    {
        _settings.VpnAutoConnect = ChkAutoConnect.IsChecked == true;
        _settings.Save();
    }

    private void TitleBar_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            try { DragMove(); } catch { }
        }
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }
}
