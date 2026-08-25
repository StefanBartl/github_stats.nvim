# PR/Architektur-Checkliste — angewendet auf github_stats.nvim

Quelle: [`regeln/`](../../../WKDBooks/Development/wkdbook-Lua/Checklists/regeln/)
(Lua/Neovim-Architektur-, Performance- und Codierungs-Checkliste). Dieses
Dokument wendet die **praktisch relevanten** Abschnitte konkret auf
github_stats.nvim an. Die Abschnitte zu Sortieralgorithmen, klassischen
Datenstrukturen (AVL/Red-Black/B-Bäume/Skip-Lists/Tries/Bloom-Filter/
Union-Find/...), Bitoperationen und Zeitkomplexitäts-Notation sind **nicht
enthalten** — sie betreffen generische CS-Grundlagen, nicht dieses konkrete
Plugin. github_stats.nvim verarbeitet kleine, JSON-basierte Datenmengen
(wenige Repos × wenige hundert Tageswerte); an dieser Größenordnung ist keine
der dort behandelten Techniken (Radix Sort, B-Bäume, Bloom-Filter, ...)
gerechtfertigt.

> The source checklists (`Arch&Coding-Regeln.md`, `Checklist.md`,
> `Zentrale-Prinzipien.md`) were retired: they were absorbed into the rule
> collection under `WKDBooks/Development/wkdbook-Lua/Checklists/`, which is
> now the canonical one. The links above point there.


---

## Schnell-Check (10 Punkte)

| # | Prüfschritt | Status | Befund |
|---|---|---|---|
| 1 | Fehlerbehandlung (pcall/xpcall) | ✅ | Durchgängig: `config/init.lua`, `storage.lua`, `health.lua` kapseln riskante Calls in `pcall`. |
| 2 | Type Guards | 🟡 | Teilweise (`validate_repo_format` in `health.lua`), nicht an jeder Grenze. Kein systematisches `type(...)`-Gate für alle Konfig-Keys. |
| 3 | Buffer/Window validieren | ✅ | `ui_state.lua` prüft `nvim_buf_is_valid`/`nvim_win_is_valid` vor jeder Operation; `dashboard/init.lua` ebenso. |
| 4 | Keine globalen States | 🟡 | Grundsätzlich sauber (Modul-lokaler State + Getter/Setter in `config`, `dashboard_state`, `ui_state`). In dieser Session wurde jedoch ein echter Global-Leak in `dashboard/init.lua` gefunden und gefixt (fehlendes `local` nach Entfernen einer Modul-Variable) — Lua-LS-Diagnostics (`lowercase-global`) haben ihn sofort angezeigt; genau der Mechanismus, den dieser Check absichern soll. |
| 5 | Single Responsibility | ✅ | Klare Modulgrenzen: `config/`, `bindings/{usrcmds,keymaps,autocmds}`, `dashboard/{state,render,movement,actions,detail}`, `@types/`. |
| 6 | UI-Cleanup (`cleanup_all()`) | ✅ | `ui_state.cleanup_all()` + `dashboard/init.lua`s `cleanup_dashboard()`; in dieser Session wurde `M.close()` genau darauf vereinheitlicht (vorher zwei divergierende Teardown-Pfade, einer davon crash-anfällig). |
| 7 | Performance-Hotspots (`table.concat`, Vorreservierung) | 🟡 | `table.concat` wird genutzt (`storage.lua`, `analytics.lua`); Tabellen-Vorreservierung nirgends — bei den tatsächlichen Datenmengen (≤ einige hundert Einträge) kein messbarer Effekt zu erwarten. |
| 8 | Annotationen vollständig | ✅ | `@module`/`@brief`/`@description` konsequent pro Datei, `@param`/`@return` an praktisch jeder Funktion. |
| 9 | Testbarkeit | ✅ | Tests vorhanden (`TESTS/**`), `scripts/test.sh` läuft sie über einen echten `busted`/`plenary`-Runner (`scripts/minimal_init.lua`, `.deps/lib.nvim` + `.deps/plenary.nvim` in CI). Volle Suite grün (54/54) — dabei zwei echte Bugs aufgedeckt und gefixt: `date_presets.lua`'s `M.list()`/`M.resolve()` behandelten "config.init() noch nicht gelaufen" wie "Presets deaktiviert" statt (wie `get_retention()`/`get_notification_level()` es bereits tun) auf `DEFAULT_CONFIG` zurückzufallen; ein Sparkline-Test verwechselte Byte- mit Zeichenlänge (`#sparkline` bei 3-Byte-UTF-8-Zeichen). |
| 10 | Import-Reihenfolge | 🟡 | Nicht strikt System→Debug→Utils→State→UI→Controller→Keymaps, aber konsistent und nachvollziehbar pro Datei (z. B. `bindings/keymaps.lua`: config → state → movement/render → ui_state → detail → actions). |

**Bonuspunkt `lib.nvim`:** ✅ genutzt (`dependencies = { "StefanBartl/lib.nvim" }`;
`lib.nvim.notify`, `lib.nvim.map`, `lib.nvim.window`, `lib.nvim.cross.executable`,
`lib.nvim.net.curl`, `lib.nvim.fs.json`, `lib.nvim.usercmd.composer`, `lib.nvim.ui.kit.note`,
`lib.lua.strings.format`, `lib.lua.tables` across most of the plugin — see
[`regeln/LUA_NVIM.md`](../../../WKDBooks/Development/wkdbook-Lua/Checklists/regeln/LUA_NVIM.md#libnvim-verwenden)). The
note in [Zentral-Prinzipien.md](./Zentral-Prinzipien.md) predates this and is stale.

---

## PR-Review-Checkliste (angewendet)

### 1. Sicherheit und Fehlerbehandlung

- ✅ Explizite `ok, err`-Rückgaben statt stiller Fehler (`config.init`,
  `storage.write_metric`, alle `health.lua`-Checks).
- ❌ Keine strukturierten Fehlertypen (`InvalidStateError` o. ä.) — Fehler sind
  einfache Strings. Für die Fehlerbandbreite dieses Plugins (Netzwerk/Token/
  Storage-Fehler, alle terminal und einmalig behandelt) bisher kein
  praktischer Nachteil aufgefallen.
- ✅ Guards vor API-Zugriffen vorhanden, wo API-Aufrufe fehlschlagen können.

### 2. Modularität und Struktur

- ✅ Single Responsibility eingehalten.
- 🟡 Keine Globals — bis auf den in dieser Session gefundenen/gefixten
  Global-Leak (s. o.).
- ✅ Interne Helfer sind `local function`, nicht exportiert.
- ✅ `/config`-Ordner mit `/config/DEFAULTS.lua` — in dieser Session umgesetzt
  (`config/init.lua` + `config/DEFAULTS.lua`).
- N/A Tools/Registry-Pattern — kein Anwendungsfall (kein Plugin-internes
  Tool-System).

### 3. Buffer-/Window-Management

- ✅ Handle-first-then-check (`create_dashboard_buffer`/`create_dashboard_window`).
- ✅ Gültigkeit vor jedem API-Call geprüft.
- ✅ Einheitliche, benannte Lifecycle-Funktionen (`M.open`, `M.close`,
  `cleanup_dashboard`).
- 🟡 Race Conditions: der einzige `vim.schedule`-Callback mit Buffer-Bezug
  (`dashboard/init.lua`s Force-Refresh-Callback) prüft vor dem Re-Render
  erneut, ob überhaupt noch ein Dashboard-State existiert — aber validiert
  nicht explizit Buffer/Fenster-Handle an dieser Stelle selbst (verlässt sich
  auf `render_dashboard()`s eigene `buf`/`win`-Prüfung über `ui_state.get_buf_win()`,
  was im Ergebnis gleichwertig sicher ist).

### 4. UI-State-Management

- ✅ `ui_state.lua` ist exakt das geforderte Muster: zentraler State,
  Getter/Setter statt Direktzugriff.
- ❌ Kein Snapshot/Restore — für Dashboard-UI-Zustand bislang nicht
  benötigt (kein Undo-Feature vorgesehen).

### 5. Dokumentation und Annotationen

- ✅ Kopf-Tags durchgängig.
- ✅ Funktions-Tags durchgängig (`@param`, `@return`).
- ✅ Eigene `@types/`-Ordner-Struktur, jetzt **pro Subverzeichnis**
  (`dashboard/@types/`, `state/@types/`, Root-`@types/` für das
  Modulübergreifende) statt eines einzigen flachen Ordners. Siehe
  `Arch&Coding.md`.

### 6. Testbarkeit und Lesbarkeit

- 🟡 Keine echte Dependency Injection (Module werden direkt per `require()`
  geholt, nicht injiziert) — für die Größe des Projekts akzeptabel, macht
  aber Mocking in Tests umständlicher (die vorhandenen Tests behelfen sich
  mit direktem Monkey-Patching von `config.get`/`config.get_repos`).
- ✅ Mehrere reine Funktionen vorhanden (`analytics.lua`s Aggregationslogik).
- ✅ Separater Test-Entrypoint: `scripts/test.sh` (busted/plenary via
  `scripts/minimal_init.lua`), volle Suite grün (54/54).

### 7. Tooling

- ✅ `.luarc.json` vorhanden mit `diagnostics.globals = ["vim", "describe", "it", ...]`
  und `workspace.library` für `luv`/`busted`.
- ✅ `stylua.toml` und `.luacheckrc` vorhanden; `stylua --check .` und
  `luacheck .` laufen beide grün. `.github/workflows/ci.yml` setzt beide
  sowie `scripts/test.sh` auf jedem Push/PR durch — vorher war keiner der
  drei automatisiert, jetzt alle drei.

---

## Anti-Pattern-Check

| Muster | Befund |
|---|---|
| Globaler State | 🟡 einmal gefunden & gefixt in dieser Session (s. o.), sonst sauber |
| API ohne Guards | ✅ nicht beobachtet |
| String-Concat im Loop | ✅ nicht beobachtet (durchgängig `string.format`/`table.concat`) |
| Closures im Loop | ✅ nicht beobachtet |
| Viele kleine temporäre Tabellen | N/A bei aktueller Datengröße |

## Import- und Dateistruktur-Check

| Punkt | Befund |
|---|---|
| Import-Reihenfolge | 🟡 nicht strikt normiert, aber konsistent |
| Datei-Header | ✅ vorhanden |
| Typ-Ablage (`@types`-Ordner) | ✅ pro Subverzeichnis (`dashboard/@types/`, `state/@types/`, Root für Modulübergreifendes) — siehe `Arch&Coding.md` |
