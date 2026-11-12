"use strict";
(function () {
  const screens = [...document.querySelectorAll("[data-screen]")];
  const tabs = [...document.querySelectorAll("[data-tab]")];
  const validScreens = new Set(screens.map((screen) => screen.dataset.screen));
  const dialog = document.getElementById("install-dialog");
  const installButton = document.getElementById("install");

  function activate(name, addHistory) {
    const target = validScreens.has(name) ? name : "home";
    screens.forEach((screen) => {
      const active = screen.dataset.screen === target;
      screen.hidden = !active;
      screen.classList.toggle("active", active);
    });
    tabs.forEach((tab) => {
      const active = tab.dataset.tab === target;
      tab.classList.toggle("active", active);
      if (active) tab.setAttribute("aria-current", "page");
      else tab.removeAttribute("aria-current");
    });
    if (addHistory && location.hash !== "#" + target) {
      history.pushState({ screen: target }, "", "#" + target);
    }
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  document.addEventListener("click", (event) => {
    const tab = event.target.closest("[data-tab]");
    const link = event.target.closest("[data-go]");
    if (tab) activate(tab.dataset.tab, true);
    else if (link) activate(link.dataset.go, true);
  });

  window.addEventListener("popstate", () => {
    activate(location.hash.slice(1) || "home", false);
  });

  const now = new Date();
  const today = document.getElementById("today");
  today.textContent = new Intl.DateTimeFormat("ru-RU", {
    weekday: "long",
    day: "numeric",
    month: "long"
  }).format(now).toLocaleUpperCase("ru-RU");

  function isStandalone() {
    return navigator.standalone === true ||
      window.matchMedia("(display-mode: standalone)").matches;
  }

  function isIOS() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  }

  function showInstallHelp() {
    if (dialog && typeof dialog.showModal === "function") dialog.showModal();
  }

  installButton.addEventListener("click", showInstallHelp);
  document.getElementById("close-dialog").addEventListener("click", () => dialog.close());
  document.getElementById("done-dialog").addEventListener("click", () => dialog.close());

  installButton.hidden = !isIOS() || isStandalone();
  activate(location.hash.slice(1) || "home", false);
})();