(() => {
  const DEFAULT_CONFIG = {
    prodAccounts: [],
    devAccounts: [],
    roleRules: [
      { name: "Administrator", match: ["admin", "administrator"], color: "#DC2626" },
      { name: "Developer", match: ["dev", "developer"], color: "#2563EB" },
      { name: "ReadOnly", match: ["readonly", "read-only", "read_only", "ro"], color: "#6B7280" }
    ],
    envColors: {
      Prod: "#F59E0B",
      Dev: "#2563EB",
      Unknown: "#64748B"
    }
  };

  let cachedConfig = DEFAULT_CONFIG;
  let rafHandle = null;

  const SELECTORS = [
    "[data-testid='awsc-nav-account-menu-button']",
    "[data-testid='awsc-nav-account-menu']",
    "[data-testid*='account']",
    "[data-testid='account-label']",
    "#nav-usernameMenu",
    "button[aria-label*='Account']",
    "button[aria-label*='アカウント']",
    "a[aria-label*='Account']",
    "a[aria-label*='アカウント']",
    "header"
  ];

  function normalizeText(text) {
    return text.replace(/\s+/g, " ").trim();
  }

  function splitLines(text) {
    return text
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
  }

  function collectElementText(el) {
    if (!el) return "";
    const parts = [];
    const text = el.innerText || el.textContent || "";
    if (text.trim()) parts.push(text);

    const aria = el.getAttribute("aria-label");
    if (aria && aria.trim()) parts.push(aria);

    const title = el.getAttribute("title");
    if (title && title.trim()) parts.push(title);

    if (el.dataset) {
      Object.values(el.dataset).forEach((value) => {
        if (typeof value === "string" && value.trim()) parts.push(value);
      });
    }

    return parts.join("\n");
  }

  function hasAccountId(text) {
    return /\b(\d{4}-\d{4}-\d{4}|\d{12})\b/.test(text);
  }

  function findAccountText() {
    let fallback = "";
    for (const selector of SELECTORS) {
      const nodes = document.querySelectorAll(selector);
      if (!nodes.length) continue;
      for (const el of nodes) {
        const text = collectElementText(el);
        if (!text || !text.trim()) continue;
        if (hasAccountId(text)) {
          return text;
        }
        if (!fallback) {
          fallback = text;
        }
      }
    }
    return fallback;
  }

  function extractAccountId(text) {
    const match = text.match(/\b(\d{4}-\d{4}-\d{4}|\d{12})\b/);
    if (!match) return "";
    return match[1].replace(/-/g, "");
  }

  function extractPrincipal(text) {
    const normalized = normalizeText(text);
    const pathMatch = normalized.match(/(?:assumed-role|role|user)\/(\S+)/i);
    if (pathMatch && pathMatch[1]) {
      return pathMatch[1];
    }

    const directMatch = normalized.match(/\b[\w+=,.@-]+\/[\w+=,.@-]+\b/);
    if (directMatch && directMatch[0]) {
      return directMatch[0];
    }

    const lines = splitLines(text);
    const accountId = extractAccountId(text);
    const candidates = lines.filter((line) => !line.includes(accountId));
    if (candidates.length === 0) return "";
    return candidates[candidates.length - 1];
  }

  function classifyRole(principal, config) {
    if (!principal) return { name: "Unknown", color: "#64748B" };
    const lower = principal.toLowerCase();
    for (const rule of config.roleRules || []) {
      if (!rule || !rule.match) continue;
      const hits = rule.match.some((m) => lower.includes(String(m).toLowerCase()));
      if (hits) {
        return { name: rule.name || "Unknown", color: rule.color || "#64748B" };
      }
    }
    return { name: "Unknown", color: "#64748B" };
  }

  function classifyEnv(accountId, config) {
    if (!accountId) return "Unknown";
    if ((config.prodAccounts || []).includes(accountId)) return "Prod";
    if ((config.devAccounts || []).includes(accountId)) return "Dev";
    return "Unknown";
  }

  function ensureRibbon() {
    let ribbon = document.getElementById("aws-env-ribbon");
    if (ribbon) return ribbon;

    ribbon = document.createElement("div");
    ribbon.id = "aws-env-ribbon";
    ribbon.innerHTML = "";
    document.body.appendChild(ribbon);
    return ribbon;
  }

  function renderRibbon(ribbon, info, config) {
    if (location.href.includes("/iam/")) {
      ribbon.classList.add("aws-env-ribbon--iam");
    } else {
      ribbon.classList.remove("aws-env-ribbon--iam");
    }

    const envColor = (config.envColors && config.envColors[info.env]) || "#64748B";
    ribbon.style.setProperty("--env-color", envColor);
    ribbon.style.setProperty("--role-color", info.role.color);

    ribbon.innerHTML = [
      `<div class="aws-env-ribbon__env">${info.env}</div>`,
      `<div class="aws-env-ribbon__panel">`,
      `<span class="aws-env-ribbon__account">${info.accountId || "アカウント不明"}</span>`,
      `<span class="aws-env-ribbon__role">権限: ${info.role.name}</span>`,
      `</div>`
    ].join("");
  }

  function collectInfo(config) {
    if (window.top !== window) {
      try {
        if (window.top.__awsEnvRibbonInfo) {
          return window.top.__awsEnvRibbonInfo;
        }
      } catch (_) {
        // 参照不可の場合は通常の取得にフォールバック
      }
    }

    const accountText = findAccountText();
    const accountId = extractAccountId(accountText);
    const principal = extractPrincipal(accountText);
    const env = classifyEnv(accountId, config);
    const role = classifyRole(principal, config);

    const info = { accountId, principal, env, role };

    if (window.top === window) {
      try {
        window.__awsEnvRibbonInfo = info;
      } catch (_) {
        // 保存できない場合は無視
      }
    }

    return info;
  }

  async function loadConfig() {
    const localUrl = chrome.runtime.getURL("config.local.json");
    const exampleUrl = chrome.runtime.getURL("config.example.json");

    try {
      const res = await fetch(localUrl);
      if (!res.ok) throw new Error("local config not found");
      const data = await res.json();
      return mergeConfig(DEFAULT_CONFIG, data);
    } catch (_) {
      try {
        const res = await fetch(exampleUrl);
        if (!res.ok) throw new Error("example config not found");
        const data = await res.json();
        return mergeConfig(DEFAULT_CONFIG, data);
      } catch (_) {
        return DEFAULT_CONFIG;
      }
    }
  }

  function mergeConfig(base, extra) {
    const merged = { ...base, ...(extra || {}) };
    merged.prodAccounts = normalizeAccountList(merged.prodAccounts || []);
    merged.devAccounts = normalizeAccountList(merged.devAccounts || []);
    merged.roleRules = Array.isArray(merged.roleRules) ? merged.roleRules : base.roleRules;
    merged.envColors = { ...base.envColors, ...(merged.envColors || {}) };
    return merged;
  }

  function normalizeAccountList(list) {
    if (Array.isArray(list)) {
      return list
        .map((item) => normalizeAccountIdString(String(item)))
        .filter(Boolean);
    }
    if (typeof list === "string") {
      return list
        .split(/[,\s]+/)
        .map((item) => normalizeAccountIdString(item))
        .filter(Boolean);
    }
    return [];
  }

  function normalizeAccountIdString(value) {
    const trimmed = String(value).trim();
    if (!trimmed) return "";
    const digits = trimmed.replace(/[^0-9]/g, "");
    if (digits.length === 12) return digits;
    return trimmed;
  }

  function scheduleUpdate() {
    if (rafHandle) return;
    rafHandle = window.requestAnimationFrame(() => {
      rafHandle = null;
      const ribbon = ensureRibbon();
      const info = collectInfo(cachedConfig);
      renderRibbon(ribbon, info, cachedConfig);
    });
  }

  function observeChanges() {
    const observer = new MutationObserver(() => scheduleUpdate());
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  async function init() {
    cachedConfig = await loadConfig();
    scheduleUpdate();
    observeChanges();
  }

  init();
})();
