(() => {
  'use strict';

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine';
  const state = { settings: { ...initial }, observer: null, timer: 0, frame: 0 };

  const selectors = {
    header: '.header, header[role="banner"]',
    player: '.playControls, .playControls__inner, [data-testid="play-controls"]',
    playerBar: 'footer, [role="contentinfo"], .player, .player__container',
    artwork: [
      '.sound__coverArt',
      '.trackItem__artwork',
      '.soundBadge__avatar',
      '.systemPlaylist__artwork',
      '.playbackSoundBadge__avatar',
      '.visualSound__artwork',
      '.listenArtworkWrapper',
      '.sc-artwork',
      '.image__full'
    ].join(','),
    card: [
      '.sound',
      '.trackItem',
      '.soundBadge',
      '.systemPlaylist',
      '.searchItem',
      '.visualSound'
    ].join(','),
    rightRail: '.stream__right, .sidebarModule, .relatedSounds, aside',
    comments: '.commentsList, [class*="commentsList"]',
    promos: '.header__goUpsell, .premiumNudge, .adsBox, [class*="upsell" i], [class*="promo" i], [class*="promoted" i], [class*="premium-nudge" i]',
    ads: [
      '[class*="adBanner" i]',
      '[class*="advertisement" i]',
      '[class*="sponsored" i]',
      '[class*="promotedTrack" i]',
      '[data-testid*="advert" i]',
      '[data-testid*="sponsor" i]',
      '[aria-label*="advertisement" i]',
      '[aria-label*="реклама" i]',
      'iframe[src*="doubleclick"]',
      'iframe[src*="googlesyndication"]',
      'iframe[src*="amazon-adsystem"]',
      'iframe[src*="moatads"]'
    ].join(',')
  };

  function addStyle() {
    document.getElementById(STYLE_ID)?.remove();
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      :root {
        --dc-bg: #090a0d;
        --dc-surface: #0e0f13;
        --dc-surface-2: #15161c;
        --dc-text: #f5f5f7;
        --dc-muted: #9b9da5;
        --dc-line: rgba(255,255,255,.085);
        --dc-line-strong: rgba(255,255,255,.16);
        --dc-radius: 12px;
        --dc-fast: 140ms cubic-bezier(.2,.7,.2,1);
      }

      html.dc-modern { color-scheme: dark; background: var(--dc-bg) !important; }
      html.dc-modern body,
      html.dc-modern #app,
      html.dc-modern .l-container,
      html.dc-modern .l-content,
      html.dc-modern .l-fluid-fixed,
      html.dc-modern .l-inner-fullwidth,
      html.dc-modern main {
        background: var(--dc-bg) !important;
        color: var(--dc-text) !important;
      }
      /* Меньше нагрева: контент не перерисовывается целиком */
      html.dc-modern .soundList__item,
      html.dc-modern .trackItem,
      html.dc-modern .soundBadge {
        content-visibility: auto;
        contain-intrinsic-size: auto 180px;
      }

      html.dc-modern [data-dc-header] {
        background: var(--dc-surface) !important;
        border-bottom: 1px solid var(--dc-line) !important;
        box-shadow: none !important;
      }

      html.dc-modern .headerSearch__input,
      html.dc-modern input[type="search"],
      html.dc-modern input[type="text"] {
        background: var(--dc-surface-2) !important;
        border: 1px solid var(--dc-line) !important;
        border-radius: 11px !important;
        color: var(--dc-text) !important;
        box-shadow: none !important;
        transition: border-color var(--dc-fast), background-color var(--dc-fast) !important;
      }
      html.dc-modern .headerSearch__input:focus,
      html.dc-modern input[type="search"]:focus,
      html.dc-modern input[type="text"]:focus {
        border-color: var(--dc-line-strong) !important;
        background: #191a20 !important;
        box-shadow: 0 0 0 3px rgba(255,255,255,.035) !important;
      }

      html.dc-modern .sc-text-light,
      html.dc-modern .sc-link-light,
      html.dc-modern .soundTitle__username,
      html.dc-modern .trackItem__username,
      html.dc-modern .playbackSoundBadge__lightLink {
        color: var(--dc-muted) !important;
      }

      /* Matte player: полупрозрачность держится и при hover/focus —
         SoundCloud перекрашивает плеер по :hover и перерендеривает узлы,
         поэтому те же правила дублируются для :hover/:focus-within/:active,
         для родительской планки и напрямую для нативных классов
         (на случай если data-атрибут ещё не проставлен после перерендера). */
      html.dc-modern [data-dc-player],
      html.dc-modern [data-dc-playerbar],
      html.dc-modern .playControls,
      html.dc-modern [data-testid="play-controls"] {
        background-color: rgba(15,16,21,.68) !important;
        background-image: none !important;
        -webkit-backdrop-filter: blur(20px) saturate(150%) !important;
        backdrop-filter: blur(20px) saturate(150%) !important;
        border-top: 1px solid rgba(255,255,255,.12) !important;
        box-shadow: 0 -8px 28px rgba(0,0,0,.25) !important;
        isolation: isolate !important;
        transition-property: opacity, border-color, box-shadow !important;
      }
      html.dc-modern [data-dc-player]:hover,
      html.dc-modern [data-dc-player]:focus-within,
      html.dc-modern [data-dc-player]:active,
      html.dc-modern [data-dc-playerbar]:hover,
      html.dc-modern [data-dc-playerbar]:focus-within,
      html.dc-modern [data-dc-playerbar]:active,
      html.dc-modern .playControls:hover,
      html.dc-modern .playControls:focus-within,
      html.dc-modern .playControls:active,
      html.dc-modern [data-testid="play-controls"]:hover,
      html.dc-modern [data-testid="play-controls"]:focus-within,
      html.dc-modern [data-testid="play-controls"]:active {
        background-color: rgba(15,16,21,.68) !important;
        background-image: none !important;
        -webkit-backdrop-filter: blur(20px) saturate(150%) !important;
        backdrop-filter: blur(20px) saturate(150%) !important;
        border-top: 1px solid rgba(255,255,255,.12) !important;
        box-shadow: 0 -8px 28px rgba(0,0,0,.25) !important;
      }
      html.dc-modern [data-dc-player] > *,
      html.dc-modern [data-dc-playerbar] > *,
      html.dc-modern [data-dc-player] [class*="playControls__"],
      html.dc-modern [data-dc-playerbar] [class*="playControls__"],
      html.dc-modern [data-dc-player] [class*="playbackSoundBadge"],
      html.dc-modern [data-dc-playerbar] [class*="playbackSoundBadge"],
      html.dc-modern [data-dc-player]:hover > *,
      html.dc-modern [data-dc-playerbar]:hover > *,
      html.dc-modern [data-dc-player]:hover [class*="playControls__"],
      html.dc-modern [data-dc-playerbar]:hover [class*="playControls__"],
      html.dc-modern [data-dc-player]:hover [class*="playbackSoundBadge"],
      html.dc-modern [data-dc-playerbar]:hover [class*="playbackSoundBadge"] {
        background-color: transparent !important;
        background-image: none !important;
      }
      html.dc-modern [data-dc-player] button,
      html.dc-modern [data-dc-player] a,
      html.dc-modern [data-dc-player] [role="button"] {
        background-color: transparent !important;
        box-shadow: none !important;
        border-color: transparent !important;
        transition: opacity var(--dc-fast) !important;
      }
      html.dc-modern [data-dc-player] button:hover,
      html.dc-modern [data-dc-player] a:hover,
      html.dc-modern [data-dc-player] [role="button"]:hover {
        opacity: .88 !important;
      }

      /* Do not reposition the native SoundCloud timeline. Only recolor it. */
      html.dc-modern .playbackTimeline__progressBackground {
        background-color: rgba(255,255,255,.16) !important;
        border-radius: 999px !important;
      }
      html.dc-modern .playbackTimeline__progressBar,
      html.dc-modern .playbackTimeline__progress {
        background-color: #fff !important;
        border-radius: 999px !important;
      }
      html.dc-modern .playbackTimeline__progressHandle {
        background-color: #fff !important;
        border-color: #fff !important;
        box-shadow: none !important;
      }

      html.dc-theme .header__goUpsell,
      html.dc-theme .sc-button-cta,
      html.dc-theme .sc-button-primary {
        background: transparent !important;
        border: 1px solid rgba(255,255,255,.32) !important;
        color: #fff !important;
        box-shadow: none !important;
      }
      html.dc-theme .header__goUpsell:hover,
      html.dc-theme .sc-button-cta:hover,
      html.dc-theme .sc-button-primary:hover {
        background: rgba(255,255,255,.08) !important;
        border-color: rgba(255,255,255,.5) !important;
      }
      html.dc-theme .header__goUpsell *,
      html.dc-theme .sc-button-cta *,
      html.dc-theme .sc-button-primary * { color: #fff !important; fill: #fff !important; }

      /* noAds V8: жёсткое скрытие рекламы даже если network-правило пропустило */
      html.dc-noads [data-dc-ad],
      html.dc-noads [data-dc-promo] {
        display: none !important;
      }

      /* Скругление обложек: SoundCloud рисует каверы абсолютно-позиционированными
         слоями (.image__full, .sc-artwork, background-image), которые overflow:hidden
         статичного предка НЕ обрезает — поэтому радиус ставится и на сам
         рисуемый узел, а маска заставляет WebKit композитить углы чисто. */
      html.dc-rounded [data-dc-artwork] {
        border-radius: 11px !important;
        overflow: hidden !important;
        background-clip: padding-box !important;
        isolation: isolate !important;
        -webkit-mask-image: -webkit-radial-gradient(white, black) !important;
        mask-image: radial-gradient(white, black) !important;
      }
      html.dc-rounded [data-dc-artwork] img,
      html.dc-rounded img[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] .image__full,
      html.dc-rounded .image__full[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] .sc-artwork,
      html.dc-rounded .sc-artwork[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] [style*="background-image"] {
        border-radius: 11px !important;
        background-clip: padding-box !important;
        -webkit-mask-image: -webkit-radial-gradient(white, black) !important;
        mask-image: radial-gradient(white, black) !important;
      }
      html.dc-rounded [data-dc-player] [data-dc-artwork],
      html.dc-rounded [data-dc-player] [data-dc-artwork] img,
      html.dc-rounded [data-dc-player] .image__full,
      html.dc-rounded [data-dc-player] .sc-artwork,
      html.dc-rounded [data-dc-playerbar] [data-dc-artwork],
      html.dc-rounded [data-dc-playerbar] [data-dc-artwork] img,
      html.dc-rounded [data-dc-playerbar] .image__full,
      html.dc-rounded [data-dc-playerbar] .sc-artwork {
        border-radius: 8px !important;
      }

      /* Lightweight animations: только transform/opacity, без box-shadow каждый кадр */
      @keyframes dcArtworkIn {
        from { opacity: .001; }
        to { opacity: 1; }
      }
      html.dc-hover [data-dc-artwork] {
        animation: dcArtworkIn 180ms ease-out both;
        backface-visibility: hidden;
      }
      html.dc-hover [data-dc-card]:hover [data-dc-artwork],
      html.dc-hover [data-dc-artwork]:hover {
        filter: brightness(1.04) !important;
      }
      @media (prefers-reduced-motion: reduce) {
        html.dc-hover [data-dc-artwork],
        html.dc-modern [data-dc-player] button,
        html.dc-modern [data-dc-player] a,
        html.dc-modern [data-dc-player] [role="button"] {
          animation: none !important;
          transition-duration: 1ms !important;
        }
      }
      @media (prefers-reduced-transparency: reduce) {
        html.dc-modern [data-dc-player] {
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
          background: #0e0f13 !important;
        }
      }

      html.dc-compact .l-container,
      html.dc-compact .l-content { max-width: 1320px !important; }
      html.dc-compact .soundList__item,
      html.dc-compact .trackItem { margin-bottom: 12px !important; }
      html.dc-compact .soundBadge { margin-bottom: 14px !important; }
      html.dc-compact [data-dc-player] { min-height: 46px !important; }

      html.dc-focus [data-dc-right-rail],
      html.dc-focus [data-dc-comments],
      html.dc-focus [data-dc-promo] { display: none !important; }
      html.dc-focus .l-fluid-fixed,
      html.dc-focus main { max-width: 1180px !important; margin-inline: auto !important; }
    `;
    (document.head || root).appendChild(style);
  }

  function markAll(scope, selector, attr) {
    try {
      if (scope instanceof Element && scope.matches(selector)) scope.setAttribute(attr, '');
      scope.querySelectorAll?.(selector).forEach(node => {
        if (!node.hasAttribute(attr)) node.setAttribute(attr, '');
      });
    } catch (_) {}
  }

  function tag(scope = document) {
    markAll(scope, selectors.header, 'data-dc-header');
    markAll(scope, selectors.player, 'data-dc-player');
    markPlayerBar(scope);
    markAll(scope, selectors.artwork, 'data-dc-artwork');
    markAll(scope, selectors.card, 'data-dc-card');
    markAll(scope, selectors.rightRail, 'data-dc-right-rail');
    markAll(scope, selectors.comments, 'data-dc-comments');
    markAll(scope, selectors.promos, 'data-dc-promo');
    markAll(scope, selectors.ads, 'data-dc-ad');
  }

  // Родительская планка плеера (footer-обёртка): красится SoundCloud
  // в сплошной цвет, поэтому помечаем и её — иначе blur перекрывается.
  function markPlayerBar(scope) {
    try {
      const found = [];
      if (scope instanceof Element) {
        if (scope.matches(selectors.player)) found.push(scope);
        const inner = scope.closest?.(selectors.player);
        if (inner) found.push(inner);
        scope.querySelectorAll?.(selectors.player).forEach(node => found.push(node));
      } else {
        scope.querySelectorAll?.(selectors.player).forEach(node => found.push(node));
      }
      for (const el of found) {
        const bar = el.closest?.(selectors.playerBar);
        if (bar && !bar.hasAttribute('data-dc-playerbar')) bar.setAttribute('data-dc-playerbar', '');
      }
    } catch (_) {}
  }

  function removeAds(scope = document) {
    if (!state.settings.adBlock) return;
    try {
      if (scope instanceof Element && scope.matches(selectors.ads)) scope.remove();
      scope.querySelectorAll?.(selectors.ads).forEach(node => node.remove());
      if (scope instanceof Element && scope.matches(selectors.promos)) scope.remove();
      scope.querySelectorAll?.(selectors.promos).forEach(node => {
        // Focus Mode выключен — upsell всё равно скрываем при adBlock
        node.remove();
      });
    } catch (_) {}
  }

  function skipAudioAds(scope = document) {
    if (!state.settings.adBlock) return;
    try {
      const audios = scope instanceof Element && scope.tagName === 'AUDIO'
        ? [scope]
        : Array.from(scope.querySelectorAll?.('audio') ?? []);
      for (const a of audios) {
        const src = (a.currentSrc || a.src || '').toLowerCase();
        if (src.includes('advert') || src.includes('/ads/') || src.includes('promotion')) {
          try { a.muted = true; a.currentTime = (a.duration || 0); a.pause(); } catch (_) {}
          a.remove();
        }
      }
    } catch (_) {}
  }

  function applyClasses() {
    const s = state.settings;
    root.classList.toggle('dc-modern', Boolean(s.modernDesign));
    root.classList.toggle('dc-theme', Boolean(s.theme));
    root.classList.toggle('dc-rounded', Boolean(s.roundedCards));
    root.classList.toggle('dc-hover', Boolean(s.artworkHover));
    root.classList.toggle('dc-compact', Boolean(s.compactMode));
    root.classList.toggle('dc-focus', Boolean(s.focus));
    root.classList.toggle('dc-noads', Boolean(s.adBlock));
  }

  function refresh(scope = document) {
    tag(scope);
    removeAds(scope);
    skipAudioAds(scope);
    applyClasses();
  }

  function schedule(nodes) {
    // 4.0: дебаунс 180мс, обрабатываем только добавленные узлы, не весь document
    if (state.timer) return;
    state.timer = setTimeout(() => {
      state.timer = 0;
      try {
        for (const n of nodes) {
          if (n instanceof Element) {
            tag(n);
            removeAds(n);
            skipAudioAds(n);
          }
        }
      } catch (_) {}
      applyClasses();
    }, 180);
  }

  addStyle();
  state.set = (key, value) => {
    state.settings[key] = Boolean(value);
    refresh(document);
  };
  state.setAll = values => {
    Object.assign(state.settings, values || {});
    refresh(document);
  };
  state.refresh = () => refresh(document);
  state.destroy = () => {
    state.observer?.disconnect();
    if (state.timer) clearTimeout(state.timer);
    if (state.frame) cancelAnimationFrame(state.frame);
    document.getElementById(STYLE_ID)?.remove();
    try {
      document.querySelectorAll?.('[data-dc-playerbar]').forEach(node => node.removeAttribute('data-dc-playerbar'));
    } catch (_) {}
    root.classList.remove('dc-modern','dc-theme','dc-rounded','dc-hover','dc-compact','dc-focus','dc-noads');
  };

  window.__diecloudeThemeEngine = state;
  window.__diecloude = state;

  state.observer = new MutationObserver(records => {
    const batch = [];
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node instanceof Element) batch.push(node);
      }
    }
    if (batch.length) schedule(batch);
  });
  state.observer.observe(document.body || root, { childList: true, subtree: true });
  refresh(document);
})();
