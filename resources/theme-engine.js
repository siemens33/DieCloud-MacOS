(() => {
  'use strict';

  // DieCloude 4.2.0 — theme engine
  // Тегирование + MutationObserver + один <style>, как раньше.
  // 4.2.0: Редизайн клиента и плавающей панели плеера, улучшенные карточки,
  // устранены визуальные артефакты, плавные переходы и акцентные свечения.

  const initial = __SETTINGS__;
  const previous = window.__diecloudeThemeEngine;
  if (previous && typeof previous.destroy === 'function') previous.destroy();

  const root = document.documentElement;
  const STYLE_ID = 'diecloude-theme-engine';
  const state = { settings: { ...initial }, observer: null, timer: 0, frame: 0, pendingNodes: [] };

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
      /* Отступ снизу, чтобы лента треков не перекрывалась фиксированным плеером */
      html.dc-modern .l-container,
      html.dc-modern .l-content {
        padding-bottom: 96px !important;
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

      /* Верхняя панель SoundCloud — тёмная матовая шапка */
      html.dc-modern [data-dc-header],
      html.dc-modern header[role="banner"],
      html.dc-modern .header {
        background-color: rgba(14, 16, 21, 0.95) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        backdrop-filter: blur(20px) !important;
        border-bottom: 1px solid var(--dc-line) !important;
        box-shadow: 0 4px 16px rgba(0,0,0,.3) !important;
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

      /* Refined secondary buttons (excluding play/pause buttons) */
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

      /* Tab-style navigation links */
      html.dc-modern .g-tabs-link,
      html.dc-modern [class*="profileTab"] {
        color: var(--dc-muted) !important;
        border-bottom-color: transparent !important;
        transition: color var(--dc-fast), border-color var(--dc-fast) !important;
      }
      html.dc-modern .g-tabs-link.active,
      html.dc-modern .g-tabs-link:hover,
      html.dc-modern [class*="profileTab"].active,
      html.dc-modern [class*="profileTab"]:hover {
        color: var(--dc-text) !important;
        border-bottom-color: var(--dc-accent) !important;
      }

      /* Highlight currently playing track in lists */
      html.dc-modern .trackItem.playing,
      html.dc-modern .trackList__item.playing,
      html.dc-modern .soundList__item.playing {
        background: linear-gradient(90deg, var(--dc-accent-soft), transparent 70%) !important;
        border-left: 2px solid var(--dc-accent) !important;
      }

      /* User profile hero section */
      html.dc-modern .profileHeader,
      html.dc-modern [class*="profileHeader"] {
        background: linear-gradient(180deg, var(--dc-surface-2), var(--dc-bg)) !important;
        border-bottom: 1px solid var(--dc-line) !important;
      }

      /* Stats numbers */
      html.dc-modern .infoStats__value,
      html.dc-modern [class*="infoStats"] {
        color: var(--dc-text) !important;
      }

      /* Links */
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

      /* Waveform in player */
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
         МАТОВЫЙ ПЛЕЕР. Реальная разметка SoundCloud (проверено в
         живом DOM): панель — это div.playControls (position:fixed),
         внутри section.playControls__inner[role=contentinfo] с плотным
         серым фоном; <footer> на странице нет. Стекло кладём на сам
         .playControls (и теги движка), всё внутри — прозрачное, кроме
         шкалы/громкости (их красим отдельно) и родной белой кнопки
         .playControls__play — её не трогаем вовсе.
         ───────────────────────────────────────────────────────────── */
      /* ─────────────────────────────────────────────────────────────
         МАТОВАЯ ПАНЕЛЬ ПЛЕЕРА
         Плотный глубокий матовый фон (#111318), чистая граница сверху,
         высота и полное перекрытие контента под плеером.
         ───────────────────────────────────────────────────────────── */
      html.dc-modern .playControls,
      html.dc-modern .playControls__inner,
      html.dc-modern [data-dc-player],
      html.dc-modern [data-dc-playerbar],
      html.dc-modern [data-testid="play-controls"],
      html.dc-modern .playControls:hover,
      html.dc-modern .playControls__inner:hover,
      html.dc-modern [data-dc-player]:hover,
      html.dc-modern [data-dc-playerbar]:hover {
        background-color: #111318 !important;
        background: #111318 !important;
        border-top: 1px solid rgba(255, 255, 255, 0.09) !important;
        box-shadow: 0 -4px 24px rgba(0, 0, 0, 0.7) !important;
        opacity: 1 !important;
      }
      html.dc-modern .playControls {
        position: fixed !important;
        bottom: 0 !important;
        left: 0 !important;
        right: 0 !important;
        z-index: 1000 !important;
      }
      html.dc-modern .playControls__inner {
        min-height: 54px !important;
        max-width: 1280px !important;
        margin: 0 auto !important;
        display: flex !important;
        align-items: center !important;
        padding: 0 16px !important;
        box-sizing: border-box !important;
      }
      html.dc-modern .playControls__buttons {
        display: flex !important;
        align-items: center !important;
        gap: 8px !important;
      }

      /* Прозрачные обёртки внутренних элементов (но НЕ сам .playControls__inner!) */
      html.dc-modern .playControls__elements,
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

      /* Активные состояния shuffle / repeat (когда включены) */
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
        filter: drop-shadow(0 0 6px var(--dc-accent-soft)) !important;
      }
      html.dc-modern .playControls [class*="shuffleControl"][class*="active" i] svg,
      html.dc-modern .playControls [class*="repeatControl"][class*="active" i] svg {
        fill: var(--dc-accent) !important;
      }

      /* Нативная шкала времени: плавная полоска с подсветкой и круглым бегунком */
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

      /* Ползунок громкости — в ту же гамму */
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

      /* Круглая кнопка Play/Pause плеера: яркая, контрастная, плавная реакция */
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
      /* Иконка внутри кнопки всегда контрастная тёмная */
      html.dc-modern [class*="playControls__play"] svg {
        fill: #0b0c10 !important;
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
      /* Кнопка воспроизведения/паузы на обложках (Play/Pause button overlay) — всегда идеальный круг */
      html.dc-modern .sc-button-play:not([class*="playControls__play"]),
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]),
      html.dc-modern .playButton,
      html.dc-modern [class*="playButton" i],
      html.dc-modern .image__button,
      html.dc-modern .coverArt__playButton button,
      html.dc-modern [class*="coverArt"] button,
      html.dc-theme .sc-button-play:not([class*="playControls__play"]),
      html.dc-theme .sc-button-pause:not([class*="playControls__play"]),
      html.dc-theme .playButton {
        border-radius: 50% !important;
        background-color: rgba(15, 17, 23, 0.88) !important;
        -webkit-backdrop-filter: blur(16px) !important;
        backdrop-filter: blur(16px) !important;
        border: 1.5px solid rgba(255, 255, 255, 0.28) !important;
        color: #ffffff !important;
        box-shadow: 0 6px 22px rgba(0, 0, 0, 0.55) !important;
        transition: transform 140ms ease, background-color 140ms ease, border-color 140ms ease !important;
      }
      html.dc-modern .sc-button-play:not([class*="playControls__play"]):hover,
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]):hover,
      html.dc-modern .playButton:hover,
      html.dc-modern [class*="playButton" i]:hover,
      html.dc-modern .image__button:hover,
      html.dc-modern .coverArt__playButton button:hover,
      html.dc-modern [class*="coverArt"] button:hover,
      html.dc-theme .sc-button-play:not([class*="playControls__play"]):hover,
      html.dc-theme .sc-button-pause:not([class*="playControls__play"]):hover,
      html.dc-theme .playButton:hover {
        transform: scale(1.08) !important;
        background-color: var(--dc-accent) !important;
        border-color: var(--dc-accent) !important;
        color: #0b0c10 !important;
        box-shadow: 0 8px 26px var(--dc-accent-soft), 0 4px 16px rgba(0,0,0,0.6) !important;
      }
      /* Иконка внутри кнопки воспроизведения/паузы на обложке */
      html.dc-modern .sc-button-play:not([class*="playControls__play"]) svg,
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]) svg,
      html.dc-modern .playButton svg,
      html.dc-modern [class*="playButton" i] svg,
      html.dc-modern .image__button svg,
      html.dc-modern .coverArt__playButton svg,
      html.dc-modern [class*="coverArt"] button svg,
      html.dc-modern .sc-button-play:not([class*="playControls__play"]) path,
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]) path,
      html.dc-modern .playButton path,
      html.dc-modern [class*="playButton" i] path,
      html.dc-modern .image__button path,
      html.dc-modern .coverArt__playButton path,
      html.dc-modern [class*="coverArt"] button path {
        fill: #ffffff !important;
        color: #ffffff !important;
        transition: fill 140ms ease !important;
      }
      html.dc-modern .sc-button-play:not([class*="playControls__play"]):hover svg,
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]):hover svg,
      html.dc-modern .playButton:hover svg,
      html.dc-modern [class*="playButton" i]:hover svg,
      html.dc-modern .image__button:hover svg,
      html.dc-modern .coverArt__playButton button:hover svg,
      html.dc-modern [class*="coverArt"] button:hover svg,
      html.dc-modern .sc-button-play:not([class*="playControls__play"]):hover path,
      html.dc-modern .sc-button-pause:not([class*="playControls__play"]):hover path,
      html.dc-modern .playButton:hover path,
      html.dc-modern [class*="playButton" i]:hover path,
      html.dc-modern .image__button:hover path,
      html.dc-modern .coverArt__playButton button:hover path,
      html.dc-modern [class*="coverArt"] button:hover path {
        fill: #0b0c10 !important;
        color: #0b0c10 !important;
      }
      html.dc-modern .image__buttonWrapper {
        background: transparent !important;
        border: none !important;
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
        html.dc-modern [class*="playControls" i] {
          -webkit-backdrop-filter: none !important;
          backdrop-filter: none !important;
          background: #111318 !important;
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
      const el = document.querySelector(selectors.player) || document.querySelector('.playControls, [class*="playControls" i]');
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
    // Дебаунс 180мс. Раньше повторные мутации во время таймера отбрасывались —
    // реклама/аудио, появившиеся в этом окне, могли не обработаться.
    for (const n of nodes) {
      if (n instanceof Element) state.pendingNodes.push(n);
    }
    if (state.timer) return;
    state.timer = setTimeout(() => {
      state.timer = 0;
      const batch = state.pendingNodes;
      state.pendingNodes = [];
      try {
        // Если накопилось слишком много узлов — дешевле один проход по document.
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
    }, 220);
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
