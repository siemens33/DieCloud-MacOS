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
      var b = document.querySelector('.skipControls__next, button.playControls__next, button[title*="next" i], button[aria-label*="next" i], button[aria-label*="следующ" i]');
      var ok = false;
      if (b && !b.disabled) {
        try { b.click(); ok = true; } catch(_) {}
        try { b.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window })); } catch(_) {}
      }
      try {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', code: 'ArrowRight', keyCode: 39, which: 39, shiftKey: true, bubbles: true, cancelable: true }));
        ok = true;
      } catch(_) {}
      return ok;
    })();
    """

    static let previousTrack = """
    (function(){
      if (window.__diecloude && typeof window.__diecloude.prev === 'function') {
        return window.__diecloude.prev();
      }
      var b = document.querySelector('.skipControls__previous, button.playControls__previous, button[title*="prev" i], button[aria-label*="previous" i], button[aria-label*="предыдущ" i]');
      var ok = false;
      if (b && !b.disabled) {
        try { b.click(); ok = true; } catch(_) {}
        try { b.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window })); } catch(_) {}
      }
      try {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', code: 'ArrowLeft', keyCode: 37, which: 37, shiftKey: true, bubbles: true, cancelable: true }));
        ok = true;
      } catch(_) {}
      return ok;
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
