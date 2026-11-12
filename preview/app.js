const tracks = [
  { id: 1, title: "Afterglow", artist: "Lena Vale", album: "Open Skies", duration: "3:42" },
  { id: 2, title: "Slow Orbit", artist: "Kite Theory", album: "Night Transit", duration: "4:11" },
  { id: 3, title: "Glass Houses", artist: "Mira North", album: "Soft Geometry", duration: "3:18" },
  { id: 4, title: "Signal Bloom", artist: "Arc Relay", album: "Low Light", duration: "2:56" },
  { id: 5, title: "Still Awake", artist: "June Weather", album: "Half Past", duration: "4:03" },
  { id: 6, title: "Paper Moons", artist: "Lena Vale", album: "Open Skies", duration: "3:29" },
];
const tabs = [
  ["home", "house", "Home"],
  ["search", "search", "Search"],
  ["library", "library-big", "Your Library"],
  ["settings", "settings", "Settings"],
];

const palettes = {
  dark:     { dark: 1, bg: "#0a0a0a", fg: "#fafafa", secondary: "#171717", muted: "#262626", mfg: "#909090", popover: "#141414", primary: "#fafafa", pfg: "#171717", selection: "#1d4ed8", border: "#50505066", hover: "#36363666" },
  light:    { dark: 0, bg: "#fafafa", fg: "#171717", secondary: "#f5f5f5", muted: "#e5e5e5", mfg: "#606060", popover: "#ffffff", primary: "#171717", pfg: "#fafafa", selection: "#2563eb", border: "#9b9b9b66", hover: "#d5d5d566" },
  midnight: { dark: 1, bg: "#07111f", fg: "#e6edf7", secondary: "#102238", muted: "#15283d", mfg: "#8296ad", popover: "#0b1a2c", primary: "#38bdf8", pfg: "#07111f", selection: "#0284c7", border: "#40689266", hover: "#23477066" },
  forest:   { dark: 1, bg: "#0b1410", fg: "#ecf7ef", secondary: "#16261d", muted: "#203328", mfg: "#86a58f", popover: "#101d16", primary: "#86efac", pfg: "#0b1410", selection: "#16a34a", border: "#4e7a6066", hover: "#304a3a66" },
  ocean:    { dark: 1, bg: "#06171a", fg: "#e6edf7", secondary: "#0f292d", muted: "#17373b", mfg: "#7fa9ad", popover: "#0a2024", primary: "#5eead4", pfg: "#06171a", selection: "#0d9488", border: "#3f808666", hover: "#244f5466" },
  rose:     { dark: 1, bg: "#180b10", fg: "#fafafa", secondary: "#2b161e", muted: "#3b2029", mfg: "#b58a98", popover: "#211018", primary: "#fda4af", pfg: "#180b10", selection: "#e11d48", border: "#984e6766", hover: "#55303c66" },
  lavender: { dark: 1, bg: "#120e1c", fg: "#fafafa", secondary: "#241c35", muted: "#302745", mfg: "#a99bc2", popover: "#191326", primary: "#c4b5fd", pfg: "#120e1c", selection: "#7c3aed", border: "#7e66b266", hover: "#473a6466" },
  amber:    { dark: 1, bg: "#171108", fg: "#fafafa", secondary: "#291f11", muted: "#382b18", mfg: "#ad9878", popover: "#20170c", primary: "#fcd34d", pfg: "#171108", selection: "#d97706", border: "#94703c66", hover: "#513f2466" },
};
const themeNames = ["system", "dark", "light", "midnight", "forest", "ocean", "rose", "lavender", "amber"];
const rounding = { square: 0, subtle: 6, rounded: 10, round: 20 };
const paceScale = { slow: 1.6, base: 1, quick: 0.6 };
const faces = {
  inter: "Inter, system-ui, sans-serif", system: "-apple-system, system-ui, sans-serif",
  rounded: "ui-rounded, 'SF Pro Rounded', system-ui, sans-serif", serif: "ui-serif, Georgia, serif", monospaced: "ui-monospace, Menlo, monospace",
};
const defaults = { theme: "system", adaptive: false, iconPack: "lucide", blur: false, corners: "subtle", ambient: true, ambientMotion: true, fontSize: 14, typeface: "inter", reduceMotion: false, pace: "base" };
const look = { ...defaults, ...JSON.parse(localStorage.getItem("sonora-look") || "{}") };
const systemDark = () => matchMedia("(prefers-color-scheme: dark)").matches;
const paletteOf = name => palettes[name === "system" ? (systemDark() ? "dark" : "light") : name];

function applyLook() {
  const p = paletteOf(look.theme), r = document.documentElement.style;
  const set = { "--bg": p.bg, "--fg": p.fg, "--secondary": p.secondary, "--muted": p.muted, "--muted-fg": p.mfg, "--popover": p.popover, "--primary": p.primary, "--primary-fg": p.pfg, "--selection": p.selection, "--border": p.border, "--hover": p.hover,
    "--radius": rounding[look.corners] + "px", "--base": look.fontSize + "px", "--pace": look.reduceMotion ? 0 : paceScale[look.pace] };
  for (const [k, v] of Object.entries(set)) r.setProperty(k, v);
  r.setProperty("font-family", faces[look.typeface]);
  r.colorScheme = p.dark ? "dark" : "light";
  document.body.classList.toggle("blur-ui", look.blur);
  document.body.classList.toggle("no-ambient", !look.ambient);
  document.body.classList.toggle("still", !look.ambientMotion || look.reduceMotion);
  localStorage.setItem("sonora-look", JSON.stringify(look));
}

let tab = "home";
let settingsTab = "general";
let imported = true;
let current = null;
let playing = false;
const screen = document.querySelector("#screen");
const player = document.querySelector("#player");
const nowPlaying = document.querySelector("#nowPlaying");
const tabBar = document.querySelector(".tabs");

const lacking = { iconoir: ["file-music"], solar: ["plus", "check"] };
const icon = (name, size = 20) => {
  const pack = lacking[look.iconPack]?.includes(name) ? "lucide" : look.iconPack;
  return `<span class="icon" style="--i:url(icons/${pack}/${name}.svg);--s:${size}px"></span>`;
};
const art = size => `<span class="art" style="--a:${size}px">${icon("music", size * 0.4)}</span>`;

const row = t => `<button class="row ${current?.id === t.id ? "current" : ""}" data-track="${t.id}">${art(40)}<span class="meta"><b>${t.title}</b><small>${t.artist}</small></span><span class="dur">${t.duration}</span></button>`;
const head = (title, trailing = "") => `<div class="page-head"><h1>${title}</h1>${trailing}</div>`;
const vacancy = (ic, title, msg = "", action = "") => `<div class="vacancy">${icon(ic, 28)}<h2>${title}</h2>${msg ? `<p>${msg}</p>` : ""}${action}</div>`;
const group = (title, body) => `<div class="group"><div class="eyebrow">${title}</div><div class="panel">${body}</div></div>`;

function render() {
  tabBar.innerHTML = tabs.map(([id, ic, label]) => `<button data-tab="${id}" class="${id === tab ? "active" : ""}">${icon(ic)}<span>${label}</span></button>`).join("");
  if (tab === "home") {
    screen.innerHTML = head("Home") +
      `<div class="eyebrow">Quick picks</div><div class="picks">${tracks.slice(0, 6).map(t => `<button class="pick" data-track="${t.id}">${art(48)}<span>${t.title}</span></button>`).join("")}</div>` +
      `<div class="eyebrow">Recently added</div>${tracks.slice(-4).reverse().map(row).join("")}`;
  } else if (tab === "search") {
    screen.innerHTML = head("Search") +
      `<label class="field">${icon("search", 16)}<input type="search" placeholder="Songs, artists, and albums" aria-label="Search"></label><div id="results"></div>`;
    const results = document.querySelector("#results");
    const show = query => {
      const hits = tracks.filter(t => `${t.title} ${t.artist} ${t.album}`.toLowerCase().includes(query.toLowerCase()));
      results.innerHTML = hits.length ? `<div class="eyebrow">${query ? "Results" : "Songs"}</div>${hits.map(row).join("")}` : vacancy("search", "No matches");
    };
    show("");
    document.querySelector(".field input").addEventListener("input", e => show(e.target.value));
  } else if (tab === "library") {
    screen.innerHTML = head("Your Library", `<button class="ghost" id="add" aria-label="Import">${icon("plus")}</button>`) +
      (imported
        ? `<div class="library-head"><div><strong>Local Music</strong><small>${tracks.length} songs</small></div><button class="btn primary" data-track="1">${icon("play-filled", 14)}Play</button></div>${tracks.map(row).join("")}`
        : vacancy("file-music", "No songs yet", "Choose audio files stored on this iPhone or in iCloud Drive.", `<button class="btn primary" id="import">Import music</button>`));
    document.querySelector("#add").addEventListener("click", () => { imported = !imported; render(); });
    document.querySelector("#import")?.addEventListener("click", () => { imported = true; render(); });
  } else {
    const line = (a, b) => `<div class="setting"><span>${a}</span><span>${b}</span></div>`;
    const prov = (n, ic) => `<div class="setting provider">${icon(ic, 16)}<div><span>${n}</span><small>Native client required</small></div></div>`;
    const sub = settingsTab === "general"
      ? group("Providers", prov("Apple Music", "music") + prov("Spotify", "music") + prov("YouTube Music", "music") + prov("Deezer", "music") + prov("Subsonic / Navidrome", "disc-3")) +
        group("About", line("Sonora for iPhone", "0.1.0") + `<div class="about">A native Swift rewrite. The desktop Rust runtime is not embedded in this app.</div>`)
      : settingsTab === "playback"
        ? group("Playback", line("Audio engine", "AVPlayer") + line("Background audio", "Enabled"))
        : appearance();
    screen.innerHTML = head("Settings") +
      `<div class="strip">${["general", "appearance", "playback"].map(t => `<button data-stab="${t}" class="${t === settingsTab ? "active" : ""}">${title(t)}</button>`).join("")}</div><div class="pad">${sub}</div>`;
  }
}

const title = t => t[0].toUpperCase() + t.slice(1);
const opt = (text, detail, control, stacked = false) =>
  `<div class="opt ${stacked ? "stacked" : ""}"><div class="txt"><span>${text}</span>${detail ? `<small>${detail}</small>` : ""}</div>${control}</div>`;
const sw = key => `<button class="switch ${look[key] ? "on" : ""}" data-toggle="${key}" role="switch" aria-checked="${look[key]}"><i></i></button>`;
const seg = (key, values) => `<div class="seg">${values.map(v => `<button data-set="${key}:${v}" class="${look[key] === v ? "on" : ""}">${title(v === "base" ? "standard" : v)}</button>`).join("")}</div>`;
const faceName = v => ({ inter: "Default", system: "San Francisco" })[v] ?? title(v);
let openMenu = null;
const menu = (key, values, label) => `<div class="dd ${openMenu === key ? "open" : ""}">
  <button class="dd-trigger" data-dd="${key}" aria-haspopup="listbox" aria-expanded="${openMenu === key}" aria-label="${label}"><span>${key === "typeface" ? faceName(look[key]) : title(look[key])}</span>${icon("chevron-down", 14)}</button>
  <div class="dd-list" role="listbox">${values.map(v => `<button role="option" aria-selected="${look[key] === v}" data-set="${key}:${v}" class="${look[key] === v ? "on" : ""}"><span>${key === "typeface" ? faceName(v) : title(v)}</span>${look[key] === v ? icon("check", 14) : ""}</button>`).join("")}</div>
</div>`;
const swatches = () => `<div class="swatches">${themeNames.map(n => { const p = paletteOf(n); return `<button data-set="theme:${n}" class="${look.theme === n ? "on" : ""}" style="background:${p.bg};color:${p.fg}"><span class="dots"><i style="background:${p.primary}"></i><i style="background:${p.selection}"></i><i style="background:${p.muted}"></i></span>${title(n)}</button>`; }).join("")}</div>`;

function appearance() {
  return group("General",
      opt("Theme", "Choose the application colour palette", swatches(), true) +
      opt("Adaptive theme", "Tint the palette with the artwork of the playing album", sw("adaptive")) +
      opt("Icon pack", "Choose the icon set the interface draws from", menu("iconPack", ["lucide", "iconoir", "remix", "solar"], "Icon pack")) +
      opt("Blur UI", "Frost the player and tab bar over whatever they cover", sw("blur")) +
      opt("Corners", "How rounded surfaces and controls are", seg("corners", ["square", "subtle", "rounded", "round"]), true)) +
    group("Fullscreen",
      opt("Ambient background", "Fill the full-screen player with colours drawn from the cover", sw("ambient")) +
      (look.ambient ? opt("Ambient motion", "Drift the ambient colours instead of holding them still", sw("ambientMotion")) : "")) +
    group("Text",
      opt("Font size", "Base text size, everything else scales with it", `<div class="slider"><input type="range" min="12" max="20" step="1" value="${look.fontSize}" data-range="fontSize" aria-label="Font size"><span>${look.fontSize} px</span></div>`, true) +
      opt("Font", "The typeface Sonora uses across the interface", menu("typeface", ["inter", "system", "rounded", "serif", "monospaced"], "Font"))) +
    group("Motion",
      opt("Reduce motion", "Skip interface animations and transitions", sw("reduceMotion")) +
      opt("Animation speed", "How fast interface animations play", seg("pace", ["slow", "base", "quick"]), true)) +
    `<div class="pad0"><button class="btn secondary" id="reset-look">Reset appearance</button></div>`;
}

function renderPlayer() {
  if (!current) return;
  player.hidden = false;
  player.innerHTML = `<span class="line"></span>${art(44)}<span class="meta"><b>${current.title}</b><small>${current.artist}</small></span><button class="ghost toggle" aria-label="${playing ? "Pause" : "Play"}">${icon(playing ? "pause-filled" : "play-filled")}</button><button class="ghost next" aria-label="Next">${icon("skip-forward")}</button>`;
}

function showNowPlaying() {
  if (!current) return;
  nowPlaying.hidden = false;
  nowPlaying.innerHTML = `<div class="np-top"><button class="ghost close" aria-label="Close">${icon("chevron-down", 22)}</button><div class="eyebrow">Now Playing</div><span style="width:36px"></span></div>
    <div class="np-cover">${art(340)}</div>
    <div class="np-title"><h2>${current.title}</h2><p>${current.artist}</p></div>
    <div class="scrub"><div><i></i></div></div>
    <div class="times"><span>1:03</span><span>${current.duration}</span></div>
    <div class="transport"><button class="ghost dim">${icon("shuffle")}</button><button class="ghost previous">${icon("skip-back", 26)}</button><button class="play toggle" aria-label="${playing ? "Pause" : "Play"}">${icon(playing ? "pause-filled" : "play-filled", 26)}</button><button class="ghost next">${icon("skip-forward", 26)}</button><button class="ghost dim">${icon("repeat")}</button></div>`;
}

function select(id) {
  current = tracks.find(t => t.id === Number(id));
  playing = true;
  renderPlayer();
  render();
}

document.addEventListener("click", e => {
  const tabButton = e.target.closest("[data-tab]");
  const trackButton = e.target.closest("[data-track]");
  if (tabButton) { tab = tabButton.dataset.tab; render(); }
  if (trackButton) select(trackButton.dataset.track);
  if (e.target.closest(".toggle")) { playing = !playing; renderPlayer(); if (!nowPlaying.hidden) showNowPlaying(); }
  if (e.target.closest(".next") && current) { select(current.id % tracks.length + 1); if (!nowPlaying.hidden) showNowPlaying(); }
  if (e.target.closest(".previous") && current) { select((current.id + tracks.length - 2) % tracks.length + 1); showNowPlaying(); }
  if (e.target.closest(".close")) nowPlaying.hidden = true;
  const dd = e.target.closest("[data-dd]");
  if (dd) { openMenu = openMenu === dd.dataset.dd ? null : dd.dataset.dd; render(); return; }
  if (openMenu && !e.target.closest(".dd-list")) { openMenu = null; render(); }
  const stab = e.target.closest("[data-stab]");
  const toggle = e.target.closest("[data-toggle]");
  const setter = e.target.closest("[data-set]");
  if (stab) { settingsTab = stab.dataset.stab; render(); }
  if (toggle) { look[toggle.dataset.toggle] = !look[toggle.dataset.toggle]; refresh(); }
  if (setter) { const [k, v] = setter.dataset.set.split(":"); look[k] = v; openMenu = null; refresh(); }
  if (e.target.closest("#reset-look")) { Object.assign(look, defaults); refresh(); }
});
document.addEventListener("input", e => {
  const range = e.target.closest("[data-range]");
  if (range) { look[range.dataset.range] = Number(range.value); applyLook(); range.nextElementSibling.textContent = range.value + " px"; }
});
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => look.theme === "system" && refresh());

/** Re-applies the look and redraws every screen so icons and swatches follow it. */
function refresh() {
  applyLook();
  render();
  renderPlayer();
  if (!nowPlaying.hidden) showNowPlaying();
}

player.addEventListener("click", e => { if (!e.target.closest("button")) showNowPlaying(); });

applyLook();
render();
