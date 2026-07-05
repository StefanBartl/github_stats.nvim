# Zentrale Prinzipien — angewendet auf github_stats.nvim

Quelle: [`Zentrale-Prinzipien.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md)
(generische 10-Punkte-Selbstprüfung pro Modul). Dieses Dokument bewertet
github_stats.nvim konkret gegen die 10 Punkte, statt die generische Liste zu
wiederholen.

**Hinweis zu `lib.nvim`:** Die Quell-Checkliste verlangt durchgängig
`StefanBartl/lib.nvim` (`lib.notify`, `lib.map`, `lib.cross`, `lib.lazy`,
`lib.memo`, ...). github_stats.nvim hat **keine** Abhängigkeit zu `lib.nvim` —
das Plugin bringt eigene, funktional äquivalente Bausteine mit
(`config.notify`, `bindings/keymaps.lua`, cross-platform-Checks in
`health.lua`). Ob `lib.nvim` nachträglich eingeführt wird, ist eine separate
Architekturentscheidung, keine stillschweigende Annahme dieses Dokuments.

---

## 1. Events bündeln, Logik entkoppeln

Es gibt genau **einen** eigenen `nvim_create_autocmd`-Aufruf-Ort für
Plugin-Lifecycle-Events: [`bindings/autocmds.lua`](../../lua/github_stats/bindings/autocmds.lua)
(`VimEnter` → Auto-Fetch + optionales Dashboard-Auto-Open). Zwei weitere,
bewusst *nicht* zentralisierte Autocmds sind buffer-scoped und an die
Dashboard-Instanz gebunden (`BufWipeout` in `dashboard/init.lua`), siehe
[docs/BINDINGS.md](../BINDINGS.md#autocmds) für die Begründung. **Kein**
Duplizieren von Event-Bindungen über mehrere Module hinweg. ✅

## 2. Eigene Logik lazy laden

Kein eigenes Lazy-Loading *innerhalb* des Plugins nötig — die
Empfehlung betrifft primär die Ladezeit-Strategie der Neovim-Config
(`lazy.nvim`-Spec), die in [README.md](../../README.md#installation) explizit
mit `event = "VimEnter"` (empfohlen) vs. `lazy = false` dokumentiert ist. Innerhalb
des Plugins werden Submodule ohnehin erst bei tatsächlichem Gebrauch per
`require()` geladen (kein Eager-Require aller Submodule in `init.lua`, bis auf
die im `M.setup()`-Pfad ohnehin benötigten). ✅

## 3. Kontext statt Mehrfach-API-Zugriffe

`GHStats.DashboardState` (siehe [`dashboard/state.lua`](../../lua/github_stats/dashboard/state.lua))
ist genau so ein Kontext-Objekt: Repos, Cursor-Index, Scroll-Offset,
Fenstergröße etc. werden einmal zentral gehalten und von `render.lua`,
`movement.lua`, `bindings/keymaps.lua` referenziert statt wiederholt einzeln
abgefragt. ✅

## 4. Autocommand-Gruppen sauber nutzen

`bindings/autocmds.lua` nutzt `vim.api.nvim_create_augroup("GithubStatsAutoFetch", { clear = true })`
— klar benannt, `clear = true` erlaubt sauberes Reload ohne Neustart. ✅

## 5. Event oder Command?

Die meisten Aktionen sind explizite `:GithubStats*`-Commands (Fetch, Show,
Export, Diff, Dashboard, ...), nicht automatisch an Events gebunden — passt
zum Grundsatz "nur automatisch, was wirklich automatisch sein soll". Die
einzige automatische Aktion ist der tägliche Auto-Fetch auf `VimEnter`
(zustandsgetrieben: `fetch_interval_hours`), was explizit so gewünscht ist. ✅

## 6. Treesitter notwendig oder nicht?

Nicht anwendbar — github_stats.nvim parst keinen Buffer-Inhalt, nur JSON aus
der GitHub-API. N/A.

## 7. Cache vorhanden und explizit?

Kein reiner In-Memory-Cache, aber ein expliziter, persistenter
Daten-Cache: `~/.config/nvim/github-stats/data/**/*.json`
([`storage.lua`](../../lua/github_stats/storage.lua)) plus
`last_fetch.json` zur Intervall-Steuerung. Regenerierbar (force-fetch),
invalidierbar (einfach löschen). Liegt allerdings nicht in
`stdpath("cache")`, sondern in `stdpath("config")` — bewusst so, weil es
*Nutzdaten* sind (historische Traffic-Daten), kein Wegwerf-Cache; siehe
README-Abschnitt "Why use config.json?". 🟡 (Abweichung von der Checkliste ist
hier inhaltlich begründet, nicht übersehen.)

## 8. Allokationen im Hot-Path vermeiden

Kein echter Hot-Path (kein `CursorMoved`/`TextChanged`-Handler). Der
"heißeste" Pfad ist das Dashboard-Rendering (`render.lua`), debounced auf
50ms ([`dashboard/init.lua:20`](../../lua/github_stats/dashboard/init.lua)).
Dort werden pro Render neue Tabellen für die Zeilen gebaut — bei realistischen
Repo-Zahlen (< 100) irrelevant; keine Optimierung nötig. N/A bei aktueller
Größenordnung.

## 9. Debugbarkeit eingeplant?

`:GithubStatsDebug` Command zeigt Config-Status, Token-Verfügbarkeit,
letzten Fetch-Summary inkl. Fehlerdetails. `:checkhealth github_stats` deckt
Config/Token/curl/Storage/API-Konnektivität ab. Kontrollfluss ist über
`ok, err`-Rückgaben durchgängig nachvollziehbar. ✅

## 10. Laufzeit wichtiger als Startup?

Es gibt keinen `CursorMoved`/`TextChanged`/`BufEnter`-Handler — Startup-Kosten
sind daher die relevantere Achse, und die ist bereits durch die
`event = "VimEnter"`-Empfehlung plus internes `vim.defer_fn(..., 1000)` beim
Auto-Fetch adressiert (siehe `bindings/autocmds.lua`). ✅

---

## Kurzform (mental) — Fazit

- **Wann läuft es?** Auf explizitem Command, oder einmal täglich auf
  `VimEnter` (deferred).
- **Muss es jetzt laufen?** Ja für Commands; der Auto-Fetch ist bewusst
  deferred und intervall-gated.
- **Lädt es mehr als nötig?** Nein, Submodule werden bei Bedarf geladen.
- **Läuft es öfter als nötig?** Rendering ist debounced.
- **Wird Arbeit wiederholt?** Nein — z. B. das Dashboard-Sortieren fragt
  Stats einmal pro Render ab, nicht pro Vergleich.
- **Ist der Datenfluss klar?** Ja: `config` → `fetcher`/`analytics` → `storage`
  → `dashboard/render` — jede Schicht hat eine klare Richtung.
