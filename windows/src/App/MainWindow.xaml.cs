using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using DieCloud.Models;
using DieCloud.Services;
using DieCloud.Web;

namespace DieCloud;

public partial class MainWindow : Window
{
    private readonly SettingsState _settings;
    private readonly DiscordRPC _discordRpc;
    private readonly XrayService _xrayService;
    private readonly WebViewBridge _bridge;
    private readonly VpnWindow _vpnWindow;
    private readonly UpdateManager _updateManager;
    private NowPlayingSMTC? _smtc;
    private readonly List<Slider> _bandSliders = new();
    private bool _isUpdatingSliders;
    private bool _isInitialized;
    private bool _isProxyBoundToWebView;

    public MainWindow()
    {
        _settings = SettingsState.Load();
        _discordRpc = new DiscordRPC(_settings.EffectiveDiscordClientID);
        _xrayService = new XrayService();
        _bridge = new WebViewBridge(_settings);
        _vpnWindow = new VpnWindow(_settings, _xrayService);
        _updateManager = new UpdateManager();

        _vpnWindow.Owner = this;
        _vpnWindow.OnProxyStateChanged += VpnWindow_OnProxyStateChanged;

        InitializeComponent();
        _isInitialized = true;

        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
        PreviewKeyDown += MainWindow_PreviewKeyDown;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        EnableWindows11Mica();
        InitSettingsUI();
        BuildEqualizerSliders();

        // Check first run / welcome banner
        if (!_settings.WelcomeShown)
        {
            WelcomeOverlay.Visibility = Visibility.Visible;
            WebViewControl.Visibility = Visibility.Collapsed;
        }
        else
        {
            WelcomeOverlay.Visibility = Visibility.Collapsed;
            WebViewControl.Visibility = Visibility.Visible;
        }

        // Initialize SMTC
        var hWnd = new WindowInteropHelper(this).Handle;
        try
        {
            _smtc = new NowPlayingSMTC(hWnd);
            _smtc.OnPlay += () => Dispatcher.Invoke(() => _bridge.ExecuteScriptAsync("window.__diecloude?.togglePlay?.();"));
            _smtc.OnPause += () => Dispatcher.Invoke(() => _bridge.ExecuteScriptAsync("window.__diecloude?.togglePlay?.();"));
            _smtc.OnNext += () => Dispatcher.Invoke(() => _bridge.ExecuteScriptAsync("(window.__diecloude?.next || window.__diecloude?.nextTrack)?.();"));
            _smtc.OnPrevious += () => Dispatcher.Invoke(() => _bridge.ExecuteScriptAsync("(window.__diecloude?.prev || window.__diecloude?.prevTrack)?.();"));
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SMTC initialization warning: {ex.Message}");
        }

        // Auto-connect to VPN on launch if enabled
        bool useProxy = false;
        if (_settings.VpnAutoConnect && !string.IsNullOrEmpty(_settings.SelectedVpnServerUri))
        {
            var server = _settings.VpnServers.FirstOrDefault(s => s.RawURI == _settings.SelectedVpnServerUri);
            if (server != null)
            {
                bool ready = await _xrayService.EnsureXrayAvailableAsync();
                if (ready && _xrayService.Start(server))
                {
                    _settings.VPNEnabled = true;
                    useProxy = true;
                    UpdateVpnToolbarState(true);
                }
            }
        }
        else if (_xrayService.IsXrayInstalled && _xrayService.StartDirectMode())
        {
            // Start Xray in direct pass-through mode so WebView2 can always bind to 127.0.0.1:17890
            // and switch to any VPN server at runtime without requiring an app restart!
            useProxy = true;
        }

        _isProxyBoundToWebView = useProxy;

        // Wire progress bar
        _bridge.OnNavigationStarting += () => Dispatcher.Invoke(() =>
        {
            WebProgressBar.Visibility = Visibility.Visible;
            WebProgressBar.IsIndeterminate = true;
        });

        _bridge.OnNavigationCompleted += (ok) => Dispatcher.Invoke(() =>
        {
            WebProgressBar.Visibility = Visibility.Collapsed;
            WebProgressBar.IsIndeterminate = false;
        });

        WebProgressBar.Visibility = Visibility.Visible;
        try
        {
            await _bridge.InitializeAsync(WebViewControl, useProxy);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Не удалось запустить компонент Microsoft Edge WebView2.\n\n" +
                            "Если у вас Windows 10, убедитесь, что установлен Microsoft Edge WebView2 Runtime:\n" +
                            "https://developer.microsoft.com/en-us/microsoft-edge/webview2/\n\n" +
                            "Детали: " + ex.Message,
                            "DieCloud", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            WebProgressBar.Visibility = Visibility.Collapsed;
        }

        // Bridge event subscriptions
        _bridge.OnMetaReceived += Bridge_OnMetaReceived;
        _bridge.OnPlaybackStateReceived += Bridge_OnPlaybackStateReceived;
        _bridge.OnVolumeReceived += Bridge_OnVolumeReceived;
        _bridge.OnEscapeReceived += () => Dispatcher.Invoke(CloseAllOverlays);

        // Discord RPC enable state
        _discordRpc.SetEnabled(_settings.DiscordRPC);

        // Sync Toolbar buttons visual states
        UpdateAdBlockToolbarState(_settings.AdBlock);
        UpdateVpnToolbarState(_xrayService.IsRunning && _settings.VPNEnabled);

        // Check for updates silently in the background after 4 seconds (matching macOS)
        _ = Task.Delay(4000).ContinueWith(_ => Dispatcher.Invoke(() => _updateManager.CheckForUpdatesAsync(this, silentWhenCurrent: true)));
    }

    private void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _discordRpc.Dispose();
        _smtc?.Dispose();
        _xrayService.Dispose();
        _vpnWindow.Close();
    }

    private void EnableWindows11Mica()
    {
        try
        {
            var hWnd = new WindowInteropHelper(this).Handle;
            int trueVal = 1;
            // DWMWA_USE_IMMERSIVE_DARK_MODE = 20
            DwmSetWindowAttribute(hWnd, 20, ref trueVal, sizeof(int));

            // DWMWA_SYSTEMBACKDROP_TYPE = 38 (2 = Mica, 3 = Acrylic)
            int micaVal = 2;
            DwmSetWindowAttribute(hWnd, 38, ref micaVal, sizeof(int));
        }
        catch { }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    #region Settings UI Binding
    private void InitSettingsUI()
    {
        _isInitialized = false;
        ChkModernDesign.IsChecked = _settings.ModernDesign;
        ChkTheme.IsChecked = _settings.Theme;
        ChkRoundedCards.IsChecked = _settings.RoundedCards;
        ChkArtworkHover.IsChecked = _settings.ArtworkHover;
        ChkFocus.IsChecked = _settings.Focus;
        ChkAdBlock.IsChecked = _settings.AdBlock;
        ChkDiscordRPC.IsChecked = _settings.DiscordRPC;
        TxtDiscordClientId.Text = _settings.DiscordClientID == SettingsState.DefaultDiscordClientID ? "" : _settings.DiscordClientID;
        ChkEqualizer.IsChecked = _settings.EqualizerEnabled;
        ChkNormalization.IsChecked = _settings.EqualizerNormalization;

        RbAccentMono.IsChecked = _settings.Accent == "mono";
        RbAccentAmber.IsChecked = _settings.Accent == "amber";
        RbAccentBlue.IsChecked = _settings.Accent == "blue";

        _isInitialized = true;
    }

    private void BuildEqualizerSliders()
    {
        SlidersContainer.Children.Clear();
        _bandSliders.Clear();

        for (int i = 0; i < SettingsState.EqualizerFrequencies.Length; i++)
        {
            int freq = SettingsState.EqualizerFrequencies[i];
            int index = i;

            var row = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(45) });

            string label = freq >= 1000 ? $"{freq / 1000.0} кГц" : $"{freq} Гц";
            var textFreq = new TextBlock
            {
                Text = label,
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromRgb(138, 146, 166)),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(textFreq, 0);

            var slider = new Slider
            {
                Minimum = -12,
                Maximum = 12,
                Value = _settings.EqualizerBands[i],
                SmallChange = 1,
                LargeChange = 3,
                Tag = index,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(6, 0, 6, 0)
            };
            slider.ValueChanged += Slider_ValueChanged;
            Grid.SetColumn(slider, 1);
            _bandSliders.Add(slider);

            var textVal = new TextBlock
            {
                Text = $"{slider.Value:0} дБ",
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.FromRgb(108, 117, 125)),
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Right
            };
            Grid.SetColumn(textVal, 2);

            slider.Tag = (index, textVal);

            row.Children.Add(textFreq);
            row.Children.Add(slider);
            row.Children.Add(textVal);

            SlidersContainer.Children.Add(row);
        }
    }

    private void Slider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!_isInitialized || _isUpdatingSliders || sender is not Slider slider) return;
        if (slider.Tag is (int index, TextBlock valText))
        {
            valText.Text = $"{e.NewValue:0} дБ";
            _settings.EqualizerBands[index] = Math.Round(e.NewValue, 1);
            _settings.Save();
            _ = _bridge.PushAllSettingsAsync();
        }
    }

    private void EqualizerToggle_Changed(object sender, RoutedEventArgs e)
    {
        if (!_isInitialized) return;
        _settings.EqualizerEnabled = ChkEqualizer.IsChecked == true;
        _settings.EqualizerNormalization = ChkNormalization.IsChecked == true;
        _settings.Save();
        _ = _bridge.PushAllSettingsAsync();
    }

    private void CmbPresets_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isInitialized || _bandSliders.Count == 0) return;
        string[] presetKeys = ["flat", "bassBoost", "electronic", "rock", "vocal", "acoustic"];
        int idx = CmbPresets.SelectedIndex;
        if (idx >= 0 && idx < presetKeys.Length)
        {
            var bands = SettingsState.EqualizerPresets[presetKeys[idx]];
            _isUpdatingSliders = true;
            for (int i = 0; i < bands.Length && i < _bandSliders.Count; i++)
            {
                _bandSliders[i].Value = bands[i];
                _settings.EqualizerBands[i] = bands[i];
            }
            _isUpdatingSliders = false;
            _settings.Save();
            _ = _bridge.PushAllSettingsAsync();
        }
    }

    private void AccentChanged(object sender, RoutedEventArgs e)
    {
        if (!_isInitialized) return;
        if (RbAccentAmber.IsChecked == true) _settings.Accent = "amber";
        else if (RbAccentBlue.IsChecked == true) _settings.Accent = "blue";
        else _settings.Accent = "mono";

        _settings.Save();
        _ = _bridge.PushAllSettingsAsync();
    }

    private void SettingChanged(object sender, RoutedEventArgs e)
    {
        if (!_isInitialized) return;
        _settings.ModernDesign = ChkModernDesign.IsChecked == true;
        _settings.Theme = ChkTheme.IsChecked == true;
        _settings.RoundedCards = ChkRoundedCards.IsChecked == true;
        _settings.ArtworkHover = ChkArtworkHover.IsChecked == true;
        _settings.Focus = ChkFocus.IsChecked == true;
        _settings.AdBlock = ChkAdBlock.IsChecked == true;
        _settings.DiscordRPC = ChkDiscordRPC.IsChecked == true;

        UpdateAdBlockToolbarState(_settings.AdBlock);
        _discordRpc.SetEnabled(_settings.DiscordRPC);
        _settings.Save();
        _ = _bridge.PushAllSettingsAsync();
    }

    private void TxtDiscordClientId_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!_isInitialized) return;
        _settings.DiscordClientID = TxtDiscordClientId.Text;
        _discordRpc.SetClientID(_settings.EffectiveDiscordClientID);
        _settings.Save();
    }

    private void BtnAdBlock_Click(object sender, RoutedEventArgs e)
    {
        _settings.AdBlock = !_settings.AdBlock;
        ChkAdBlock.IsChecked = _settings.AdBlock;
        UpdateAdBlockToolbarState(_settings.AdBlock);
        _settings.Save();
        _ = _bridge.PushAllSettingsAsync();
    }

    private void UpdateAdBlockToolbarState(bool isEnabled)
    {
        if (isEnabled)
        {
            BtnAdBlock.Foreground = new SolidColorBrush(Color.FromRgb(52, 199, 89)); // Green
            IconAdBlock.Opacity = 1.0;
        }
        else
        {
            BtnAdBlock.Foreground = new SolidColorBrush(Color.FromRgb(160, 168, 186));
            IconAdBlock.Opacity = 0.45;
        }
    }

    private void BtnVpn_Click(object sender, RoutedEventArgs e) => OpenVpnWindow();
    private void BtnOpenVpn_Click(object sender, RoutedEventArgs e) => OpenVpnWindow();

    private void OpenVpnWindow()
    {
        _vpnWindow.Show();
        _vpnWindow.Activate();
    }

    private void VpnWindow_OnProxyStateChanged(bool isConnected, string serverName)
    {
        UpdateVpnToolbarState(isConnected);
        if (_isProxyBoundToWebView)
        {
            _ = _bridge.ExecuteScriptAsync("location.reload();");
        }
        else
        {
            MessageBox.Show(this,
                "VPN активирован. Для применения прокси к встроенному браузеру, пожалуйста, перезапустите DieCloud (при следующем запуске прокси будет подключаться моментально без перезапусков).",
                "DieCloud VPN", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void UpdateVpnToolbarState(bool isConnected)
    {
        if (isConnected)
        {
            BtnVpn.Foreground = new SolidColorBrush(Color.FromRgb(52, 199, 89)); // Green
            IconVpn.Text = "🛡️";
        }
        else
        {
            BtnVpn.Foreground = new SolidColorBrush(Color.FromRgb(160, 168, 186));
            IconVpn.Text = "🔒";
        }
    }

    private void BtnResetDesign_Click(object sender, RoutedEventArgs e)
    {
        _settings.ResetDesign();
        InitSettingsUI();
        _ = _bridge.PushAllSettingsAsync();
    }

    private void BtnCheckUpdates_Click(object sender, RoutedEventArgs e)
    {
        _ = _updateManager.CheckForUpdatesAsync(this, silentWhenCurrent: false);
    }
    #endregion

    #region Bridge Events
    private void Bridge_OnMetaReceived(string title, string artist, string artwork, string trackUrl)
    {
        Dispatcher.Invoke(() =>
        {
            TitleNowPlaying.Text = string.IsNullOrEmpty(artist) ? title : $"{artist} — {title}";
            _smtc?.UpdateMetadata(title, artist, artwork);
            _discordRpc.Update(new DiscordRPC.Playback
            {
                Title = title,
                Artist = artist,
                Artwork = artwork,
                TrackURL = trackUrl,
                Playing = true
            });
        });
    }

    private void Bridge_OnPlaybackStateReceived(bool playing, double position, double duration)
    {
        Dispatcher.Invoke(() =>
        {
            _smtc?.UpdatePlaybackState(playing);
            _discordRpc.Update(new DiscordRPC.Playback
            {
                Playing = playing,
                Position = position,
                Duration = duration
            });
        });
    }

    private void Bridge_OnVolumeReceived(double volume, bool muted)
    {
        Dispatcher.Invoke(() =>
        {
            _settings.Volume = volume;
            _settings.IsMuted = muted;
            _settings.Save();
        });
    }
    #endregion

    #region Window Controls & Hotkeys
    private void TitleBar_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            // Do not start drag if user clicked directly on any button
            if (e.OriginalSource is DependencyObject dep && FindVisualParent<Button>(dep) != null)
            {
                return;
            }

            if (e.ClickCount == 2)
            {
                BtnMaximize_Click(sender, e);
            }
            else
            {
                try { DragMove(); } catch { }
            }
        }
    }

    private static T? FindVisualParent<T>(DependencyObject? child) where T : DependencyObject
    {
        while (child != null)
        {
            if (child is T parent) return parent;
            child = VisualTreeHelper.GetParent(child);
        }
        return null;
    }

    private void BtnMinimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void BtnMaximize_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized)
        {
            WindowState = WindowState.Normal;
            MaximizeIcon.Text = "🗖";
        }
        else
        {
            WindowState = WindowState.Maximized;
            MaximizeIcon.Text = "🗗";
        }
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    private void BtnSettings_Click(object sender, RoutedEventArgs e)
    {
        SettingsPanel.Visibility = SettingsPanel.Visibility == Visibility.Visible
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void CloseSettings_Click(object sender, RoutedEventArgs e) => SettingsPanel.Visibility = Visibility.Collapsed;

    private void WelcomeOverlay_MouseDown(object sender, MouseButtonEventArgs e)
    {
        // Dismiss if user clicks directly on the dark overlay background outside the card
        if (e.OriginalSource == WelcomeOverlay)
        {
            StartListening_Click(sender, e);
        }
    }

    private void StartListening_Click(object sender, RoutedEventArgs e)
    {
        WelcomeOverlay.Visibility = Visibility.Collapsed;
        WebViewControl.Visibility = Visibility.Visible;
        _settings.WelcomeShown = ChkDontShowWelcome.IsChecked == true;
        _settings.Save();
    }

    private void CloseAllOverlays()
    {
        SettingsPanel.Visibility = Visibility.Collapsed;
        if (WelcomeOverlay.Visibility == Visibility.Visible)
        {
            WelcomeOverlay.Visibility = Visibility.Collapsed;
            WebViewControl.Visibility = Visibility.Visible;
        }
    }

    private void MainWindow_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            CloseAllOverlays();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Enter && WelcomeOverlay.Visibility == Visibility.Visible)
        {
            StartListening_Click(sender, e);
            e.Handled = true;
            return;
        }

        // Hardware multimedia keys (Keyboards & Headsets)
        if (e.Key == Key.MediaPlayPause)
        {
            _ = _bridge.ExecuteScriptAsync("window.__diecloude?.togglePlay?.();");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.MediaNextTrack)
        {
            _ = _bridge.ExecuteScriptAsync("(window.__diecloude?.next || window.__diecloude?.nextTrack)?.();");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.MediaPreviousTrack)
        {
            _ = _bridge.ExecuteScriptAsync("(window.__diecloude?.prev || window.__diecloude?.prevTrack)?.();");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.MediaStop)
        {
            _ = _bridge.ExecuteScriptAsync("window.__diecloude?.togglePlay?.();");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.VolumeMute)
        {
            _ = _bridge.ExecuteScriptAsync("window.__diecloude?.toggleMute?.();");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.VolumeUp)
        {
            _ = _bridge.ExecuteScriptAsync("window.__diecloude?.changeVolume?.(0.05);");
            e.Handled = true;
            return;
        }
        if (e.Key == Key.VolumeDown)
        {
            _ = _bridge.ExecuteScriptAsync("window.__diecloude?.changeVolume?.(-0.05);");
            e.Handled = true;
            return;
        }

        // Global hotkeys matching macOS
        if (Keyboard.Modifiers == ModifierKeys.Alt)
        {
            if (e.Key == Key.Up)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.changeVolume?.(0.05);");
                e.Handled = true;
            }
            else if (e.Key == Key.Down)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.changeVolume?.(-0.05);");
                e.Handled = true;
            }
            else if (e.Key == Key.M)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.toggleMute?.();");
                e.Handled = true;
            }
        }
        else if (Keyboard.Modifiers == ModifierKeys.Control)
        {
            if (e.Key == Key.Left)
            {
                _ = _bridge.ExecuteScriptAsync("(window.__diecloude?.prev || window.__diecloude?.prevTrack)?.();");
                e.Handled = true;
            }
            else if (e.Key == Key.Right)
            {
                _ = _bridge.ExecuteScriptAsync("(window.__diecloude?.next || window.__diecloude?.nextTrack)?.();");
                e.Handled = true;
            }
            else if (e.Key == Key.P)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.togglePlay?.();");
                e.Handled = true;
            }
            else if (e.Key == Key.L)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.toggleLike?.();");
                e.Handled = true;
            }
        }
        else if (Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift))
        {
            if (e.Key == Key.Right)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.seekBy?.(10);");
                e.Handled = true;
            }
            else if (e.Key == Key.Left)
            {
                _ = _bridge.ExecuteScriptAsync("window.__diecloude?.seekBy?.(-10);");
                e.Handled = true;
            }
        }
    }
    #endregion
}
