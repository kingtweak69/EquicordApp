(() => {
  "use strict";

  if (window.__equicordMobileInstalled) return;
  window.__equicordMobileInstalled = true;

  const STYLE_ID = "equicord-mobile-style";

  const css = `
    :root {
      --eq-safe-top: env(safe-area-inset-top, 0px);
      --eq-safe-bottom: env(safe-area-inset-bottom, 0px);
      --eq-drawer-width: min(88vw, 360px);
    }

    html, body, #app-mount {
      width: 100% !important;
      min-width: 0 !important;
      max-width: 100vw !important;
      overflow-x: hidden !important;
      background: #0e0f12 !important;
    }

    body {
      overscroll-behavior: none !important;
      -webkit-text-size-adjust: 100%;
      touch-action: manipulation;
    }

    * {
      -webkit-tap-highlight-color: transparent;
      box-sizing: border-box;
    }

    input, textarea, [contenteditable="true"] {
      font-size: 16px !important;
    }

    /* App root / major layout containers */
    #app-mount > div,
    #app-mount > div > div {
      min-width: 0 !important;
      max-width: 100vw !important;
    }

    /* Discord changes hashed class names frequently. These semantic fallbacks
       target the recurring sidebar/channel/member structures without relying
       on one exact build. */
    [class*="guilds"],
    [class*="sidebarList"],
    [class*="sidebar_"],
    [class*="membersWrap"],
    [class*="members_"] {
      transition: transform .22s ease, opacity .22s ease !important;
    }

    /* Member list wastes too much width on a phone. */
    [class*="membersWrap"],
    [class*="members_"] {
      display: none !important;
    }

    /* Channel/server drawer: hidden by default on narrow layouts. */
    @media (max-width: 700px) {
      [class*="guilds"] {
        position: fixed !important;
        z-index: 10003 !important;
        left: 0 !important;
        top: 0 !important;
        bottom: 0 !important;
        height: 100dvh !important;
        transform: translateX(-110%) !important;
      }

      [class*="sidebarList"],
      [class*="sidebar_"] {
        position: fixed !important;
        z-index: 10002 !important;
        left: 72px !important;
        top: 0 !important;
        bottom: 0 !important;
        height: 100dvh !important;
        width: calc(var(--eq-drawer-width) - 72px) !important;
        max-width: calc(var(--eq-drawer-width) - 72px) !important;
        transform: translateX(-140%) !important;
      }

      body.eq-drawer-open [class*="guilds"] {
        transform: translateX(0) !important;
      }

      body.eq-drawer-open [class*="sidebarList"],
      body.eq-drawer-open [class*="sidebar_"] {
        transform: translateX(0) !important;
      }

      [class*="chat_"],
      [class*="chatContent"],
      main {
        min-width: 0 !important;
        width: 100% !important;
        max-width: 100vw !important;
      }

      [class*="toolbar"] {
        gap: 2px !important;
      }

      [class*="toolbar"] > * {
        margin-left: 0 !important;
      }

      [class*="messageListItem"],
      [class*="message_"] {
        max-width: 100vw !important;
      }

      [class*="form_"],
      [class*="channelTextArea"] {
        margin-left: 8px !important;
        margin-right: 8px !important;
      }

      [class*="embedWrapper"],
      [class*="imageWrapper"] {
        max-width: calc(100vw - 52px) !important;
      }
    }

    #equicord-dim {
      display: none;
      position: fixed;
      inset: 0;
      z-index: 10001;
      background: rgba(0,0,0,.56);
      backdrop-filter: blur(2px);
      -webkit-backdrop-filter: blur(2px);
    }

    body.eq-drawer-open #equicord-dim {
      display: block;
    }

    #equicord-grabber {
      position: fixed;
      z-index: 10000;
      left: 4px;
      top: 42%;
      width: 4px;
      height: 70px;
      border-radius: 99px;
      background: rgba(255,255,255,.20);
      pointer-events: none;
    }

    @media (min-width: 701px) {
      #equicord-grabber, #equicord-dim {
        display: none !important;
      }
    }
  `;

  function installStyle() {
    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    }
  }

  function installOverlay() {
    if (!document.body) return;

    if (!document.getElementById("equicord-dim")) {
      const dim = document.createElement("div");
      dim.id = "equicord-dim";
      dim.addEventListener("click", () => closeDrawer());
      document.body.appendChild(dim);
    }

    if (!document.getElementById("equicord-grabber")) {
      const grabber = document.createElement("div");
      grabber.id = "equicord-grabber";
      document.body.appendChild(grabber);
    }
  }

  function openDrawer() {
    document.body?.classList.add("eq-drawer-open");
  }

  function closeDrawer() {
    document.body?.classList.remove("eq-drawer-open");
  }

  function toggleDrawer() {
    document.body?.classList.toggle("eq-drawer-open");
  }

  function clickCandidate(selectors, textMatchers = []) {
    for (const selector of selectors) {
      const el = document.querySelector(selector);
      if (el instanceof HTMLElement) {
        el.click();
        return true;
      }
    }

    const all = Array.from(document.querySelectorAll("button, a, [role='button'], [role='link']"));
    for (const node of all) {
      const label = [
        node.getAttribute?.("aria-label"),
        node.getAttribute?.("title"),
        node.textContent
      ].filter(Boolean).join(" ").toLowerCase();

      if (textMatchers.some(x => label.includes(x))) {
        node.click();
        return true;
      }
    }

    return false;
  }

  function navigate(destination) {
    closeDrawer();

    switch (destination) {
      case "drawer":
      case "servers":
        toggleDrawer();
        break;

      case "messages":
        // Discord's exact DOM varies by release; favor semantic labels.
        clickCandidate(
          [
            'a[href="/channels/@me"]',
            'a[href*="/channels/@me"]'
          ],
          ["direct messages", "messages", "home"]
        );
        break;

      case "search":
        clickCandidate(
          [
            'button[aria-label*="Search"]',
            '[role="button"][aria-label*="Search"]'
          ],
          ["search"]
        );
        break;

      case "profile":
        clickCandidate(
          [
            'button[aria-label*="User Settings"]',
            '[role="button"][aria-label*="User Settings"]'
          ],
          ["user settings", "settings", "profile"]
        );
        break;
    }
  }

  let startX = 0;
  let startY = 0;

  window.addEventListener("touchstart", e => {
    const touch = e.touches?.[0];
    if (!touch) return;
    startX = touch.clientX;
    startY = touch.clientY;
  }, { passive: true });

  window.addEventListener("touchend", e => {
    const touch = e.changedTouches?.[0];
    if (!touch) return;

    const dx = touch.clientX - startX;
    const dy = touch.clientY - startY;

    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.25) return;

    if (startX < 30 && dx > 0) {
      openDrawer();
    } else if (dx < -70) {
      closeDrawer();
    }
  }, { passive: true });

  const observer = new MutationObserver(() => {
    installStyle();
    installOverlay();
  });

  installStyle();

  if (document.body) {
    installOverlay();
    observer.observe(document.body, { childList: true, subtree: true });
  } else {
    window.addEventListener("DOMContentLoaded", () => {
      installOverlay();
      observer.observe(document.body, { childList: true, subtree: true });
    }, { once: true });
  }

  window.EquicordMobile = {
    navigate,
    openDrawer,
    closeDrawer,
    toggleDrawer
  };
})();
