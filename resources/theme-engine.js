(() => {
  'use strict';

  // DieCloude 4.0.2 — theme engine
  // Архитектура прежняя (теги + MutationObserver + один <style>),
  // обновлён матовый плеер и монохромные акценты.

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine';
  const state = { settings: { ...initial }, observer: null, timer: 0, frame: 0 };

  const selectors = {
    header: '.header, header[role="banner"]',
    // Только сама планка .playControls — внутренние .playControls__*
    // перекрашивать не нужно: за них отвечает родительская плита.
    player: '.playControls, [data-testid="play-controls"]',
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

      /* Мягкая подсветка строк трек-листа при наведении */
      html.dc-modern .trackList__item:hover,
      html.dc-modern .trackListItem:hover,
      html.dc-modern .trackList__item:focus-within {
        background-color: rgba(255,255,255,.035) !important;
      }

      /* ─────────────────────────────────────────────────────────────
         МАТОВЫЙ ПЛЕЕР — два слоя настоящего стекла.

         Внешняя плита ([data-dc-playerbar], footer) — матовая основа:
         полупрозрачная тёмная заливка + сильный backdrop-blur и лёгкая
         перенасыщенность под ним, тонкий верхний хайлайт и хайрлайн.
         Внутренняя планка ([data-dc-player] без playerbar) — едва
         заметная вуаль, приглушающая родной фон SoundCloud, чтобы blur
         оставался видимым. Покой и hover идентичны — эффект не
         «слетает» при наведении.
         ───────────────────────────────────────────────────────────── */
      html.dc-modern [data-dc-playerbar],
      html.dc-modern footer,
      html.dc-modern :is([data-dc-playerbar], footer):is(:hover, :focus-within, :active) {
        background-color: rgba(24,25,32,.62) !important;
        background-image:
          linear-gradient(180deg, rgba(255,255,255,.075), rgba(255,255,255,.012) 38%, rgba(255,255,255,0) 62%) !important;
        -webkit-backdrop-filter: blur(28px) saturate(165%) !important;
        backdrop-filter: blur(28px) saturate(165%) !important;
        border-top: 1px solid rgba(255,255,255,.14) !important;
        box-shadow: 0 -12px 40px rgba(0,0,0,.36), inset 0 1px 0 rgba(255,255,255,.05) !important;
        isolation: isolate !important;
      }

      /* Внутренняя планка плеера: вуаль без собственного blur,
         чтобы стекло не складывалось дважды. Если парент-плиты нет
         (структурный поиск пометил сам бар) — атрибут playerbar на нём,
         и правило выше красит его как основу. */
      html.dc-modern [data-dc-player]:not([data-dc-playerbar]) {
        background-color: rgba(16,17,23,.34) !important;
        background-image: none !important;
        -webkit-backdrop-filter: none !important;
        backdrop-filter: none !important;
        border-top-color: transparent !important;
        box-shadow: none !important;
      }

      /* Внутренности планки — прозрачные, чтобы не перекрывать стекло.
         Обложки с background-image не трогаем — их красит dc-rounded. */
      html.dc-modern :is([data-dc-playerbar], footer):is(> *, :hover > *) div:not([style*="background-image"]),
      html.dc-modern :is([data-dc-playerbar], footer):is(> *, :hover > *) section:not([style*="background-image"]),
      html.dc-modern :is([data-dc-player], [data-dc-playerbar]):is([class*="playControls__"], :hover [class*="playControls__"]),
      html.dc-modern :is([data-dc-player], [data-dc-playerbar]) :is([class*="playControls__"], [class*="playbackSoundBadge"], :hover [class*="playControls__"]) {
        background-color: transparent !important;
        background-image: none !important;
      }
      html.dc-modern :is([data-dc-playerbar], footer, [data-dc-player]) :is(button, a, [role="button"]),
      html.dc-modern :is([data-dc-playerbar], footer, [data-dc-player]) :is(button, a, [role="button"]):hover {
        background-color: transparent !important;
        background-image: none !important;
        box-shadow: none !important;
        border-color: transparent !important;
        transition: opacity var(--dc-fast) !important;
      }
      html.dc-modern :is([data-dc-playerbar], footer, [data-dc-player]) :is(button, a, [role="button"]):hover {
        opacity: .82 !important;
      }

      /* Нативная шкала времени: позицию не трогаем, только цвет */
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
      /* Ползунок громкости — в ту же белую гамму */
      html.dc-modern .volume__sliderRange,
      html.dc-modern .volume[data-level] .sliderContainer {
        background-color: rgba(255,255,255,.16) !important;
        border-radius: 999px !important;
      }
      html.dc-modern .volume__sliderProgress {
        background-color: #fff !important;
        border-radius: 999px !important;
      }
      html.dc-modern .volume__sliderHandle {
        background-color: #fff !important;
        border-color: #fff !important;
        box-shadow: none !important;
      }

      /* Белый фирменный акцент: CTA-кнопки и круглые play-кнопки
         на обложках становятся монохромными. */
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
      html.dc-theme :is(.sc-button-play, .playButton) {
        background-color: rgba(12,13,17,.55) !important;
        border: 1px solid rgba(255,255,255,.22) !important;
        box-shadow: 0 4px 18px rgba(0,0,0,.35) !important;
      }
      html.dc-theme :is(.sc-button-play, .playButton):hover {
        background-color: rgba(20,21,27,.7) !important;
        border-color: rgba(255,255,255,.38) !important;
      }

      /* noAds V9: жёсткое скрытие рекламы даже если network-правило пропустило */
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
      html.dc-rounded :is([data-dc-playerbar], footer, [data-dc-player]) [data-dc-artwork],
      html.dc-rounded :is([data-dc-playerbar], footer, [data-dc-player]) :is([data-dc-artwork] img, .image__full, .sc-artwork) {
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
        html.dc-modern :is([data-dc-playerbar], footer, [data-dc-player]) :is(button, a, [role="button"]) {
          animation: none !important;
          transition-duration: 1ms !important;
        }
      }
      @media (prefers-reduced-transparency: reduce) {
        html.dc-modern :is([data-dc-playerbar], footer) {
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
      html.dc-compact :is([data-dc-playerbar], [data-dc-player]) { min-height: 46px !important; }

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

  // Родительская плита плеера (footer-обёртка): на ней держится матовое
  // стекло, поэтому помечаем и её — иначе blur перекрывается родным фоном.
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

  // Структурный поиск планки плеера: классы SoundCloud периодически
  // переименовываются, поэтому ищем через <audio> -> fixed/sticky предок
  // у нижнего края вьюпорта. Быстрый путь — уже помеченный узел жив.
  function ensurePlayerBar() {
    try {
      const marked = document.querySelector('[data-dc-playerbar]');
      if (marked && marked.isConnected) return;
      let el = document.querySelector(selectors.player);
      if (!el) {
        const audios = document.querySelectorAll('audio');
        for (const a of audios) {
          let p = a.parentElement;
          for (let i = 0; i < 8 && p && p !== document.body; i++, p = p.parentElement) {
            let r, cs;
            try {
              r = p.getBoundingClientRect();
              cs = getComputedStyle(p);
            } catch (_) { continue; }
            if ((cs.position === 'fixed' || cs.position === 'sticky') &&
                r.bottom >= window.innerHeight - 8 && r.width > window.innerWidth * 0.5) {
              el = p;
              break;
            }
          }
          if (el) break;
        }
      }
      if (!el) {
        // SoundCloud может играть без <audio> в DOM: ищем кнопку play/pause
        // и поднимаемся к широкой планке у нижнего края.
        const btns = document.querySelectorAll('button[aria-label], [role="button"][aria-label]');
        for (const b of btns) {
          const label = (b.getAttribute('aria-label') || '').toLowerCase();
          if (!/play|pause|воспроизв|пауз/.test(label)) continue;
          let p = b.parentElement;
          for (let i = 0; i < 10 && p && p !== document.body; i++, p = p.parentElement) {
            let r;
            try { r = p.getBoundingClientRect(); } catch (_) { continue; }
            if (r.bottom >= window.innerHeight - 8 && r.width > window.innerWidth * 0.5 &&
                r.height < window.innerHeight * 0.4) {
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
    applyClasses();
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
          }
        }
      } catch (_) {}
      ensurePlayerBar();
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
