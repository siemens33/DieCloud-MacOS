(() => {
  'use strict';

  // DieCloude 4.1.0 — theme engine
  // Тегирование + MutationObserver + один <style>, как раньше.
  // 4.1.0: матовое стекло плеера вернулось на явные селекторы (без :is-трюков),
  // добавлен мост в приложение (Now Playing, диагностика) и цветовые темы.

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine';
  const state = { settings: { ...initial }, observer: null, timer: 0, frame: 0 };

  const selectors = {
    header: '.header, header[role="banner"]',
    // Планка плеера: тегируем основные узлы, а CSS красит ещё и по подстроке
    // класса — если SoundCloud переименует классы, краска всё равно найдёт бар.
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
      '[class*="promoted" i]',
      '[data-testid*="advert" i]',
      '[data-testid*="sponsor" i]',
      '[data-testid*="promot" i]',
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
        /* Акцент темы. По умолчанию — белый монохром; темы ниже его переопределяют. */
        --dc-accent: #ffffff;
        --dc-accent-soft: rgba(255,255,255,.08);
        --dc-accent-border: rgba(255,255,255,.32);
      }
      html.dc-accent-amber {
        --dc-accent: #e8a33d;
        --dc-accent-soft: rgba(232,163,61,.12);
        --dc-accent-border: rgba(232,163,61,.45);
      }
      html.dc-accent-blue {
        --dc-accent: #4f8cff;
        --dc-accent-soft: rgba(79,140,255,.14);
        --dc-accent-border: rgba(79,140,255,.5);
      }
      /* Системный акцент прилетает из приложения точным hex
         (инлайн-переменная на <html>, см. applyAccent). */

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
        border-color: var(--dc-accent-border) !important;
        background: #191a20 !important;
        box-shadow: 0 0 0 3px var(--dc-accent-soft) !important;
      }

      html.dc-modern .sc-text-light,
      html.dc-modern .sc-link-light,
      html.dc-modern .soundTitle__username,
      html.dc-modern .trackItem__username,
      html.dc-modern .playbackSoundBadge__lightLink {
        color: var(--dc-muted) !important;
      }

      /* Мягкая подсветка строк трек-листа при наведении */
      html.dc-modern .trackList__item:hover,
      html.dc-modern .trackListItem:hover,
      html.dc-modern .trackList__item:focus-within {
        background-color: rgba(255,255,255,.035) !important;
      }

      /* Дозаливка тёмным: всплывающие меню, диалоги, тосты, скроллбары */
      html.dc-modern .dropdownMenu,
      html.dc-modern [class*="dropdownMenu" i],
      html.dc-modern [class*="popover" i],
      html.dc-modern [role="menu"],
      html.dc-modern [role="dialog"],
      html.dc-modern [class*="modal" i],
      html.dc-modern [class*="dialog" i],
      html.dc-modern [class*="toast" i] {
        background-color: var(--dc-surface-2) !important;
        color: var(--dc-text) !important;
        border: 1px solid var(--dc-line) !important;
        border-radius: var(--dc-radius) !important;
        box-shadow: 0 18px 48px rgba(0,0,0,.5) !important;
      }
      html.dc-modern .dropdownMenu *,
      html.dc-modern [class*="dropdownMenu" i] *,
      html.dc-modern [class*="popover" i] *,
      html.dc-modern [role="menu"] *,
      html.dc-modern [role="dialog"] *,
      html.dc-modern [class*="modal" i] * {
        color: var(--dc-text) !important;
      }
      html.dc-modern ::-webkit-scrollbar { width: 10px; height: 10px; }
      html.dc-modern ::-webkit-scrollbar-track { background: transparent; }
      html.dc-modern ::-webkit-scrollbar-thumb {
        background-color: rgba(255,255,255,.14);
        border-radius: 999px;
        border: 2px solid transparent;
        background-clip: padding-box;
      }
      html.dc-modern ::-webkit-scrollbar-thumb:hover { background-color: rgba(255,255,255,.24); }

      /* ─────────────────────────────────────────────────────────────
         МАТОВЫЙ ПЛЕЕР. Реальная разметка SoundCloud (проверено в
         живом DOM): панель — это div.playControls (position:fixed),
         внутри section.playControls__inner[role=contentinfo] с плотным
         серым фоном; <footer> на странице нет. Стекло кладём на сам
         .playControls (и теги движка), всё внутри — прозрачное, кроме
         шкалы/громкости (их красим отдельно) и родной белой кнопки
         .playControls__play — её не трогаем вовсе.
         ───────────────────────────────────────────────────────────── */
      html.dc-modern [data-dc-player],
      html.dc-modern [data-dc-playerbar],
      html.dc-modern .playControls,
      html.dc-modern [data-testid="play-controls"],
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
        background-color: rgba(15,16,20,.72) !important;
        background-image: linear-gradient(180deg, rgba(255,255,255,.07), rgba(255,255,255,0) 46%) !important;
        -webkit-backdrop-filter: blur(30px) saturate(150%) !important;
        backdrop-filter: blur(30px) saturate(150%) !important;
        border-top: 1px solid rgba(255,255,255,.18) !important;
        box-shadow: 0 -6px 24px rgba(0,0,0,.5) !important;
        isolation: isolate !important;
      }

      /* Внутренности планки — прозрачные, чтобы не перекрывать стекло.
         Обложки с background-image не трогаем — их красит dc-rounded.
         Родная круглая кнопка .playControls__play исключена: её белый
         фон и чёрную иконку рисует сам SoundCloud, вмешательство
         оставляет кривую обводку. */
      html.dc-modern [data-dc-player] > *:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar] > *:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player] [class*="playControls__"]:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar] [class*="playControls__"]:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player] [class*="playbackSoundBadge"]:not(button),
      html.dc-modern [data-dc-playerbar] [class*="playbackSoundBadge"]:not(button),
      html.dc-modern footer div:not([style*="background-image"]),
      html.dc-modern footer section:not([style*="background-image"]),
      html.dc-modern [data-dc-player]:hover > *:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar]:hover > *:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player]:hover [class*="playControls__"]:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar]:hover [class*="playControls__"]:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player]:hover [class*="playbackSoundBadge"]:not(button),
      html.dc-modern [data-dc-playerbar]:hover [class*="playbackSoundBadge"]:not(button) {
        background-color: transparent !important;
        background-image: none !important;
      }
      html.dc-modern [data-dc-player] button:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player] a:not([class*="playControls__play"]),
      html.dc-modern [data-dc-player] [role="button"]:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar] button:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar] a:not([class*="playControls__play"]),
      html.dc-modern [data-dc-playerbar] [role="button"]:not([class*="playControls__play"]),
      html.dc-modern footer button,
      html.dc-modern footer a,
      html.dc-modern footer [role="button"] {
        background-color: transparent !important;
        background-image: none !important;
        box-shadow: none !important;
        border-color: transparent !important;
        transition: opacity var(--dc-fast) !important;
      }
      html.dc-modern [data-dc-player] button:not([class*="playControls__play"]):hover,
      html.dc-modern [data-dc-player] a:not([class*="playControls__play"]):hover,
      html.dc-modern [data-dc-player] [role="button"]:not([class*="playControls__play"]):hover,
      html.dc-modern [data-dc-playerbar] button:not([class*="playControls__play"]):hover,
      html.dc-modern [data-dc-playerbar] a:not([class*="playControls__play"]):hover,
      html.dc-modern [data-dc-playerbar] [role="button"]:not([class*="playControls__play"]):hover,
      html.dc-modern footer button:hover,
      html.dc-modern footer a:hover,
      html.dc-modern footer [role="button"]:hover {
        opacity: .82 !important;
      }

      /* Нативная шкала времени: позицию не трогаем, только цвет.
         Пройденная часть — акцент темы, остаток — приглушённый.
         Селекторы с [data-dc-playerbar] нужны, чтобы перебить
         обобщающую очистку фонов ниже по специфичности. */
      html.dc-modern [data-dc-player] .playbackTimeline__progressBackground,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressBackground,
      html.dc-modern footer .playbackTimeline__progressBackground {
        background-color: rgba(255,255,255,.16) !important;
        border-radius: 999px !important;
      }
      html.dc-modern [data-dc-player] .playbackTimeline__progressBar,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressBar,
      html.dc-modern footer .playbackTimeline__progressBar,
      html.dc-modern [data-dc-player] .playbackTimeline__progress,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progress,
      html.dc-modern footer .playbackTimeline__progress {
        background-color: var(--dc-accent) !important;
        border-radius: 999px !important;
      }
      html.dc-modern [data-dc-player] .playbackTimeline__progressHandle,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressHandle,
      html.dc-modern footer .playbackTimeline__progressHandle {
        background-color: var(--dc-accent) !important;
        border-color: var(--dc-accent) !important;
        box-shadow: none !important;
      }
      /* Ползунок громкости — в ту же гамму */
      html.dc-modern [data-dc-player] .volume__sliderRange,
      html.dc-modern [data-dc-playerbar] .volume__sliderRange,
      html.dc-modern footer .volume__sliderRange {
        background-color: rgba(255,255,255,.16) !important;
        border-radius: 999px !important;
      }
      html.dc-modern [data-dc-player] .volume__sliderProgress,
      html.dc-modern [data-dc-playerbar] .volume__sliderProgress,
      html.dc-modern footer .volume__sliderProgress {
        background-color: var(--dc-accent) !important;
        border-radius: 999px !important;
      }
      html.dc-modern [data-dc-player] .volume__sliderHandle,
      html.dc-modern [data-dc-playerbar] .volume__sliderHandle,
      html.dc-modern footer .volume__sliderHandle {
        background-color: var(--dc-accent) !important;
        border-color: var(--dc-accent) !important;
        box-shadow: none !important;
      }

      /* Акцентные кнопки — цвет текущей темы (монохром по умолчанию) */
      html.dc-theme .header__goUpsell,
      html.dc-theme .sc-button-cta,
      html.dc-theme .sc-button-primary {
        background: transparent !important;
        border: 1px solid var(--dc-accent-border) !important;
        color: var(--dc-accent) !important;
        box-shadow: none !important;
      }
      html.dc-theme .header__goUpsell:hover,
      html.dc-theme .sc-button-cta:hover,
      html.dc-theme .sc-button-primary:hover {
        background: var(--dc-accent-soft) !important;
        border-color: var(--dc-accent) !important;
      }
      html.dc-theme .header__goUpsell *,
      html.dc-theme .sc-button-cta *,
      html.dc-theme .sc-button-primary * {
        color: var(--dc-accent) !important;
        fill: var(--dc-accent) !important;
      }
      html.dc-theme .sc-button-play:not([class*="playControls__play"]),
      html.dc-theme .playButton {
        background-color: rgba(12,13,17,.55) !important;
        border: 1px solid var(--dc-accent-border) !important;
        box-shadow: 0 4px 18px rgba(0,0,0,.35) !important;
      }
      html.dc-theme .sc-button-play:not([class*="playControls__play"]):hover,
      html.dc-theme .playButton:hover {
        background-color: rgba(20,21,27,.7) !important;
        border-color: var(--dc-accent) !important;
      }
      /* Лайки не перекрашиваем: красное сердце — часть SoundCloud */

      /* noAds V9: жёсткое скрытие рекламы даже если network-правило пропустило */
      html.dc-noads [data-dc-ad],
      html.dc-noads [data-dc-promo] {
        display: none !important;
      }

      /* Скругление обложек: SoundCloud рисует каверы абсолютно-позиционированными
         слоями, которые overflow:hidden статичного предка НЕ обрезает — поэтому
         радиус ставится и на сам рисуемый узел, а маска чистит углы. */
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

      /* Lightweight animations: только transform/opacity */
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
        html.dc-modern [data-dc-playerbar] button,
        html.dc-modern footer button,
        html.dc-modern [data-dc-player] a,
        html.dc-modern [data-dc-playerbar] a,
        html.dc-modern footer a {
          animation: none !important;
          transition-duration: 1ms !important;
        }
      }
      @media (prefers-reduced-transparency: reduce) {
        html.dc-modern [data-dc-player],
        html.dc-modern [data-dc-playerbar],
        html.dc-modern footer,
        html.dc-modern [class*="playControls" i] {
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
      html.dc-compact [data-dc-player],
      html.dc-compact [data-dc-playerbar] { min-height: 46px !important; }

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

  // Родительская плита плеера (footer-обёртка): на ней тоже стекло.
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
      scope.querySelectorAll?.(selectors.promos).forEach(node => node.remove());
    } catch (_) {}
  }

  // Промо-треки в лентах: бейдж "Promoted"/"Sponsored" переживает
  // переименования классов — ищем по тексту коротких элементов.
  function removePromotedCards(scope = document) {
    if (!state.settings.adBlock) return;
    try {
      const badges = scope instanceof Element && scope.matches('span, em, strong, small')
        ? [scope]
        : Array.from(scope.querySelectorAll?.('span, em, strong, small') ?? []);
      for (const b of badges) {
        const t = (b.textContent || '').trim().toLowerCase();
        if (t !== 'promoted' && t !== 'sponsored' && t !== 'advertisement' && t !== 'реклама') continue;
        const card = b.closest?.('.trackItem, .soundBadge, .sound, .soundList__item, li, [class*="card" i]');
        if (card) card.remove();
        else b.remove();
      }
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
        if (a.hasAttribute('data-ad') ||
            src.includes('advert') || src.includes('/ads/') || src.includes('promotion') ||
            src.includes('preroll') || src.includes('doubleclick') || src.includes('adsrv')) {
          try { a.muted = true; a.currentTime = (a.duration || 0); a.pause(); } catch (_) {}
          a.remove();
        }
      }
    } catch (_) {}
  }

  function applyAccent() {
    root.classList.remove('dc-accent-amber', 'dc-accent-blue');
    const accent = state.settings.accent || 'mono';
    if (accent === 'amber') root.classList.add('dc-accent-amber');
    else if (accent === 'blue') root.classList.add('dc-accent-blue');
    // Системный акцент: приложение присылает точный hex macOS.
    if (accent === 'system' && typeof state.settings.accentHex === 'string' && state.settings.accentHex) {
      root.style.setProperty('--dc-accent', state.settings.accentHex);
      root.style.setProperty('--dc-accent-border', state.settings.accentHex);
    } else {
      root.style.removeProperty('--dc-accent');
      root.style.removeProperty('--dc-accent-border');
    }
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
    applyAccent();
  }

  // ── Мост в приложение ────────────────────────────────────────────
  // Тихая отправка: если хендлера нет (старая сборка, обычный браузер) — молча выходим.
  function post(type, payload) {
    try {
      window.webkit?.messageHandlers?.diecloudeBridge?.postMessage({ type: type, ...payload });
    } catch (_) {}
  }

  // ── Now Playing: читаем состояние из <audio> и бейджа плеера ──────
  const nowPlaying = { cleanup: [], lastMetaKey: '', lastPost: 0, missingReported: false, missingCheckPending: false, missingTimer: 0 };

  function audioElements(scope = document) {
    if (scope instanceof Element && scope.tagName === 'AUDIO') return [scope];
    return Array.from(scope.querySelectorAll?.('audio') ?? []);
  }

  function postState(a) {
    const now = performance.now();
    if (now - nowPlaying.lastPost < 900 && !a.paused) return; // троттлинг ~1с
    nowPlaying.lastPost = now;
    post('state', {
      playing: !a.paused && !a.ended,
      position: a.currentTime || 0,
      duration: isFinite(a.duration) ? a.duration : 0
    });
  }

  function readMeta() {
    const titleEl = document.querySelector('.playbackSoundBadge__titleLink, .playbackSoundBadge__title');
    const artistEl = document.querySelector('.playbackSoundBadge__artist, .playbackSoundBadge__lightLink');
    const artEl = document.querySelector('.playbackSoundBadge__avatar .image__full, .playbackSoundBadge__avatar .sc-artwork, .playbackSoundBadge__avatar');
    let artwork = '';
    if (artEl) {
      const styleBg = (artEl.getAttribute('style') || '').match(/url\(["']?([^"')]+)/i);
      const img = artEl.matches('img') ? artEl : artEl.querySelector('img');
      artwork = styleBg?.[1] || img?.src || '';
      if (artwork) artwork = artwork.replace(/t\d+x\d+/, 't500x500');
    }
    const title = (titleEl?.getAttribute('title') || titleEl?.textContent || '').trim();
    const artist = (artistEl?.textContent || artistEl?.getAttribute('title') || '').trim();
    return { title, artist, artwork };
  }

  function maybePostMeta() {
    const meta = readMeta();
    const key = meta.title + '|' + meta.artist + '|' + meta.artwork;
    if (!meta.title || key === nowPlaying.lastMetaKey) return;
    nowPlaying.lastMetaKey = key;
    post('meta', meta);
  }

  function hookAudio(scope = document) {
    for (const a of audioElements(scope)) {
      if (a.dataset.dcHooked) continue;
      a.dataset.dcHooked = '1';
      const onPlay = () => { postState(a); maybePostMeta(); };
      const onPause = () => postState(a);
      const onTime = () => postState(a);
      const onLoaded = () => { postState(a); maybePostMeta(); };
      const onEnded = () => postState(a);
      a.addEventListener('play', onPlay);
      a.addEventListener('pause', onPause);
      a.addEventListener('timeupdate', onTime);
      a.addEventListener('loadedmetadata', onLoaded);
      a.addEventListener('ended', onEnded);
      nowPlaying.cleanup.push(() => {
        a.removeEventListener('play', onPlay);
        a.removeEventListener('pause', onPause);
        a.removeEventListener('timeupdate', onTime);
        a.removeEventListener('loadedmetadata', onLoaded);
        a.removeEventListener('ended', onEnded);
      });
      postState(a);
      maybePostMeta();
    }
  }

  // ── Диагностика: панель плеера не найдена ─────────────────────────
  // Не спешим с негативом: React-панель может отрисоваться позже,
  // поэтому «не найдено» отправляется только если через 5с всё ещё пусто.
  function reportPlayerPresence() {
    const found = Boolean(
      document.querySelector('[data-dc-playerbar], [data-dc-player], .playControls, [class*="playControls" i]')
    );
    if (found) {
      if (nowPlaying.missingReported) {
        nowPlaying.missingReported = false;
        post('playerFound', {});
      }
      return;
    }
    if (nowPlaying.missingReported || nowPlaying.missingCheckPending) return;
    nowPlaying.missingCheckPending = true;
    nowPlaying.missingTimer = setTimeout(() => {
      nowPlaying.missingCheckPending = false;
      const stillMissing = !document.querySelector('[data-dc-playerbar], [data-dc-player], .playControls, [class*="playControls" i]');
      if (stillMissing && !nowPlaying.missingReported) {
        nowPlaying.missingReported = true;
        post('playerMissing', {});
      }
    }, 5000);
  }

  // Структурный поиск планки плеера: классы SoundCloud периодически
  // переименовываются, поэтому ищем широкую невысокую полосу у нижнего
  // края вьюпорта (fixed она или sticky — не важно, новый DOM бывает absolute).
  function ensurePlayerBar() {
    try {
      const marked = document.querySelector('[data-dc-playerbar]');
      if (marked && marked.isConnected) return;
      let el = document.querySelector(selectors.player);
      if (!el) {
        const candidates = document.querySelectorAll('audio, button[aria-label], [role="button"][aria-label]');
        for (const node of candidates) {
          const label = node.tagName === 'AUDIO' ? '' : (node.getAttribute('aria-label') || '').toLowerCase();
          if (node.tagName !== 'AUDIO' && !/play|pause|next|previous|воспроизв|пауз|следующ|предыдущ/.test(label)) continue;
          let p = node.parentElement;
          for (let i = 0; i < 10 && p && p !== document.body; i++, p = p.parentElement) {
            let r;
            try { r = p.getBoundingClientRect(); } catch (_) { continue; }
            if (r.bottom >= window.innerHeight - 10 && r.width > window.innerWidth * 0.5 &&
                r.height < window.innerHeight * 0.4 && r.height > 28) {
              el = p;
              break;
            }
          }
          if (el) break;
        }
      }
      if (el) {
        el.setAttribute('data-dc-player', '');
        const bar = (el.closest && el.closest(selectors.playerBar)) || el;
        bar.setAttribute('data-dc-playerbar', '');
      }
    } catch (_) {}
  }

  function refresh(scope = document) {
    if (scope === document) ensurePlayerBar();
    tag(scope);
    removeAds(scope);
    removePromotedCards(scope);
    skipAudioAds(scope);
    hookAudio(scope);
    applyClasses();
    if (scope === document) { maybePostMeta(); reportPlayerPresence(); }
  }

  function schedule(nodes) {
    // Дебаунс 180мс, обрабатываем только добавленные узлы, не весь document
    if (state.timer) return;
    state.timer = setTimeout(() => {
      state.timer = 0;
      try {
        for (const n of nodes) {
          if (n instanceof Element) {
            tag(n);
            removeAds(n);
            removePromotedCards(n);
            skipAudioAds(n);
            hookAudio(n);
          }
        }
      } catch (_) {}
      ensurePlayerBar();
      applyClasses();
      maybePostMeta();
    }, 180);
  }

  addStyle();
  state.set = (key, value) => {
    state.settings[key] = value;
    refresh(document);
  };
  state.setAll = values => {
    Object.assign(state.settings, values || {});
    refresh(document);
  };
  state.refresh = () => refresh(document);
  // Перемотка из системного плеера / медиа-клавиш
  state.seek = seconds => {
    const a = document.querySelector('audio');
    if (a && isFinite(seconds)) {
      try { a.currentTime = Math.max(0, Math.min(seconds, a.duration || seconds)); postState(a); } catch (_) {}
    }
  };
  state.destroy = () => {
    state.observer?.disconnect();
    if (state.timer) clearTimeout(state.timer);
    if (state.frame) cancelAnimationFrame(state.frame);
    if (nowPlaying.missingTimer) clearTimeout(nowPlaying.missingTimer);
    nowPlaying.cleanup.forEach(fn => fn());
    nowPlaying.cleanup = [];
    document.getElementById(STYLE_ID)?.remove();
    try {
      document.querySelectorAll?.('[data-dc-playerbar]').forEach(node => node.removeAttribute('data-dc-playerbar'));
    } catch (_) {}
    root.style.removeProperty('--dc-accent');
    root.style.removeProperty('--dc-accent-border');
    root.classList.remove('dc-modern','dc-theme','dc-rounded','dc-hover','dc-compact','dc-focus','dc-noads','dc-accent-amber','dc-accent-blue');
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
