import Foundation

/// Скрипты управления плеером в WKWebView: используют API `window.__diecloude`
/// с безопасным DOM-фолбэком по селекторам и `aria-label`.
enum PlayerScripts {
    static let togglePlay = """
    (function(){
      if (window.__diecloude && typeof window.__diecloude.togglePlay === 'function') {
        return window.__diecloude.togglePlay();
      }
      var b = document.querySelector('.playControls__play, button.playControl');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/play current|pause current|воспроизвед|пауз/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) { b.click(); return true; }
      var a = document.querySelector('audio');
      if (a) { a.paused ? a.play() : a.pause(); return true; }
      return false;
    })();
    """

    static let nextTrack = """
    (function(){
      if (window.__diecloude && typeof window.__diecloude.next === 'function') {
        return window.__diecloude.next();
      }
      var b = document.querySelector('.skipControls__next');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/next|следующ/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) { b.click(); return true; }
      return false;
    })();
    """

    static let previousTrack = """
    (function(){
      if (window.__diecloude && typeof window.__diecloude.prev === 'function') {
        return window.__diecloude.prev();
      }
      var b = document.querySelector('.skipControls__previous');
      if (!b) {
        var all = document.querySelectorAll('button[aria-label]');
        for (var i = 0; i < all.length; i++) {
          if (/previous|prev|предыдущ/i.test(all[i].getAttribute('aria-label') || '')) { b = all[i]; break; }
        }
      }
      if (b) { b.click(); return true; }
      return false;
    })();
    """

    static func seekBy(_ deltaSeconds: Double) -> String {
        "window.__diecloude?.seekBy(\(deltaSeconds));"
    }

    static func seekTo(_ seconds: Double) -> String {
        "window.__diecloude?.seek(\(seconds));"
    }

    static func changeVolume(_ delta: Double) -> String {
        "window.__diecloude?.changeVolume(\(delta));"
    }

    static func setVolume(_ value: Double) -> String {
        "window.__diecloude?.setVolume(\(value));"
    }

    static let toggleMute = "window.__diecloude?.toggleMute();"

    static let toggleLike = "window.__diecloude?.toggleLike();"
}
