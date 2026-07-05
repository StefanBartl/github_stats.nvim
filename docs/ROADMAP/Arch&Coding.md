# Architektur- & Coding-Regeln — angewendet auf github_stats.nvim

Quelle: [`Arch&Coding-Regeln.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md).
Diese Version bewertet github_stats.nvim konkret gegen die Regeln, statt sie
zu wiederholen. Die Quelldatei enthält außerdem einen großen, generischen
Abschnitt zu CPU-Zyklenkosten, GC-Tuning, Weak-Table-Memoization und
String/Table-Mikro-Benchmarks — das ist bei diesem Plugin (kleine JSON-Arrays,
kein Hot-Path, keine Millionen-Elemente-Schleifen) **nicht praktisch
relevant** und wird hier nicht dupliziert; siehe stattdessen den kurzen
Performance-Abschnitt unten.

**`lib.nvim`-Hinweis:** wie in [Zentral-Prinzipien.md](./Zentral-Prinzipien.md)
vermerkt — nicht genutzt, keine Annahme darüber getroffen.

---

## 1. Sicherheitsprinzipien & Fehlerbehandlung

| Regel | Befund |
|---|---|
| `pcall()` bevorzugt | ✅ konsequent in `config/init.lua`, `storage.lua`, `health.lua` |
| Type Guards & Literal Checks | 🟡 punktuell (`validate_repo_format`), nicht an jeder Config-Grenze |
| Explizite Rückgaben | ✅ `ok, err`-Konvention durchgängig |
| Kein `notify()` in Low-Level-Code | ✅ Notifications laufen über `config.notify()`, aufgerufen aus den Command-/Fetch-Schichten, nicht aus `storage.lua`/`api.lua` |
| Standardisiertes Error-Wrapping (`safe_call`) | ❌ nicht vorhanden — jede Funktion macht ihr eigenes `pcall` |
| Strukturierte Fehlertypen | ❌ nur Strings |
| `@error`/`@raises` Tags | ❌ nicht genutzt (siehe Annotations-Abschnitt) |
| Private Funktionen bleiben lokal | ✅ durchgängig `local function` für Interna |
| Argumente immer explizit übergeben + Type-Check | 🟡 Argumente werden übergeben, aber nicht überall mit `assert`/Type-Check abgesichert |

## 2. Modularisierung & Strukturprinzipien

| Regel | Befund |
|---|---|
| Modul = eine Verantwortung | ✅ (`config/`, `bindings/{usrcmds,keymaps,autocmds}`, `dashboard/{state,render,movement,actions,detail}`) |
| Reine Funktionen bevorzugt | 🟡 teilweise, gut in `analytics.lua` |
| Lokale statt globale Funktionen | ✅ |
| Entwurfsmuster wo sinnvoll | N/A — kein Bedarf an Singleton/Factory/Observer bei dieser Größe |
| Tools via Registry | N/A |
| Keine globalen States | 🟡 ein Global-Leak in dieser Session gefunden+gefixt (`dashboard/init.lua`) |
| Pure Functions | 🟡 s. o. |

## 3. Buffer- & Window-Management

| Regel | Befund |
|---|---|
| `local win/buf = ...` zuerst | ✅ |
| Immer `~= nil` & `nvim_*_is_valid()` | ✅ |
| Keine API-Calls ohne Prüfung | ✅ |
| Einheitliche UI-Methoden | ✅ `M.open`/`M.close`/`cleanup_dashboard` |
| Zustand zentral via `ui_state` | ✅ exakt dieses Muster |
| automatische `cleanup_all()` | ✅ vorhanden, in dieser Session als einziger kanonischer Teardown-Pfad konsolidiert (vorher gab es einen zweiten, kaputten Pfad über `M.close(_state)`) |

## 4. Methoden, Metatables & Datenmodelle

Metatables werden aktuell nirgends eingesetzt (keine `.add()`/`.clear()`-Objekte,
keine Ringbuffer, kein `__index`-Sharing). Bei der aktuellen Modulgröße ist das
kein Mangel — Getter/Setter-Module (`config`, `ui_state`, `dashboard_state`)
lösen dasselbe Problem einfacher. N/A bis auf Weiteres.

## 5. Dokumentation & Annotationen

| Regel | Befund |
|---|---|
| Einheitliche Datei-Tags (`@module`, `@brief`, `@description`) | ✅ |
| `@param`/`@return` pro Funktion | ✅ |
| Konsistentes Naming (englisch, snake_case) | ✅ |
| Explizite Typisierungen (`@alias`, `@field`) | ✅ (`@types/*.lua`) |
| `@see`-Verlinkung | ❌ nicht genutzt |
| `@error`/`@raises` | ❌ nicht genutzt — vertretbar, da Fehler durchgängig als zweiter Rückgabewert (`nil, err`) modelliert sind, nicht als `error()`/`raise` |
| Subverzeichnis → eigener `/types`-Ordner pro Ebene | ❌ **Gap.** Es gibt genau einen flachen `lua/github_stats/@types/`-Ordner für das ganze Plugin, nicht pro Subverzeichnis (`dashboard/`, `bindings/`, `state/`) einen eigenen. Bei der aktuellen Modulzahl (< 30 Dateien) ist das noch überschaubar; wird `dashboard/` weiter wachsen, lohnt sich ein `dashboard/@types/init.lua` nach dem in der Quelldatei gezeigten Gruppierungs-Stil (`--- ### Xy.lua`-Kommentarblöcke pro Quelldatei). |

Für Neovim-Config-Module gilt zusätzlich: README (deutsch) + `/doc/*.txt`
(englisch) pro Modul. Für ein eigenständiges Plugin-Repo wie github_stats.nvim
ist das nicht 1:1 anwendbar — hier ist README.md selbst schon englisch (Repo
ist öffentlich auf GitHub), `doc/github_stats.nvim.txt` existiert parallel.

## 6. Testbarkeit & Lesbarkeit

| Regel | Befund |
|---|---|
| Klein & fokussiert (SRP) | ✅ |
| Klarheit vor Kürze | ✅ |
| Testbarkeit durch Design | 🟡 kein DI, aber auch keine versteckten Abhängigkeiten — Module werden direkt `require()`t und in Tests per Monkey-Patch überschrieben |
| Snapshot-/Restore-Funktion | ❌ nicht vorhanden, kein Anwendungsfall |
| Separater Test-Entry | ❌ nicht vorhanden — Tests liegen unter `lua/github_stats/tests/**` als `busted`-Specs, aber es gibt keinen lokal lauffähigen `busted`-Runner/CI-Job, um sie zu verifizieren; einige Specs referenzieren nicht-existente Module (`dashboard.renderer`, `dashboard.navigator`) |

## 7. Fehlerbehandlung & Validierung (Sicherheit)

Kein `safe_call(fn, args)`-Wrapper, keine strukturierten Fehlertypen — s.
Abschnitt 1. Für den Fehlerraum dieses Plugins (Netzwerk/Token/Storage,
jeweils einmalig behandelt und dem Nutzer als Notification/Healthcheck-Zeile
gezeigt) bisher ohne erkennbaren Nachteil.

## 8–10. Performance, Speicher, Cache, Weak Tables/Memoisierung

**Nicht praktisch relevant bei aktueller Größenordnung.** Die im
Quelldokument behandelten Techniken (Tabellen-Vorreservierung,
`table[i]`-Befüllung, Weak-Table-Caches, GC-Tuning, Coroutine-Recycling)
zielen auf Hot-Paths mit tausenden bis Millionen Iterationen. github_stats.nvim
verarbeitet pro Repo/Metrik üblicherweise Dutzende bis wenige Hundert
Tageswerte, async über `vim.system`, ohne `CursorMoved`/`TextChanged`-Handler.
Was tatsächlich schon angewendet wird und sinnvoll ist:

- `table.concat` statt `..`-Verkettung in Schleifen: ✅ genutzt in
  `storage.lua`, `config/init.lua`, `analytics.lua`.
- Debounced Writes/Renders: ✅ Dashboard-Rendering ist debounced
  (`dashboard/init.lua:20`, `RENDER_DEBOUNCE_MS = 50`).
- Async statt Blocken: ✅ `vim.system` überall statt `vim.fn.system`
  (blockierend) für API-Calls.

Tabellen-Vorreservierung, Weak-Caches, explizites `collectgarbage()`-Tuning:
❌ nicht genutzt, aktuell ohne belegten Bedarf.

## 11. Spezialfälle

Dual Representation, Defaultwerte über Metatable, FIFO/History mit Limits,
geteilte Logik via `__index`: N/A — keiner dieser Fälle kommt im aktuellen
Feature-Umfang vor (keine begrenzten Historien-Listen, keine Objekt-Defaults
über Metatables).

## MISC — Cross-Plattform

✅ Explizit umgesetzt: `health.lua`s `command_exists()` unterscheidet
Windows (PowerShell `Get-Command`, Fallback-Direktausführung) von Unix
(`command -v`); README dokumentiert Storage-Pfade separat für
Linux/macOS/Windows.

## Annotations-Regeln

Bereits oben unter Abschnitt 5 bewertet. Zusätzlich zur dortigen Bewertung:
das `#`-Präfix-Konvention für Kommentare in `@alias`/`@return`-Zeilen wird
nicht durchgängig genutzt (z. B. `---@return boolean, string?  # Success flag, error message`-Stil
kommt vor, ist aber nicht überall identisch formatiert) — kosmetisch, keine
funktionale Auswirkung.

## (Direkt-)Importe vs. Alias

Die Quelldatei zeigt Benchmarks: `local fn = mod.fn` lohnt sich nur in
Tight-Loops mit ≥ 100k Aufrufen; `vim.fn`/`vim.api` direkt vs. aliasiert macht
keinen messbaren Unterschied; `require(...).fn` vs. gespeicherte Referenz ist
irrelevant unter ~1M Aufrufen. github_stats.nvim hat keine solchen Loops —
lokale Aliase wie `local fn = vim.fn` (in `config/init.lua`, `health.lua`)
sind vorhanden, aber eher aus Lesbarkeits- als aus Performance-Gründen
gerechtfertigt, und das ist hier die richtige Motivation.

## Importreihung

Empfohlene Reihenfolge: System/Kern → Debug/Notify → Config/Utility → State →
UI → Controller → Keymaps. In der Praxis (z. B.
[`bindings/keymaps.lua`](../../lua/github_stats/bindings/keymaps.lua)):
`config` → `config.DEFAULTS` → `dashboard_state` → `movement` → `render` →
`ui_state` → `detail` → `actions` — folgt der Empfehlung im Kern (Config vor
State vor UI vor Controller-artigen Modulen), auch wenn nicht strikt nach
diesem exakten Kategorienschema benannt. 🟡 gut genug, keine Umsortierung nötig.

## Tables / Strings

- `table.insert` ohne Reserve wird an mehreren Stellen genutzt
  (`build_entry`/`build_lines` in `dashboard/render.lua`, `fetcher.lua`s
  Success/Error-Listen) — bei Listengrößen im niedrigen zweistelligen Bereich
  (Anzahl Repos, Anzahl Zeilen pro Eintrag) ist der Unterschied zu `t[i] = v`
  nicht messbar. Kein Handlungsbedarf.
- String-Verkettung in Schleifen wird vermieden; `string.format` und
  `table.concat` sind die durchgängig genutzten Bausteine.

## `types-file`-Demo

Siehe Gap unter Abschnitt 5 (Dokumentation) — flacher statt pro-Ebene
`@types`-Ordner. Der in der Quelldatei gezeigte Gruppierungs-Stil
(`--- #### Xy.lua`-Kommentarblöcke innerhalb einer `types/init.lua`) ist eine
gute Vorlage, falls/wenn dieser Ordner pro Subverzeichnis aufgesplittet wird.

---

## Fazit

github_stats.nvim erfüllt die praktisch relevanten Sicherheits-, Struktur- und
Dokumentations-Regeln bereits weitgehend (Fehlerbehandlung, Buffer/Window-
Management, UI-State, Annotationen). Die drei konkreten, umsetzbaren Lücken:

1. **Kein Formatter/Linter** (stylua/luacheck) im Repo/CI — siehe
   [Checklist.md](./Checklist.md#7-tooling).
2. **Flacher statt geschachtelter `@types`-Ordner** — nur relevant, falls
   `dashboard/` oder `bindings/` deutlich weiterwachsen.
3. **Tests referenzieren teils nicht-existente Module** und es gibt keinen
   lauffähigen Test-Runner lokal/in CI — siehe
   [Checklist.md](./Checklist.md#schnell-check-10-punkte), Punkt 9.

Alles andere (Performance-Mikro-Optimierung, Weak Tables, strukturierte
Fehlertypen, Metatable-Patterns) ist bei der aktuellen Größe und I/O-Last des
Plugins nicht gerechtfertigt und wird bewusst nicht als offene Aufgabe
geführt.
