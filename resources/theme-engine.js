(() => {
  'use strict';

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine-352-polish';
  const state = { settings: { ...initial }, observer: null, frame: 0 };

  const selectors = {
    header: '.header, header[role="banner"]',
    player: '.playControls, [data-testid="play-controls"]',
    artwork: [
      '.sound__coverArt',
      '.trackItem__artwork',
      '.soundBadge__avatar',
      '.systemPlaylist__artwork',
      '.playbackSoundBadge__avatar',
      '.visualSound__artwork',
      '.listenArtworkWrapper',
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
    promos: '.header__goUpsell, [class*="upsell" i], [class*="promo" i]',
    ads: '[class*="adBanner" i],[class*="advertisement" i],[class*="sponsored" i],[data-testid*="advert" i],[aria-label*="advertisement" i],[aria-label*="реклама" i],iframe[src*="doubleclick"],iframe[src*="googlesyndication"]'
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

      /* Matte player: translucent, blurred and visually continuous. */
      html.dc-modern [data-dc-player] {
        background: rgba(14,15,19,.74) !important;
        -webkit-backdrop-filter: blur(22px) saturate(135%) !important;
        backdrop-filter: blur(22px) saturate(135%) !important;
        border-top: 1px solid rgba(255,255,255,.10) !important;
        box-shadow: 0 -10px 32px rgba(0,0,0,.20) !important;
        isolation: isolate !important;
      }
      html.dc-modern [data-dc-player]::before {
        content: "";
        position: absolute;
        inset: 0;
        pointer-events: none;
        background: linear-gradient(180deg, rgba(255,255,255,.035), transparent 45%);
        z-index: -1;
      }
      html.dc-modern [data-dc-player] > *,
      html.dc-modern [data-dc-player] [class*="playControls__"],
      html.dc-modern [data-dc-player] [class*="playbackSoundBadge"] {
        background-color: transparent !important;
      }
      html.dc-modern [data-dc-player] button,
      html.dc-modern [data-dc-player] a,
      html.dc-modern [data-dc-player] [role="button"] {
        background-color: transparent !important;
        box-shadow: none !important;
        border-color: transparent !important;
        transition: opacity var(--dc-fast), transform var(--dc-fast) !important;
      }
      html.dc-modern [data-dc-player] button:hover,
      html.dc-modern [data-dc-player] a:hover,
      html.dc-modern [data-dc-player] [role="button"]:hover {
        opacity: .88 !important;
        transform: translateY(-1px) !important;
      }
      html.dc-modern [data-dc-player] button:active,
      html.dc-modern [data-dc-player] a:active,
      html.dc-modern [data-dc-player] [role="button"]:active {
        transform: scale(.96) !important;
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

      /* Rounded artwork without clip-path seams or rounded card frames. */
      html.dc-rounded [data-dc-artwork] {
        border-radius: 11px !important;
        overflow: hidden !important;
        background-clip: padding-box !important;
        -webkit-mask-image: -webkit-radial-gradient(white, black) !important;
      }
      html.dc-rounded [data-dc-artwork] img,
      html.dc-rounded img[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] .image__full,
      html.dc-rounded [data-dc-artwork] [style*="background-image"] {
        border-radius: 11px !important;
        overflow: hidden !important;
      }
      html.dc-rounded [data-dc-player] [data-dc-artwork],
      html.dc-rounded [data-dc-player] [data-dc-artwork] img {
        border-radius: 7px !important;
      }

      /* Lightweight, reliable animations: artwork and controls only. */
      @keyframes dcArtworkIn {
        from { opacity: .001; transform: scale(.985); }
        to { opacity: 1; transform: scale(1); }
      }
      html.dc-hover [data-dc-artwork] {
        animation: dcArtworkIn 220ms cubic-bezier(.2,.7,.2,1) both;
        transition: transform var(--dc-fast), filter var(--dc-fast), box-shadow var(--dc-fast) !important;
        transform-origin: center;
        backface-visibility: hidden;
      }
      html.dc-hover [data-dc-card]:hover [data-dc-artwork],
      html.dc-hover [data-dc-artwork]:hover {
        transform: scale(1.012) !important;
        filter: brightness(1.035) !important;
        box-shadow: 0 0 0 1px rgba(255,255,255,.12), 0 10px 26px rgba(0,0,0,.20) !important;
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
      scope.querySelectorAll?.(selector).forEach(node => node.setAttribute(attr, ''));
    } catch (_) {}
  }

  function tag(scope = document) {
    markAll(scope, selectors.header, 'data-dc-header');
    markAll(scope, selectors.player, 'data-dc-player');
    markAll(scope, selectors.artwork, 'data-dc-artwork');
    markAll(scope, selectors.card, 'data-dc-card');
    markAll(scope, selectors.rightRail, 'data-dc-right-rail');
    markAll(scope, selectors.comments, 'data-dc-comments');
    markAll(scope, selectors.promos, 'data-dc-promo');
  }

  function removeAds(scope = document) {
    if (!state.settings.adBlock) return;
    try {
      if (scope instanceof Element && scope.matches(selectors.ads)) scope.remove();
      scope.querySelectorAll?.(selectors.ads).forEach(node => node.remove());
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
  }

  function refresh(scope = document) {
    tag(scope);
    removeAds(scope);
    applyClasses();
  }

  function schedule(scope = document) {
    if (state.frame) return;
    state.frame = requestAnimationFrame(() => {
      state.frame = 0;
      refresh(scope);
    });
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
    if (state.frame) cancelAnimationFrame(state.frame);
    document.getElementById(STYLE_ID)?.remove();
    root.classList.remove('dc-modern','dc-theme','dc-rounded','dc-hover','dc-compact','dc-focus');
  };

  window.__diecloudeThemeEngine = state;
  window.__diecloude = state;

  state.observer = new MutationObserver(records => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node instanceof Element) {
          tag(node);
          removeAds(node);
        }
      }
    }
    schedule(document);
  });
  state.observer.observe(document.body || root, { childList: true, subtree: true });
  refresh(document);
})();
