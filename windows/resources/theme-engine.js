(() => {
  'use strict';

  // DieCloude 4.5.0 — theme engine
  // Тегирование + MutationObserver + один <style> + перехват Audio + громкость + горячие клавиши.

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine';
  const VOLUME_KEY = 'dc_saved_volume';
  const MUTED_KEY = 'dc_saved_muted';

  function readStoredNumber(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      if (raw !== null) {
        const val = parseFloat(raw);
        if (Number.isFinite(val)) return Math.max(0, Math.min(1, val));
      }
    } catch (_) {}
    return fallback;
  }

  function readStoredBool(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      if (raw === 'true') return true;
      if (raw === 'false') return false;
    } catch (_) {}
    return fallback;
  }

  const state = {
    settings: {
      ...initial,
      volume: typeof initial.volume === 'number' ? initial.volume : readStoredNumber(VOLUME_KEY, 0.8),
      isMuted: typeof initial.isMuted === 'boolean' ? initial.isMuted : readStoredBool(MUTED_KEY, false)
    },
    observer: null,
    timer: 0,
    frame: 0,
    pendingNodes: []
  };

  function persistVolumeLocal(volume, muted) {
    try {
      localStorage.setItem(VOLUME_KEY, String(volume));
      localStorage.setItem(MUTED_KEY, String(Boolean(muted)));
    } catch (_) {}
  }

  const selectors = {
    header: '.header, header[role="banner"]',
    // ВАЖНО: Никаких [class*="playControls"], чтобы не тегировать дочерние элементы .playControls__*!
    player: 'section.playControls, div.playControls:not([class*="playControls__"]), .playControls:not(.playControls *), [data-testid="play-controls"]',
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
        --dc-bg: #08090c;
        --dc-surface: #0e1015;
        --dc-surface-2: #14161f;
        --dc-text: #f5f5f7;
        --dc-muted: #8e919d;
        --dc-line: rgba(255,255,255,.07);
        --dc-line-strong: rgba(255,255,255,.14);
        --dc-radius: 14px;
        --dc-fast: 160ms cubic-bezier(.2,.8,.2,1);
        /* Акцент темы. По умолчанию — белый монохром; темы ниже его переопределяют. */
        --dc-accent: #ffffff;
        --dc-accent-soft: rgba(255,255,255,.09);
        --dc-accent-border: rgba(255,255,255,.32);
        --dc-glass: rgba(255,255,255,.04);
      }
      html.dc-accent-amber {
        --dc-accent: #e8a33d;
        --dc-accent-soft: rgba(232,163,61,.14);
        --dc-accent-border: rgba(232,163,61,.45);
      }
      html.dc-accent-blue {
        --dc-accent: #4f8cff;
        --dc-accent-soft: rgba(79,140,255,.16);
        --dc-accent-border: rgba(79,140,255,.5);
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
      /* Отступ снизу для страниц SoundCloud (только внутри #content / main, НЕ трогая шапку и плеер!) */
      html.dc-modern #content,
      html.dc-modern main,
      html.dc-modern #content .l-container,
      html.dc-modern #content .l-content,
      html.dc-modern .userMain,
      html.dc-modern div.collection,
      html.dc-modern .collection,
      html.dc-modern .collection__section,
      html.dc-modern .collection__likesSection,
      html.dc-modern .collection__userStream,
      html.dc-modern .lazyLoadingList,
      html.dc-modern .stream {
        padding-bottom: 120px !important;
        box-sizing: border-box !important;
      }

      /* Физический нескладывающийся распорный элемент (spacer) в конце любого Grid и Flex списка треков */
      html.dc-modern .lazyLoadingList__list::after,
      html.dc-modern .badgeList::after,
      html.dc-modern .soundBadgeList::after,
      html.dc-modern .stream__list::after,
      html.dc-modern .searchList::after,
      html.dc-modern .collection__likesSection::after,
      html.dc-modern .collection__userStream::after,
      html.dc-modern .userStream__list::after,
      html.dc-modern .trackList__list::after {
        content: "" !important;
        display: block !important;
        width: 100% !important;
        height: 120px !important;
        min-height: 120px !important;
        flex: 0 0 100% !important;
        flex-basis: 100% !important;
        grid-column: 1 / -1 !important;
        pointer-events: none !important;
        background: transparent !important;
      }
      /* Гарантированное скрытие вспомогательного текста скринридеров */
      html.dc-modern .sc-visuallyhidden,
      html.dc-modern [class*="visuallyhidden" i] {
        position: absolute !important;
        width: 1px !important;
        height: 1px !important;
        padding: 0 !important;
        margin: -1px !important;
        overflow: hidden !important;
        clip: rect(0, 0, 0, 0) !important;
        white-space: nowrap !important;
        border: 0 !important;
      }

      /* Верхняя панель SoundCloud — тёмная матовая шапка строго 46px */
      html.dc-modern [data-dc-header],
      html.dc-modern header[role="banner"],
      html.dc-modern .header {
        position: fixed !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        height: 46px !important;
        max-height: 46px !important;
        overflow: hidden !important;
        background-color: rgba(14, 16, 21, 0.95) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        backdrop-filter: blur(20px) !important;
        border-bottom: 1px solid var(--dc-line) !important;
        box-shadow: 0 4px 16px rgba(0,0,0,.3) !important;
        z-index: 9999 !important;
        box-sizing: border-box !important;
      }

      /* Защита шапки: header__inner не должен растягиваться и свисать черной полосой */
      html.dc-modern .header__inner,
      html.dc-modern .header .l-container,
      html.dc-modern header .l-container,
      html.dc-modern [data-dc-header] .l-container {
        height: 46px !important;
        max-height: 46px !important;
        padding-top: 0 !important;
        padding-bottom: 0 !important;
        margin-top: 0 !important;
        margin-bottom: 0 !important;
        background: transparent !important;
        background-color: transparent !important;
        box-sizing: border-box !important;
        overflow: visible !important;
      }

      /* Контейнер страницы: фиксированные 46px сверху под шапку */
      html.dc-modern .l-container.l-content,
      html.dc-modern #app > .l-container {
        padding-top: 46px !important;
        margin-top: 0 !important;
        box-sizing: border-box !important;
      }

      /* Внутри #content верхний отступ НЕ задваиваем */
      html.dc-modern #content {
        padding-top: 0 !important;
        margin-top: 0 !important;
        box-sizing: border-box !important;
      }

      /* Навигация библиотеки (Overview, Likes, Playlists...) — ровно под шапкой, без лишних пустот */
      html.dc-modern .l-nav,
      html.dc-modern .l-collection > .l-nav {
        margin-top: 6px !important;
        margin-bottom: 8px !important;
        padding-top: 0 !important;
        padding-bottom: 0 !important;
      }

      html.dc-modern .collectionNav,
      html.dc-modern .collection__nav,
      html.dc-modern .g-tabs {
        display: block !important;
        height: auto !important;
        min-height: 40px !important;
        margin-top: 0 !important;
        margin-bottom: 8px !important;
        padding-top: 0 !important;
        padding-bottom: 0 !important;
        overflow: visible !important;
        border-bottom: 1px solid var(--dc-line) !important;
      }

      html.dc-modern .g-tabs__item,
      html.dc-modern .collectionNav__item {
        display: inline-block !important;
        margin-right: 20px !important;
        vertical-align: middle !important;
      }

      html.dc-modern .g-tabs__link,
      html.dc-modern .g-tabs-link {
        display: inline-block !important;
        padding: 6px 2px 10px 2px !important;
        font-size: 14px !important;
        font-weight: 600 !important;
        color: var(--dc-muted) !important;
        text-decoration: none !important;
        border-bottom: 2px solid transparent !important;
        transition: color var(--dc-fast), border-color var(--dc-fast) !important;
      }

      html.dc-modern .g-tabs__link.active,
      html.dc-modern .g-tabs__link:hover,
      html.dc-modern .g-tabs-link.active,
      html.dc-modern .g-tabs-link:hover {
        color: var(--dc-text) !important;
        border-bottom-color: var(--dc-accent) !important;
      }

      /* Панель управления и фильтрации треков в библиотеке (collectionSection__top) */
      html.dc-modern .collectionSection__top {
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        height: auto !important;
        min-height: 36px !important;
        margin-top: 4px !important;
        margin-bottom: 8px !important;
        padding: 0 4px !important;
        background: transparent !important;
        border: none !important;
        box-sizing: border-box !important;
        visibility: visible !important;
        opacity: 1 !important;
      }

      /* Подзаголовок страницы («Hear the tracks you’ve liked:») */
      html.dc-modern .collectionSection__subHeading {
        font-size: 14px !important;
        font-weight: 600 !important;
        color: var(--dc-muted) !important;
        margin: 0 !important;
        padding: 0 !important;
        line-height: 1.2 !important;
      }

      html.dc-modern .collectionSection__flexFill {
        flex: 1 1 auto !important;
      }

      /* Переключатель вида (Сетка / Список) */
      html.dc-modern .listDisplayToggle {
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
      }

      html.dc-modern .listDisplayToggle__title {
        font-size: 13px !important;
        color: var(--dc-muted) !important;
        margin-right: 6px !important;
      }

      html.dc-modern .listDisplayToggle__options {
        display: inline-flex !important;
        align-items: center !important;
        gap: 4px !important;
        margin: 0 !important;
        padding: 0 !important;
        list-style: none !important;
      }

      html.dc-modern .listDisplayToggle button,
      html.dc-modern .listDisplayToggle .sc-button {
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid var(--dc-line) !important;
        border-radius: 8px !important;
        color: var(--dc-muted) !important;
        padding: 4px 6px !important;
        height: 28px !important;
        width: 28px !important;
        box-sizing: border-box !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        transition: background-color var(--dc-fast), color var(--dc-fast), border-color var(--dc-fast) !important;
      }

      html.dc-modern .listDisplayToggle button:hover,
      html.dc-modern .listDisplayToggle button.sc-button-selected {
        background: rgba(255, 255, 255, 0.12) !important;
        color: var(--dc-text) !important;
        border-color: var(--dc-line-strong) !important;
      }

      /* Фильтр / Поиск в коллекции */
      html.dc-modern .collectionSection__filters {
        display: inline-flex !important;
        align-items: center !important;
        margin-left: 12px !important;
      }

      html.dc-modern .collectionSection__filterText,
      html.dc-modern .collectionSection__filterText .textfield {
        margin: 0 !important;
        padding: 0 !important;
      }

      html.dc-modern .collectionSection__filterText .textfield__inputWrapper {
        position: relative !important;
        display: inline-flex !important;
        align-items: center !important;
      }

      html.dc-modern .collectionSection__filterText input.textfield__input,
      html.dc-modern .collectionSection__filterText input[type="text"],
      html.dc-modern .collectionSection__filterText input[type="search"] {
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid var(--dc-line) !important;
        border-radius: 18px !important;
        color: var(--dc-text) !important;
        font-size: 13px !important;
        padding: 4px 28px 4px 12px !important;
        height: 30px !important;
        min-width: 180px !important;
        box-sizing: border-box !important;
        transition: border-color var(--dc-fast), background-color var(--dc-fast), box-shadow var(--dc-fast) !important;
      }

      html.dc-modern .collectionSection__filterText input.textfield__input:focus,
      html.dc-modern .collectionSection__filterText input[type="text"]:focus,
      html.dc-modern .collectionSection__filterText input[type="search"]:focus {
        background: rgba(255, 255, 255, 0.09) !important;
        border-color: var(--dc-accent-border) !important;
        box-shadow: 0 0 0 3px var(--dc-accent-soft) !important;
        color: var(--dc-text) !important;
        outline: none !important;
      }

      html.dc-modern .collectionSection__filterText .textfield__clearContainer {
        position: absolute !important;
        right: 8px !important;
        top: 50% !important;
        transform: translateY(-50%) !important;
        cursor: pointer !important;
        color: var(--dc-muted) !important;
      }

      html.dc-modern .collectionSection__filterText .textfield__clearContainer:hover {
        color: var(--dc-text) !important;
      }

      /* Сброс лишних служебных заголовков и пустот */
      html.dc-modern .l-collection-top,
      html.dc-modern .l-top:empty {
        display: none !important;
        height: 0 !important;
        min-height: 0 !important;
        padding: 0 !important;
        margin: 0 !important;
        border: none !important;
      }

      html.dc-modern .collectionSection__list,
      html.dc-modern .collection .lazyLoadingList,
      html.dc-modern .collection .badgeList {
        padding-top: 0 !important;
        margin-top: 8px !important;
      }

      html.dc-modern .headerSearch__input,
      html.dc-modern input[type="search"],
      html.dc-modern input[type="text"] {
        background: rgba(255,255,255,.05) !important;
        border: 1px solid var(--dc-line) !important;
        border-radius: 20px !important;
        color: var(--dc-text) !important;
        font-size: 13px !important;
        padding: 6px 14px !important;
        box-shadow: none !important;
        transition: border-color var(--dc-fast), background-color var(--dc-fast) !important;
      }
      html.dc-modern .headerSearch__input:focus,
      html.dc-modern input[type="search"]:focus,
      html.dc-modern input[type="text"]:focus {
        border-color: var(--dc-accent-border) !important;
        background: rgba(255,255,255,.09) !important;
        box-shadow: 0 0 0 3px var(--dc-accent-soft) !important;
      }

      /* Навигация в шапке */
      html.dc-modern .header__navMenu a,
      html.dc-modern .header__link {
        color: var(--dc-muted) !important;
        font-weight: 500 !important;
        transition: color var(--dc-fast) !important;
      }
      html.dc-modern .header__navMenu a:hover,
      html.dc-modern .header__link:hover {
        color: var(--dc-text) !important;
      }
      html.dc-modern .header__navMenu a.selected {
        color: var(--dc-text) !important;
        border-bottom: 2px solid var(--dc-accent) !important;
      }

      html.dc-modern .sc-text-light,
      html.dc-modern .sc-link-light,
      html.dc-modern .soundTitle__username,
      html.dc-modern .trackItem__username,
      html.dc-modern .playbackSoundBadge__lightLink {
        color: var(--dc-muted) !important;
      }

      /* Мягкая подсветка строк трек-листа при наведении */
      html.dc-modern .trackList__item,
      html.dc-modern .trackListItem {
        border-radius: 8px !important;
        transition: background-color var(--dc-fast) !important;
      }
      html.dc-modern .trackList__item:hover,
      html.dc-modern .trackListItem:hover,
      html.dc-modern .trackList__item:focus-within {
        background-color: rgba(255,255,255,.04) !important;
      }

      /* Карточки с эффектом парения и мягкой тенью */
      html.dc-modern .sound,
      html.dc-modern .soundBadge,
      html.dc-modern .searchItem {
        border-radius: var(--dc-radius) !important;
        transition: transform var(--dc-fast), box-shadow var(--dc-fast), background-color var(--dc-fast) !important;
      }
      html.dc-modern .sound:hover,
      html.dc-modern .soundBadge:hover,
      html.dc-modern .searchItem:hover {
        background-color: rgba(255,255,255,.03) !important;
        transform: translateY(-2px) !important;
        box-shadow: 0 10px 28px rgba(0,0,0,.45) !important;
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

      /* Вторичные кнопки (не трогаем play/pause и кнопки плеера) */
      html.dc-modern .sc-button:not(.sc-button-cta):not(.sc-button-primary):not([class*="playControls"]):not(.sc-button-play):not(.sc-button-pause):not(.playButton):not([class*="playButton" i]):not([class*="image__button" i]) {
        background: var(--dc-surface-2) !important;
        border: 1px solid var(--dc-line) !important;
        color: var(--dc-text) !important;
        border-radius: 8px !important;
        transition: all var(--dc-fast) !important;
      }
      html.dc-modern .sc-button:not(.sc-button-cta):not(.sc-button-primary):not([class*="playControls"]):not(.sc-button-play):not(.sc-button-pause):not(.playButton):not([class*="playButton" i]):not([class*="image__button" i]):hover {
        background: rgba(255,255,255,.06) !important;
        border-color: var(--dc-line-strong) !important;
      }

      /* Вкладки профиля и навигации */
      html.dc-modern .g-tabs__link,
      html.dc-modern .g-tabs-link,
      html.dc-modern [class*="profileTab"] {
        color: var(--dc-muted) !important;
        border-bottom-color: transparent !important;
        transition: color var(--dc-fast), border-color var(--dc-fast) !important;
      }
      html.dc-modern .g-tabs__link.active,
      html.dc-modern .g-tabs__link:hover,
      html.dc-modern .g-tabs-link.active,
      html.dc-modern .g-tabs-link:hover,
      html.dc-modern [class*="profileTab"].active,
      html.dc-modern [class*="profileTab"]:hover {
        color: var(--dc-text) !important;
        border-bottom-color: var(--dc-accent) !important;
      }

      /* Подсветка играющего трека в списках */
      html.dc-modern .trackItem.playing,
      html.dc-modern .trackList__item.playing,
      html.dc-modern .soundList__item.playing {
        background: linear-gradient(90deg, var(--dc-accent-soft), transparent 70%) !important;
        border-left: 2px solid var(--dc-accent) !important;
      }

      /* Шапка профиля */
      html.dc-modern .profileHeader,
      html.dc-modern [class*="profileHeader"] {
        background: linear-gradient(180deg, var(--dc-surface-2), var(--dc-bg)) !important;
        border-bottom: 1px solid var(--dc-line) !important;
      }

      html.dc-modern .infoStats__value,
      html.dc-modern [class*="infoStats"] {
        color: var(--dc-text) !important;
      }

      html.dc-modern a:not(.sc-button):not([class*="playControls"]) {
        color: var(--dc-muted) !important;
        transition: color var(--dc-fast) !important;
      }
      html.dc-modern a:not(.sc-button):not([class*="playControls"]):hover {
        color: var(--dc-text) !important;
      }
      html.dc-modern .soundTitle__title,
      html.dc-modern .trackItem__trackTitle {
        color: var(--dc-text) !important;
      }

      /* Вейвформа */
      html.dc-modern .waveform,
      html.dc-modern [class*="waveform" i] {
        opacity: .85;
        filter: saturate(0) brightness(1.3);
      }
      html.dc-modern .waveform:hover,
      html.dc-modern [class*="waveform" i]:hover {
        opacity: 1;
        filter: saturate(.5) brightness(1.4);
      }

      /* ─────────────────────────────────────────────────────────────
         МАТОВАЯ ПАНЕЛЬ ПЛЕЕРА (ТОЛЬКО корневой контейнер .playControls)
         Никаких [class*="playControls"] — дочерние .playControls__*
         не должны получать position: fixed и width: 100%!
         ───────────────────────────────────────────────────────────── */
      html.dc-modern section.playControls,
      html.dc-modern div.playControls:not([class*="playControls__"]),
      html.dc-modern .playControls:not(.playControls *),
      html.dc-modern [data-dc-player],
      html.dc-modern [data-dc-playerbar],
      html.dc-modern [data-testid="play-controls"],
      html.dc-modern section.playControls:hover,
      html.dc-modern div.playControls:not([class*="playControls__"]):hover,
      html.dc-modern .playControls:not(.playControls *):hover,
      html.dc-modern [data-dc-player]:hover,
      html.dc-modern [data-dc-playerbar]:hover {
        position: fixed !important;
        bottom: 0 !important;
        left: 0 !important;
        right: 0 !important;
        width: 100vw !important;
        min-height: 56px !important;
        height: 56px !important;
        background-color: #111318 !important;
        background: #111318 !important;
        background-image: none !important;
        border-top: 1px solid rgba(255, 255, 255, 0.09) !important;
        box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.85) !important;
        opacity: 1 !important;
        z-index: 99990 !important;
        isolation: isolate !important;
      }

      /* Дополнительная матовая заглушка под плеером от субпиксельных зазоров внизу окна */
      html.dc-modern .playControls::after {
        content: "" !important;
        position: absolute !important;
        left: 0 !important;
        right: 0 !important;
        bottom: -15px !important;
        height: 20px !important;
        background-color: #111318 !important;
        background: #111318 !important;
        z-index: -1 !important;
        pointer-events: none !important;
      }

      html.dc-modern .playControls__inner,
      html.dc-modern .playControls__bg,
      html.dc-modern .playControls__wrapper {
        background-color: #111318 !important;
        background: #111318 !important;
        background-image: none !important;
        border-top: none !important;
        opacity: 1 !important;
      }

      html.dc-modern .playControls > .playControls__bg,
      html.dc-modern .playControls .playControls__bg {
        position: absolute !important;
        inset: 0 !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        bottom: -15px !important;
        width: 100% !important;
        height: calc(100% + 15px) !important;
        background-color: #111318 !important;
        background: #111318 !important;
        opacity: 1 !important;
        z-index: 0 !important;
        pointer-events: none !important;
      }

      html.dc-modern .playControls__wrapper {
        position: relative !important;
        z-index: 1 !important;
        height: 100% !important;
        max-width: 1320px !important;
        margin: 0 auto !important;
        padding: 0 16px !important;
        box-sizing: border-box !important;
      }

      html.dc-modern .playControls__elements {
        display: flex !important;
        align-items: center !important;
        height: 100% !important;
        background: transparent !important;
      }

      html.dc-modern .playControls__buttons {
        display: flex !important;
        align-items: center !important;
        gap: 8px !important;
      }

      /* Прозрачные обёртки внутренних элементов */
      html.dc-modern .playControls__timeline,
      html.dc-modern .playbackSoundBadge,
      html.dc-modern .playbackSoundBadge__titleContextContainer,
      html.dc-modern .playbackSoundBadge__actions {
        background-color: transparent !important;
        background: transparent !important;
        background-image: none !important;
      }

      /* Кнопки управления плеером (skip, shuffle, repeat) */
      html.dc-modern .playControls__buttons button:not([class*="playControls__play"]),
      html.dc-modern .playControls [class*="skipControl"],
      html.dc-modern .playControls [class*="shuffleControl"],
      html.dc-modern .playControls [class*="repeatControl"] {
        background-color: transparent !important;
        background-image: none !important;
        box-shadow: none !important;
        border: none !important;
        color: rgba(255, 255, 255, 0.72) !important;
        opacity: 0.88 !important;
        cursor: pointer !important;
        transition: color var(--dc-fast), opacity var(--dc-fast), transform var(--dc-fast) !important;
      }
      html.dc-modern .playControls__buttons button:not([class*="playControls__play"]):hover,
      html.dc-modern .playControls [class*="skipControl"]:hover,
      html.dc-modern .playControls [class*="shuffleControl"]:hover,
      html.dc-modern .playControls [class*="repeatControl"]:hover {
        color: #ffffff !important;
        opacity: 1 !important;
        transform: scale(1.1) !important;
      }
      html.dc-modern .playControls__buttons button:not([class*="playControls__play"]) svg,
      html.dc-modern .playControls [class*="skipControl"] svg,
      html.dc-modern .playControls [class*="shuffleControl"] svg,
      html.dc-modern .playControls [class*="repeatControl"] svg {
        fill: currentColor !important;
        transition: fill var(--dc-fast) !important;
      }

      /* Активные состояния shuffle / repeat */
      html.dc-modern .playControls [class*="shuffleControl"][class*="active" i],
      html.dc-modern .playControls [class*="shuffleControl"][class*="shuffling" i],
      html.dc-modern .playControls [class*="shuffleControl"][aria-checked="true"],
      html.dc-modern .playControls [class*="repeatControl"][class*="active" i],
      html.dc-modern .playControls [class*="repeatControl"][class*="one" i],
      html.dc-modern .playControls [class*="repeatControl"][class*="all" i],
      html.dc-modern .playControls [class*="repeatControl"][aria-checked="true"] {
        color: var(--dc-accent) !important;
        opacity: 1 !important;
        filter: drop-shadow(0 0 6px var(--dc-accent-soft)) !important;
      }
      html.dc-modern .playControls [class*="shuffleControl"][class*="active" i] svg,
      html.dc-modern .playControls [class*="repeatControl"][class*="active" i] svg {
        fill: var(--dc-accent) !important;
      }

      /* Нативная шкала времени */
      html.dc-modern .playbackTimeline {
        display: flex !important;
        align-items: center !important;
        gap: 12px !important;
      }
      html.dc-modern .playbackTimeline__timePassed,
      html.dc-modern .playbackTimeline__duration {
        font-size: 11px !important;
        font-variant-numeric: tabular-nums !important;
        color: var(--dc-muted) !important;
        opacity: 0.9 !important;
      }
      html.dc-modern [data-dc-player] .playbackTimeline__progressBackground,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressBackground,
      html.dc-modern footer .playbackTimeline__progressBackground {
        background-color: rgba(255,255,255,.14) !important;
        height: 4px !important;
        border-radius: 999px !important;
        transition: height 120ms ease !important;
      }
      html.dc-modern .playbackTimeline:hover .playbackTimeline__progressBackground {
        height: 6px !important;
      }
      html.dc-modern [data-dc-player] .playbackTimeline__progressBar,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressBar,
      html.dc-modern footer .playbackTimeline__progressBar,
      html.dc-modern [data-dc-player] .playbackTimeline__progress,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progress,
      html.dc-modern footer .playbackTimeline__progress {
        background-color: var(--dc-accent) !important;
        border-radius: 999px !important;
        box-shadow: 0 0 10px var(--dc-accent-soft) !important;
      }
      html.dc-modern [data-dc-player] .playbackTimeline__progressHandle,
      html.dc-modern [data-dc-playerbar] .playbackTimeline__progressHandle,
      html.dc-modern footer .playbackTimeline__progressHandle {
        background-color: #ffffff !important;
        border: 2px solid #0e1015 !important;
        border-radius: 50% !important;
        box-shadow: 0 0 8px rgba(0,0,0,0.5) !important;
        opacity: 0;
        transition: opacity 120ms ease, transform 120ms ease !important;
      }
      html.dc-modern .playbackTimeline:hover .playbackTimeline__progressHandle {
        opacity: 1 !important;
        transform: scale(1.15) !important;
      }

      /* Ползунок громкости */
      html.dc-modern [data-dc-player] .volume__sliderRange,
      html.dc-modern [data-dc-playerbar] .volume__sliderRange,
      html.dc-modern footer .volume__sliderRange {
        background-color: rgba(255,255,255,.14) !important;
        height: 4px !important;
        border-radius: 999px !important;
      }
      html.dc-modern [data-dc-player] .volume__sliderProgress,
      html.dc-modern [data-dc-playerbar] .volume__sliderProgress,
      html.dc-modern footer .volume__sliderProgress {
        background-color: var(--dc-accent) !important;
        border-radius: 999px !important;
        box-shadow: 0 0 8px var(--dc-accent-soft) !important;
      }
      html.dc-modern [data-dc-player] .volume__sliderHandle,
      html.dc-modern [data-dc-playerbar] .volume__sliderHandle,
      html.dc-modern footer .volume__sliderHandle {
        background-color: #ffffff !important;
        border: 2px solid #0e1015 !important;
        border-radius: 50% !important;
        box-shadow: 0 0 6px rgba(0,0,0,0.5) !important;
      }
      html.dc-modern .volume__button {
        color: var(--dc-muted) !important;
        transition: color 140ms ease, transform 140ms ease !important;
      }
      html.dc-modern .volume__button:hover {
        color: #ffffff !important;
        transform: scale(1.08) !important;
      }

      /* Карточка играющего трека справа */
      html.dc-modern .playbackSoundBadge {
        display: flex !important;
        align-items: center !important;
        gap: 12px !important;
      }
      html.dc-modern .playbackSoundBadge__avatar {
        border-radius: 8px !important;
        overflow: hidden !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4) !important;
      }
      html.dc-modern .playbackSoundBadge__titleLink,
      html.dc-modern .playbackSoundBadge__title {
        color: var(--dc-text) !important;
        font-size: 12px !important;
        font-weight: 600 !important;
        line-height: 1.3 !important;
      }
      html.dc-modern .playbackSoundBadge__lightLink,
      html.dc-modern .playbackSoundBadge__artist {
        color: var(--dc-muted) !important;
        font-size: 11px !important;
        line-height: 1.3 !important;
      }
      html.dc-modern .playbackSoundBadge__actions button {
        color: var(--dc-muted) !important;
        opacity: 0.72 !important;
        transition: all 140ms ease !important;
      }
      html.dc-modern .playbackSoundBadge__actions button:hover {
        color: var(--dc-text) !important;
        opacity: 1 !important;
        transform: scale(1.1) !important;
      }
      html.dc-modern .playbackSoundBadge__actions .sc-button-like[aria-selected="true"],
      html.dc-modern .playbackSoundBadge__actions .sc-button-like.sc-button-selected {
        color: #ff3344 !important;
        opacity: 1 !important;
      }

      /* Круглая кнопка Play/Pause плеера */
      html.dc-modern [class*="playControls__play"] {
        background-color: #ffffff !important;
        border: none !important;
        border-radius: 50% !important;
        box-shadow: 0 4px 16px rgba(0,0,0,.45), 0 0 0 1px rgba(255,255,255,.15) !important;
        transition: transform 120ms cubic-bezier(.2,.8,.2,1), box-shadow 120ms ease, background-color 120ms ease !important;
      }
      html.dc-modern [class*="playControls__play"]:hover {
        background-color: var(--dc-accent, #ffffff) !important;
        transform: scale(1.08) !important;
        box-shadow: 0 6px 22px rgba(0,0,0,.55), 0 0 16px var(--dc-accent-soft) !important;
      }
      html.dc-modern [class*="playControls__play"]:active {
        transform: scale(0.95) !important;
      }
      html.dc-modern [class*="playControls__play"] svg {
        fill: #0b0c10 !important;
      }

      /* Акцентные кнопки — цвет текущей темы */
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

      /* Обёртки кнопок на обложках — прозрачные, без рамок и лишних теней */
      html.dc-modern .image__buttonWrapper,
      html.dc-modern .image__playButton,
      html.dc-modern div[class*="playButton" i],
      html.dc-modern .coverArt__playButton:not(button) {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
        border-radius: 0 !important;
        padding: 0 !important;
      }

      /* Затемнение обложки при наведении: мягкое и аккуратное */
      html.dc-modern .image__lightOverlay {
        background: rgba(0, 0, 0, 0.35) !important;
        opacity: 1 !important;
      }

      /* Кнопки Play/Pause на обложках — стеклянный круг строго по центру */
      html.dc-modern button.sc-button-play:not([class*="playControls__play"]),
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]),
      html.dc-modern button.playButton,
      html.dc-modern button.image__button,
      html.dc-modern .image__playButton button,
      html.dc-modern .image__buttonWrapper button.sc-button-play,
      html.dc-modern .image__buttonWrapper button.sc-button-pause,
      html.dc-modern .coverArt__playButton button,
      html.dc-modern .sound__coverArt button.sc-button-play,
      html.dc-modern .sound__coverArt button.sc-button-pause,
      html.dc-modern .soundBadge__coverArt button.sc-button-play,
      html.dc-modern .soundBadge__coverArt button.sc-button-pause,
      html.dc-theme button.sc-button-play:not([class*="playControls__play"]),
      html.dc-theme button.sc-button-pause:not([class*="playControls__play"]),
      html.dc-theme button.playButton {
        border-radius: 50% !important;
        background-color: rgba(15, 17, 23, 0.86) !important;
        -webkit-backdrop-filter: blur(16px) !important;
        backdrop-filter: blur(16px) !important;
        border: 1.5px solid rgba(255, 255, 255, 0.3) !important;
        color: #ffffff !important;
        box-shadow: 0 4px 18px rgba(0, 0, 0, 0.5) !important;
        cursor: pointer !important;
        transition: transform 140ms ease, background-color 140ms ease, border-color 140ms ease, box-shadow 140ms ease !important;
      }

      /* Фиксация центра кнопки на обложках карточек */
      html.dc-modern .image__button,
      html.dc-modern .image__playButton button,
      html.dc-modern .soundBadge__coverArt button.sc-button-play,
      html.dc-modern .soundBadge__coverArt button.sc-button-pause,
      html.dc-modern .sound__coverArt button.sc-button-play,
      html.dc-modern .sound__coverArt button.sc-button-pause,
      html.dc-modern .coverArt button.sc-button-play,
      html.dc-modern .coverArt button.sc-button-pause,
      html.dc-modern .trackItem__artwork button.sc-button-play,
      html.dc-modern .trackItem__artwork button.sc-button-pause {
        position: absolute !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        transform-origin: center center !important;
        margin: 0 !important;
      }

      /* Hover: центрирование translate(-50%, -50%) сохраняется, нет сдвига в правый нижний угол! */
      html.dc-modern button.sc-button-play:not([class*="playControls__play"]):hover,
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]):hover,
      html.dc-modern button.playButton:hover,
      html.dc-modern button.image__button:hover,
      html.dc-modern .image__playButton button:hover,
      html.dc-modern .coverArt__playButton button:hover,
      html.dc-theme button.sc-button-play:not([class*="playControls__play"]):hover,
      html.dc-theme button.sc-button-pause:not([class*="playControls__play"]):hover,
      html.dc-theme button.playButton:hover {
        background-color: rgba(26, 30, 42, 0.94) !important;
        border-color: rgba(255, 255, 255, 0.75) !important;
        color: var(--dc-accent) !important;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.65), 0 0 16px var(--dc-accent-soft) !important;
      }

      html.dc-modern .image__button:hover,
      html.dc-modern .image__playButton button:hover,
      html.dc-modern .soundBadge__coverArt button.sc-button-play:hover,
      html.dc-modern .soundBadge__coverArt button.sc-button-pause:hover,
      html.dc-modern .sound__coverArt button.sc-button-play:hover,
      html.dc-modern .sound__coverArt button.sc-button-pause:hover,
      html.dc-modern .coverArt button.sc-button-play:hover,
      html.dc-modern .coverArt button.sc-button-pause:hover,
      html.dc-modern .trackItem__artwork button.sc-button-play:hover,
      html.dc-modern .trackItem__artwork button.sc-button-pause:hover {
        transform: translate(-50%, -50%) scale(1.05) !important;
      }

      /* Иконка play/pause внутри кнопки на обложках */
      html.dc-modern button.sc-button-play:not([class*="playControls__play"]) svg,
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]) svg,
      html.dc-modern button.playButton svg,
      html.dc-modern button.image__button svg,
      html.dc-modern .image__playButton button svg,
      html.dc-modern .coverArt__playButton button svg,
      html.dc-modern button.sc-button-play:not([class*="playControls__play"]) path,
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]) path,
      html.dc-modern button.playButton path,
      html.dc-modern button.image__button path,
      html.dc-modern .image__playButton button path,
      html.dc-modern .coverArt__playButton button path {
        fill: #ffffff !important;
        color: #ffffff !important;
        transition: fill 140ms ease !important;
      }

      html.dc-modern button.sc-button-play:not([class*="playControls__play"]):hover svg,
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]):hover svg,
      html.dc-modern button.playButton:hover svg,
      html.dc-modern button.image__button:hover svg,
      html.dc-modern .image__playButton button:hover svg,
      html.dc-modern .coverArt__playButton button:hover svg,
      html.dc-modern button.sc-button-play:not([class*="playControls__play"]):hover path,
      html.dc-modern button.sc-button-pause:not([class*="playControls__play"]):hover path,
      html.dc-modern button.playButton:hover path,
      html.dc-modern button.image__button:hover path,
      html.dc-modern .image__playButton button:hover path,
      html.dc-modern .coverArt__playButton button:hover path {
        fill: var(--dc-accent) !important;
        color: var(--dc-accent) !important;
      }

      /* Кнопки действий под кнопкой play на обложке (сердечко, репост...) */
      html.dc-modern .image__buttonWrapper .sc-button-group,
      html.dc-modern .soundBadge__actions .sc-button-group {
        background: rgba(15, 17, 23, 0.85) !important;
        -webkit-backdrop-filter: blur(12px) !important;
        backdrop-filter: blur(12px) !important;
        border-radius: 8px !important;
        border: 1px solid rgba(255, 255, 255, 0.15) !important;
        padding: 2px !important;
      }

      /* noAds V9 */
      html.dc-noads [data-dc-ad],
      html.dc-noads [data-dc-promo] {
        display: none !important;
      }

      /* Скругление обложек */
      html.dc-rounded [data-dc-artwork] {
        border-radius: 11px !important;
        overflow: hidden !important;
        background-clip: padding-box !important;
        isolation: isolate !important;
      }
      html.dc-rounded [data-dc-artwork] img,
      html.dc-rounded img[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] .image__full,
      html.dc-rounded .image__full[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] .sc-artwork,
      html.dc-rounded .sc-artwork[data-dc-artwork],
      html.dc-rounded [data-dc-artwork] [style*="background-image"],
      html.dc-rounded [data-dc-artwork] {
        border-radius: 11px !important;
        overflow: hidden !important;
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

      /* Hover-эффект обложек */
      html.dc-hover [data-dc-card]:hover [data-dc-artwork],
      html.dc-hover [data-dc-artwork]:hover {
        filter: brightness(1.05) !important;
      }
      @media (prefers-reduced-motion: reduce) {
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
        html.dc-modern section.playControls,
        html.dc-modern div.playControls:not([class*="playControls__"]) {
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
          background: #111318 !important;
        }
      }

      /* Focus Mode */
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

  function cleanupBrokenPlayerTags() {
    try {
      document.querySelectorAll('[data-dc-player]').forEach(el => {
        if (el.className && typeof el.className === 'string' && /playControls__/i.test(el.className)) {
          el.removeAttribute('data-dc-player');
        }
      });
    } catch (_) {}
  }

  function tag(scope = document) {
    cleanupBrokenPlayerTags();
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
      for (const a of audioElements(scope)) {
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
    root.classList.remove('dc-compact');
    root.classList.toggle('dc-focus', Boolean(s.focus));
    root.classList.toggle('dc-noads', Boolean(s.adBlock));
    applyAccent();
    fixModernTopGap();
  }

  // ── Мост в приложение ────────────────────────────────────────────
  function post(type, payload) {
    try {
      window.webkit?.messageHandlers?.diecloudeBridge?.postMessage({ type: type, ...payload });
    } catch (_) {}
  }

  // ── Перехват <audio> (включая detached new Audio()) + Now Playing + громкость ──
  const nowPlaying = {
    cleanup: [],
    lastMetaKey: '',
    lastPost: 0,
    missingReported: false,
    missingCheckPending: false,
    missingTimer: 0
  };

  const trackedMedias = new Set();
  let activeMedia = null;
  let applyingVolume = false;
  let volumeSyncTimer = 0;

  // MediaElementSource cannot be created twice for the same element, even after teardown.
  const eq = window.__diecloudeEqualizer || (window.__diecloudeEqualizer = {
    context: null, graphs: new WeakMap(), elements: new Set()
  });
  const eqFrequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  function updateEqualizer() {
    const bands = Array.isArray(state.settings.equalizerBands) ? state.settings.equalizerBands : [];
    for (const media of Array.from(eq.elements)) {
      if (!media || (!document.contains(media) && media !== activeMedia && media.paused)) {
        eq.elements.delete(media);
        continue;
      }
      const graph = eq.graphs.get(media);
      if (!graph) continue;
      if (graph.compressor) {
        graph.compressor.threshold.value = state.settings.equalizerNormalization ? -24 : 0;
        graph.compressor.ratio.value = state.settings.equalizerNormalization ? 4 : 1;
      }
      graph.filters.forEach((filter, index) => {
        const value = Number(bands[index]);
        filter.gain.value = state.settings.equalizerEnabled && Number.isFinite(value)
          ? Math.max(-12, Math.min(12, value)) : 0;
      });
    }
  }

  function attachEqualizer(media) {
    if (!state.settings.equalizerEnabled || eq.graphs.has(media)) return;
    try {
      if (!media.crossOrigin) media.crossOrigin = 'anonymous';
    } catch (_) {}
    try {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) return;
      if (!eq.context) eq.context = new Context();
      const compressor = eq.context.createDynamicsCompressor();
      compressor.threshold.value = state.settings.equalizerNormalization ? -24 : 0;
      compressor.knee.value = 18;
      compressor.ratio.value = state.settings.equalizerNormalization ? 4 : 1;
      compressor.attack.value = 0.003;
      compressor.release.value = 0.25;
      const filters = eqFrequencies.map(frequency => {
        const filter = eq.context.createBiquadFilter();
        filter.type = 'peaking';
        filter.frequency.value = frequency;
        filter.Q.value = 1;
        return filter;
      });
      for (let i = 0; i < filters.length - 1; i++) filters[i].connect(filters[i + 1]);
      filters[filters.length - 1].connect(compressor);
      compressor.connect(eq.context.destination);
      const source = eq.context.createMediaElementSource(media);
      source.connect(filters[0]);
      eq.graphs.set(media, { source, filters, compressor });
      eq.elements.add(media);
      updateEqualizer();
    } catch (error) {
      console.warn('DieCloude equalizer unavailable:', error);
    }
  }

  function resumeEqualizer() {
    if (eq.context?.state === 'suspended') eq.context.resume().catch(() => {});
  }

  function applyStoredVolumeToMedia(media) {
    if (!media) return;
    applyingVolume = true;
    try {
      if (typeof state.settings.volume === 'number' && Number.isFinite(state.settings.volume)) {
        const target = Math.max(0, Math.min(1, state.settings.volume));
        if (Math.abs(media.volume - target) > 0.005) {
          media.volume = target;
        }
      }
      if (typeof state.settings.isMuted === 'boolean' && media.muted !== state.settings.isMuted) {
        media.muted = state.settings.isMuted;
      }
    } catch (_) {}
    applyingVolume = false;
  }

  function audioElements(scope = document) {
    if (scope instanceof Element && scope.tagName === 'AUDIO') return [scope];
    return Array.from(scope.querySelectorAll?.('audio') ?? []);
  }

  function getActiveMedia() {
    if (activeMedia && !activeMedia.paused) return activeMedia;
    for (const m of trackedMedias) {
      if (!m.paused) { activeMedia = m; return m; }
    }
    for (const a of audioElements(document)) {
      hookSingleAudio(a);
      if (!a.paused) { activeMedia = a; return a; }
    }
    return activeMedia || audioElements(document)[0] || Array.from(trackedMedias)[0] || null;
  }

  function postState(a) {
    if (!a) return;
    const now = performance.now();
    if (now - nowPlaying.lastPost < 900 && !a.paused) return;
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
    const clean = value => String(value || '').replace(/^current\s*track\s*:\s*/i, '').replace(/\s+/g, ' ').trim();
    const title = clean(titleEl?.getAttribute('title') || titleEl?.textContent);
    const artist = clean(artistEl?.textContent || artistEl?.getAttribute('title'));
    let trackURL = '';
    try {
      if (titleEl?.href) {
        const url = new URL(titleEl.href);
        if ((url.protocol === 'https:' || url.protocol === 'http:') &&
            (url.hostname === 'soundcloud.com' || url.hostname.endsWith('.soundcloud.com')) &&
            !url.username && !url.password) trackURL = url.href;
      }
    } catch (_) {}
    return { title, artist, artwork, trackURL };
  }

  function maybePostMeta() {
    const meta = readMeta();
    const key = meta.title + '|' + meta.artist + '|' + meta.artwork + '|' + meta.trackURL;
    if (!meta.title || key === nowPlaying.lastMetaKey) return;
    nowPlaying.lastMetaKey = key;
    post('meta', meta);
  }

  function hookSingleAudio(a) {
    if (!a) return;
    try { if (!a.crossOrigin) a.crossOrigin = 'anonymous'; } catch (_) {}
    trackedMedias.add(a);
    applyStoredVolumeToMedia(a);
    if (a.dataset?.dcHooked === '1' || a._dcHooked) return;
    try { if (a.dataset) a.dataset.dcHooked = '1'; } catch (_) {}
    a._dcHooked = true;

    const onPlay = () => {
      attachEqualizer(a);
      resumeEqualizer();
      activeMedia = a;
      applyStoredVolumeToMedia(a);
      postState(a);
      maybePostMeta();
    };
    const onPause = () => { if (!activeMedia || activeMedia === a) postState(a); };
    const onTime = () => { if (!activeMedia || activeMedia === a) postState(a); };
    const onLoaded = () => {
      activeMedia = a;
      applyStoredVolumeToMedia(a);
      postState(a);
      maybePostMeta();
    };
    const onEnded = () => postState(a);
    const onVolumeChange = () => {
      if (applyingVolume) return;
      state.settings.volume = a.volume;
      state.settings.isMuted = a.muted;
      persistVolumeLocal(a.volume, a.muted);
      clearTimeout(volumeSyncTimer);
      volumeSyncTimer = setTimeout(() => {
        post('volume', { volume: a.volume, muted: a.muted });
      }, 120);
    };

    a.addEventListener('play', onPlay);
    a.addEventListener('pause', onPause);
    a.addEventListener('timeupdate', onTime);
    a.addEventListener('loadedmetadata', onLoaded);
    a.addEventListener('ended', onEnded);
    a.addEventListener('volumechange', onVolumeChange);

    nowPlaying.cleanup.push(() => {
      a.removeEventListener('play', onPlay);
      a.removeEventListener('pause', onPause);
      a.removeEventListener('timeupdate', onTime);
      a.removeEventListener('loadedmetadata', onLoaded);
      a.removeEventListener('ended', onEnded);
      a.removeEventListener('volumechange', onVolumeChange);
    });

    postState(a);
    maybePostMeta();
  }

  function hookAudio(scope = document) {
    for (const a of audioElements(scope)) {
      hookSingleAudio(a);
    }
  }

  // Одноразовый глобальный перехват HTMLMediaElement, new Audio(), createElement('audio'), и src
  if (!window.__diecloudeAudioPatched) {
    window.__diecloudeAudioPatched = true;
    const origPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function (...args) {
      try {
        if (!this.crossOrigin) this.crossOrigin = 'anonymous';
        const eng = window.__diecloude;
        if (eng && typeof eng._onMediaPlay === 'function') eng._onMediaPlay(this);
      } catch (_) {}
      return origPlay.apply(this, args);
    };

    const OrigAudio = window.Audio;
    if (OrigAudio) {
      window.Audio = function (...args) {
        const inst = new OrigAudio(...args);
        try {
          inst.crossOrigin = 'anonymous';
          const eng = window.__diecloude;
          if (eng && typeof eng._onAudioCreated === 'function') eng._onAudioCreated(inst);
        } catch (_) {}
        return inst;
      };
      window.Audio.prototype = OrigAudio.prototype;
    }

    const origCreateElement = Document.prototype.createElement;
    Document.prototype.createElement = function (tagName, options) {
      const el = origCreateElement.call(this, tagName, options);
      if (typeof tagName === 'string' && tagName.toLowerCase() === 'audio') {
        try {
          el.crossOrigin = 'anonymous';
          const eng = window.__diecloude;
          if (eng && typeof eng._onAudioCreated === 'function') eng._onAudioCreated(el);
        } catch (_) {}
      }
      return el;
    };

    const srcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (srcDescriptor && srcDescriptor.set) {
      const origSrcSet = srcDescriptor.set;
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        ...srcDescriptor,
        set(value) {
          try {
            if (!this.crossOrigin) this.crossOrigin = 'anonymous';
          } catch (_) {}
          return origSrcSet.call(this, value);
        }
      });
    }

    const origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      if (this instanceof HTMLMediaElement && typeof name === 'string' && name.toLowerCase() === 'src') {
        try {
          if (!this.crossOrigin) this.crossOrigin = 'anonymous';
        } catch (_) {}
      }
      return origSetAttribute.call(this, name, value);
    };
  }

  state._onMediaPlay = (media) => {
    hookSingleAudio(media);
    attachEqualizer(media);
    resumeEqualizer();
    activeMedia = media;
    applyStoredVolumeToMedia(media);
  };
  state._onAudioCreated = (media) => {
    hookSingleAudio(media);
  };

  // ── Горячие клавиши в DOM (capture-фаза для Space и Esc) ──────────
  function isEditableTarget(el) {
    if (!el || !(el instanceof Element)) return false;
    const t = el.tagName;
    if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') return true;
    if (el.isContentEditable) return true;
    const role = (el.getAttribute('role') || '').toLowerCase();
    if (role === 'textbox' || role === 'searchbox' || role === 'combobox') return true;
    return Boolean(el.closest('input, textarea, [contenteditable="true"], [role="searchbox"], [role="combobox"]'));
  }

  const onKeyDown = (e) => {
    if (e.defaultPrevented || e.isComposing) return;
    if (e.key === 'Escape') {
      post('escape', {});
      if (isEditableTarget(e.target) && typeof e.target.blur === 'function') {
        e.target.blur();
      }
      return;
    }
    if ((e.code === 'Space' || e.key === ' ') && !e.metaKey && !e.ctrlKey && !e.altKey) {
      if (isEditableTarget(e.target) || isEditableTarget(document.activeElement)) return;
      e.preventDefault();
      e.stopPropagation();
      if (document.activeElement && document.activeElement !== document.body) {
        try { document.activeElement.blur(); } catch (_) {}
      }
      state.togglePlay();
    }
  };
  window.addEventListener('keydown', onKeyDown, true);

  // ── Диагностика панели плеера ────────────────────────────────────
  function reportPlayerPresence() {
    const found = Boolean(
      document.querySelector('[data-dc-playerbar], [data-dc-player], section.playControls, div.playControls:not([class*="playControls__"])')
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
      const stillMissing = !document.querySelector('[data-dc-playerbar], [data-dc-player], section.playControls, div.playControls:not([class*="playControls__"])');
      if (stillMissing && !nowPlaying.missingReported) {
        nowPlaying.missingReported = true;
        post('playerMissing', {});
      }
    }, 5000);
  }

  function ensurePlayerBar() {
    try {
      const marked = document.querySelector('[data-dc-playerbar]');
      if (marked && marked.isConnected) return;
      const el = document.querySelector(selectors.player);
      if (el) {
        el.setAttribute('data-dc-player', '');
        const bar = (el.closest && el.closest(selectors.playerBar)) || el;
        bar.setAttribute('data-dc-playerbar', '');
      }
    } catch (_) {}
  }

  function fixModernTopGap() {
    if (!root.classList.contains('dc-modern')) {
      try {
        const hi = document.querySelector('.header__inner');
        if (hi) {
          hi.style.removeProperty('padding-bottom');
          hi.style.removeProperty('padding-top');
          hi.style.removeProperty('height');
          hi.style.removeProperty('max-height');
        }
        const h = document.querySelector('.header, header[role="banner"]');
        if (h) {
          h.style.removeProperty('height');
          h.style.removeProperty('max-height');
        }
        const lc = document.querySelector('.l-container.l-content, #app > .l-container');
        if (lc) {
          lc.style.removeProperty('padding-top');
        }
        const content = document.getElementById('content');
        if (content) {
          content.style.removeProperty('padding-top');
          content.style.removeProperty('margin-top');
        }
        const lNav = document.querySelector('.l-nav');
        if (lNav) {
          lNav.style.removeProperty('margin-top');
        }
      } catch (_) {}
      return;
    }
    try {
      const hi = document.querySelector('.header__inner');
      if (hi) {
        hi.style.setProperty('padding-bottom', '0px', 'important');
        hi.style.setProperty('padding-top', '0px', 'important');
        hi.style.setProperty('height', '46px', 'important');
        hi.style.setProperty('max-height', '46px', 'important');
      }
      const h = document.querySelector('.header, header[role="banner"]');
      if (h) {
        h.style.setProperty('height', '46px', 'important');
        h.style.setProperty('max-height', '46px', 'important');
      }
      const lc = document.querySelector('.l-container.l-content, #app > .l-container');
      if (lc) {
        lc.style.setProperty('padding-top', '46px', 'important');
      }
      const content = document.getElementById('content');
      if (content) {
        content.style.setProperty('padding-top', '0px', 'important');
        content.style.setProperty('margin-top', '0px', 'important');
      }
      const lNav = document.querySelector('.l-nav');
      if (lNav) {
        lNav.style.setProperty('margin-top', '6px', 'important');
      }
    } catch (_) {}
  }

  function refresh(scope = document) {
    if (scope === document) {
      ensurePlayerBar();
      fixModernTopGap();
    }
    tag(scope);
    removeAds(scope);
    removePromotedCards(scope);
    skipAudioAds(scope);
    hookAudio(scope);
    applyClasses();
    if (scope === document) { maybePostMeta(); reportPlayerPresence(); }
  }

  function schedule(nodes) {
    for (const n of nodes) {
      if (n instanceof Element) state.pendingNodes.push(n);
    }
    if (state.timer) return;
    state.timer = setTimeout(() => {
      state.timer = 0;
      const batch = state.pendingNodes;
      state.pendingNodes = [];
      try {
        if (batch.length > 40) {
          refresh(document);
          return;
        }
        for (const n of batch) {
          tag(n);
          removeAds(n);
          removePromotedCards(n);
          skipAudioAds(n);
          hookAudio(n);
        }
      } catch (_) {}
      ensurePlayerBar();
      if (state.frame) cancelAnimationFrame(state.frame);
      state.frame = requestAnimationFrame(() => {
        state.frame = 0;
        applyClasses();
      });
      maybePostMeta();
    }, 200);
  }

  // ── Публичный API window.__diecloude ─────────────────────────────
  state.set = (key, value) => {
    state.settings[key] = value;
    if (key === 'equalizerEnabled' || key === 'equalizerBands' || key === 'equalizerNormalization') {
      trackedMedias.forEach(attachEqualizer);
      updateEqualizer();
      if (state.settings.equalizerEnabled) resumeEqualizer();
    }
    refresh(document);
  };
  state.setAll = values => {
    Object.assign(state.settings, values || {});
    if ('equalizerEnabled' in (values || {}) || 'equalizerBands' in (values || {}) || 'equalizerNormalization' in (values || {})) {
      trackedMedias.forEach(attachEqualizer);
      updateEqualizer();
      if (state.settings.equalizerEnabled) resumeEqualizer();
    }
    if (typeof values?.volume === 'number' || typeof values?.isMuted === 'boolean') {
      persistVolumeLocal(state.settings.volume, state.settings.isMuted);
      trackedMedias.forEach(m => applyStoredVolumeToMedia(m));
      for (const a of audioElements(document)) applyStoredVolumeToMedia(a);
    }
    refresh(document);
  };
  state.refresh = () => refresh(document);

  state.togglePlay = () => {
    const b = document.querySelector('.playControls__play, button.playControl')
      || Array.from(document.querySelectorAll('button[aria-label]'))
        .find(el => /play current|pause current|воспроизвед|пауз/i.test(el.getAttribute('aria-label') || ''));
    if (b) {
      b.click();
      setTimeout(() => { const m = getActiveMedia(); if (m) postState(m); }, 60);
      return true;
    }
    const a = getActiveMedia();
    if (a) {
      if (a.paused) a.play(); else a.pause();
      return true;
    }
    return false;
  };

  state.next = () => {
    const b = document.querySelector('.skipControls__next')
      || Array.from(document.querySelectorAll('button[aria-label]'))
        .find(el => /next|следующ/i.test(el.getAttribute('aria-label') || ''));
    if (b) { b.click(); setTimeout(maybePostMeta, 180); return true; }
    return false;
  };

  state.prev = () => {
    const b = document.querySelector('.skipControls__previous')
      || Array.from(document.querySelectorAll('button[aria-label]'))
        .find(el => /previous|prev|предыдущ/i.test(el.getAttribute('aria-label') || ''));
    if (b) { b.click(); setTimeout(maybePostMeta, 180); return true; }
    return false;
  };

  state.seek = seconds => {
    const a = getActiveMedia();
    if (a && isFinite(seconds)) {
      try { a.currentTime = Math.max(0, Math.min(seconds, a.duration || seconds)); postState(a); return true; } catch (_) {}
    }
    return false;
  };

  state.seekBy = delta => {
    const a = getActiveMedia();
    if (a && isFinite(delta)) {
      return state.seek((a.currentTime || 0) + delta);
    }
    return false;
  };

  state.setVolume = vol => {
    const v = Math.max(0, Math.min(1, Number(vol)));
    if (!Number.isFinite(v)) return false;
    state.settings.volume = v;
    if (v > 0 && state.settings.isMuted) state.settings.isMuted = false;
    persistVolumeLocal(v, state.settings.isMuted);
    trackedMedias.forEach(m => applyStoredVolumeToMedia(m));
    for (const a of audioElements(document)) applyStoredVolumeToMedia(a);
    post('volume', { volume: state.settings.volume, muted: state.settings.isMuted });
    return true;
  };

  state.changeVolume = delta => {
    const cur = typeof state.settings.volume === 'number' ? state.settings.volume : 0.8;
    return state.setVolume(cur + Number(delta));
  };

  state.toggleMute = () => {
    state.settings.isMuted = !state.settings.isMuted;
    persistVolumeLocal(state.settings.volume, state.settings.isMuted);
    trackedMedias.forEach(m => applyStoredVolumeToMedia(m));
    for (const a of audioElements(document)) applyStoredVolumeToMedia(a);
    const muteBtn = document.querySelector('.volume__button');
    if (!getActiveMedia() && muteBtn) muteBtn.click();
    post('volume', { volume: state.settings.volume, muted: state.settings.isMuted });
    return state.settings.isMuted;
  };

  state.toggleLike = () => {
    const btn = document.querySelector('.playControls .sc-button-like, .playbackSoundBadge__like');
    if (btn) { btn.click(); return true; }
    return false;
  };

  state.destroy = () => {
    window.removeEventListener('keydown', onKeyDown, true);
    state.observer?.disconnect();
    if (state.timer) clearTimeout(state.timer);
    if (volumeSyncTimer) clearTimeout(volumeSyncTimer);
    if (state._scrollHandler) {
      window.removeEventListener('scroll', state._scrollHandler);
      state._scrollHandler = null;
    }
    state.timer = 0;
    state.pendingNodes = [];
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

  function boot() {
    addStyle();
    const observeTarget = document.body || root;
    state.observer = new MutationObserver(records => {
      const batch = [];
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (node instanceof Element) batch.push(node);
        }
      }
      if (batch.length) schedule(batch);
    });
    if (observeTarget) {
      state.observer.observe(observeTarget, { childList: true, subtree: true });
    }

    // Поддержка бесконечной подгрузки списка треков при достижении конца ленты
    let scrollTicking = false;
    state._scrollHandler = () => {
      if (scrollTicking) return;
      scrollTicking = true;
      requestAnimationFrame(() => {
        scrollTicking = false;
        const scrollBottom = window.innerHeight + window.scrollY;
        const totalHeight = Math.max(
          document.body ? document.body.scrollHeight : 0,
          document.documentElement ? document.documentElement.scrollHeight : 0
        );
        if (totalHeight > 0 && totalHeight - scrollBottom < 280) {
          const spinner = document.querySelector('.lazyLoadingList__spinner, [class*="spinner" i]');
          if (spinner && spinner.offsetParent !== null) {
            window.dispatchEvent(new CustomEvent('scroll'));
          }
        }
      });
    };
    window.addEventListener('scroll', state._scrollHandler, { passive: true });

    updateEqualizer();
    refresh(document);
  }

  if (root) {
    boot();
  } else {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  }
})();
