# Konzept — github_stats.nvim besser machen

Stand: 2026-08-23. Ausgangsfrage: *"Was fehlt dem Plugin wirklich?"* — nicht
als Wunschliste, sondern als Ergebnis eines Durchgangs durch den aktuellen
Quellstand. Jeder Befund unten ist am Code belegt (Datei/Funktion genannt);
spekulative Features ohne Befund gehören weiterhin nach
[`IDEAS/IDEAS.md`](IDEAS/IDEAS.md), nicht hierher.

Abgrenzung zu den Nachbardokumenten:

- [`FEATURES.md`](../FEATURES.md) — was **ist**.
- [`ROADMAP.md`](../ROADMAP.md) — was **offen und beschlossen** ist.
- [`IDEAS/IDEAS.md`](IDEAS/IDEAS.md) — was **denkbar** ist, ohne Entscheidung.
- Dieses Dokument — **warum** die nächsten Schritte diese und nicht andere
  sein sollten, mit Aufwand und Risiko pro Punkt.

---

## Inhaltsverzeichnis

- [Leitgedanke](#leitgedanke)
- [P0 — Dokumentiert, aber nicht vorhanden](#p0--dokumentiert-aber-nicht-vorhanden)
- [P1 — Substanz](#p1--substanz)
- [P2 — Wahrnehmbare Qualität](#p2--wahrnehmbare-qualität)
- [P3 — Genauigkeit im Detail](#p3--genauigkeit-im-detail)
- [Ausdrücklich nicht vorgeschlagen](#ausdrücklich-nicht-vorgeschlagen)
- [Empfohlene Reihenfolge](#empfohlene-reihenfolge)

---

## Leitgedanke

Das Plugin sammelt zuverlässig und speichert sauber — Fetch, Storage,
Retention und Export sind belastbar und getestet. Die Schwächen liegen fast
alle an **einer** Stelle: zwischen "Daten liegen auf Platte" und "der Mensch
vor dem Bildschirm versteht sie". Genau dort setzen P0–P2 an.

Der zweite Auftrag dieser Sitzung — die maximale Zeitdauer im Dashboard
einstellbar zu machen (`max`, Taste `m`, aufgelöste Spanne in der Kopfzeile) —
ist bereits umgesetzt und gehört zur selben Klasse: die Daten waren da, die
Antwort auf "wie viel Historie sehe ich eigentlich?" nicht.

Zweiter Leitgedanke: **kein neuer API-Verkehr**. Alle Vorschläge unten
arbeiten auf bereits geholten Daten. Das GitHub-Traffic-API liefert ein
rollierendes 14-Tage-Fenster; der Wert des Plugins entsteht aus der lokal
aufgebauten Historie, nicht aus häufigerem Abfragen.

---

## P0 — Dokumentiert, aber nicht vorhanden

### 1. Dashboard-Auto-Refresh gibt es nicht — ✅ erledigt

> **Umgesetzt.** `dashboard/init.lua`s `start_auto_refresh()` startet den
> Timer beim Öffnen, rendert nur neu (fetcht nicht), und wird über den
> bestehenden `clear_state()`-Pfad beendet. Vier Specs decken „positiv",
> „`0` deaktiviert", „kein Zahlenwert wird ignoriert" und „Timer wird beim
> Schließen geschlossen" ab.

**Befund.** `dashboard.refresh_interval_seconds` ist in
[`config/DEFAULTS.lua`](../../lua/github_stats/config/DEFAULTS.lua) mit `300`
vorbelegt, in [`health.lua`](../../lua/github_stats/health.lua) validiert
(muss Zahl sein, `>= 10`), in `DashboardConfig` typisiert und in
[`DASHBOARD.md`](../DASHBOARD.md) als konfigurierbares Feature dokumentiert —
und `dashboard/state.lua` hält sogar ein Feld `auto_refresh_timer` samt
Aufräumpfad in `clear_state()`. **Niemand startet den Timer.** Eine Suche über
`lua/` findet keinen einzigen schreibenden Zugriff auf `auto_refresh_timer`
außer dem Aufräumen.

**Warum P0.** Das ist kein fehlendes Feature, sondern eine falsche Zusage: Wer
den Wert konfiguriert, bekommt schweigend nichts. Die teuerste Sorte Bug — er
sieht aus wie ein funktionierendes Feature.

**Vorschlag.** Timer in `dashboard/init.lua`s `M.open()` starten, wenn
`refresh_interval_seconds > 0`, `vim.schedule_wrap`-gehüllt, und nur
**re-rendern**, nicht fetchen — Fetch bleibt an `R`/`f` und das
Fetch-Intervall gebunden, sonst brennt ein offen stehendes Dashboard das
Rate-Limit ab. Beendet wird er über den bereits existierenden
`clear_state()`-Pfad. `0` deaktiviert, wie dokumentiert.

**Aufwand.** Klein (≈ 30 Zeilen + ein Spec). **Risiko.** Gering — der
Teardown-Pfad existiert bereits und ist genau die Stelle, an der ein
Timer-Leak sonst entstünde.

---

## P1 — Substanz

### 2. Jeder Tastendruck liest die gesamte Historie neu von der Platte

**Befund.** `dashboard/render.lua`s `build_lines()` ruft pro Render für
**jedes** Repository `analytics.query_metric()` zweimal auf (clones + views);
jeder dieser Aufrufe geht über `storage.read_metric_history()`, das das
komplette Metrik-Verzeichnis auflistet und **jede** Datei liest und
JSON-dekodiert. Bei 12 Repos × 2 Metriken × (Archiv + n Tagesdateien) ist das
der Preis für ein einzelnes `j`. Gebremst wird das nur durch
`RENDER_DEBOUNCE_MS = 50` — das begrenzt die Frequenz, nicht die Kosten.

**Vorschlag.** Ein Lese-Memo in `analytics` oder `storage`, geschlüsselt über
`(repo, metric)`, invalidiert von genau drei Ereignissen: erfolgreicher
Fetch, Retention-Lauf, und die manuelle Neuzeichnung `r` — die damit erstmals
wirklich *etwas* tut, das `j` nicht auch tut, und ihre dokumentierte Bedeutung
"neu von Platte" behält. Bewusst **kein** TTL: eine Zeitgrenze wäre die vierte
Wahrheit über Datenaktualität neben Fetch-Intervall, Retention und
Auto-Refresh.

**Aufwand.** Mittel. **Risiko.** Mittel — Cache-Invalidierung ist die Stelle,
an der "warum sehe ich alte Zahlen?"-Fehler entstehen. Deshalb: wenige,
explizite Invalidierungspunkte statt Heuristik, und ein Spec pro Punkt.

### 3. Der Trend-Indikator misst etwas anderes, als der Nutzer denkt — ✅ erledigt

> **Umgesetzt, Variante (a).** `analytics.trend_over(daily, window, ref?)`
> vergleicht die letzten N vollständigen Tage mit den N davor, unabhängig vom
> angezeigten Bereich; `dashboard.trend_window_days` (Default 7) stellt N ein,
> die Kopfzeile nennt es (`Trend:7d/7d`). Gemessen wird ab **gestern** — heute
> fällt aus jeder Aggregation heraus, ein Anker auf heute hätte sechs Tage
> gegen sieben gestellt und einen Rückgang erfunden, der nur der Uhr gehört.
> Beide Fenstergrenzen sind datums- statt abzählbasiert und werden von einem
> Mittags-Anker aus gesetzt, damit fehlende Tage sie nicht verschieben und
> eine Sommerzeitgrenze sie nicht um einen Tag versetzt. Neu ist außerdem
> `⬌ n/a` für „in beiden Fenstern nichts“ — nicht dasselbe wie `⬌ 0%`.

**Befund.** `compute_trend()` in `dashboard/render.lua` halbiert das
**gefilterte** Fenster und vergleicht die Summe der zweiten mit der Summe der
ersten Hälfte. Bei `Range:7d` heißt das "letzte 3–4 Tage vs. die davor" —
plausibel. Bei `Range:max` und einem Jahr Historie ist derselbe Pfeil
"zweites Halbjahr vs. erstes Halbjahr". Beides erscheint als `⬆ +67%`, ohne
Hinweis worauf es sich bezieht. Zusätzlich zählt nur `clones`, obwohl in
derselben Zeile auch `views` steht.

**Warum das jetzt wichtiger wird.** Mit der neuen `max`-Spanne wird der
bereichsabhängige Trend deutlich sichtbarer als vorher, wo `all` selten
gewählt wurde.

**Vorschlag** (zwei Varianten, bewusst gegeneinander gestellt):

a) **Fenster fixieren** — Trend immer "letzte 7 Tage vs. die 7 davor",
   unabhängig vom Anzeigebereich. Vorhersagbar, über Repos vergleichbar,
   sortierbar. Nachteil: entkoppelt vom sichtbaren Zeitraum.
b) **Bezug sichtbar machen** — Fenster bleibt relativ, aber die Kopfzeile
   benennt es (`Trend: 2. Hälfte vs. 1. Hälfte`).

Empfehlung: **(a)**, mit dem verwendeten Fenster in der Kopfzeile. Die
Sortierung `sort_by = "trend"` ist nur dann sinnvoll, wenn alle Zeilen
dasselbe messen.

**Aufwand.** Klein. **Risiko.** Gering, aber es ist eine *Verhaltens*änderung
an einer sichtbaren Zahl → changelog-pflichtig.

### 4. Die Testabdeckung endet vor der Darstellung — ✅ erledigt

> **Umgesetzt.** `tests/dashboard_render_spec.lua`, 13 Specs über den
> gerenderten Puffer: Zeilenbudget gegen `HEADER_LINES`/`ENTRY_LINES`,
> Index↔Zeile als Rundreise, gleiche Rahmenbreite aller Kopfzeilen,
> Sort/Range-Anzeige, Tastenhinweise bei Remap und bei `""`, Auswahlmarke.
> Bewusst über `dashboard.open()` statt über Test-Exports der lokalen
> `build_lines`/`build_header` — eine nur für den Test eingezogene Naht kann
> grün sein, während der echte Renderpfad kaputt ist.
>
> Hat prompt zwei echte Fehler gefunden: `query_metric` gibt für ein
> Repository ohne gespeicherte Dateien den *angefragten* Zeitraum als
> `period_start`/`period_end` zurück — Kopfzeile und `Period:`-Zeile haben
> das für bare Münze genommen und einen Zeitraum für Daten behauptet, die es
> nicht gibt. Beide fragen jetzt `has_days()` (leeres `daily_breakdown`).

**Befund.** Specs decken `analytics`, `config`, `date_presets`, `export`,
`retention` und einen Dashboard-Flow ab. Ungetestet sind ausgerechnet die
Module, in denen die letzten echten Bugs saßen: die Zeilenarithmetik in
`dashboard/state.lua` / `movement.lua` (der `* 6`- bzw. `2 + 3*N`-Vorfall)
und `build_lines()` / `build_header()` selbst.

**Vorschlag.** `build_lines()` ist eine reine Funktion von (State, Stats) →
`string[]` und damit ohne Fenster testbar: Kopfzeilenhöhe gegen
`HEADER_LINES`, Eintragshöhe gegen `ENTRY_LINES`, Rahmenbreite, sowie
`get_repo_line()` / `get_repo_from_line()` als Rundreise über alle Indizes.

**Aufwand.** Klein bis mittel. **Risiko.** Keins.

---

## P2 — Wahrnehmbare Qualität

### 5. Das Dashboard hat keine einzige Hervorhebung

**Befund.** Im gesamten `lua/`-Baum gibt es keinen Aufruf von
`nvim_buf_add_highlight`, `nvim_buf_set_extmark` oder `nvim_set_hl` und kein
`hl_group`. Der Dashboard-Puffer ist monochromer Text; die Option `theme` ist
in `DASHBOARD.md` ausdrücklich als "reserved for future use" markiert. Farbe
trägt damit null Information — weder steigend/fallend, noch Auswahl, noch
"keine Daten".

**Vorschlag.** Ein kleiner, benannter Satz Highlight-Gruppen
(`GithubStatsTrendUp`, `GithubStatsTrendDown`, `GithubStatsHeader`,
`GithubStatsSelected`, `GithubStatsMuted`), per `default = true` an vorhandene
Standardgruppen gelinkt (`DiagnosticOk` / `DiagnosticError` / `Title` /
`CursorLine` / `Comment`), gesetzt über Extmarks beim Rendern. Kein eigenes
Theme-System — `theme` bliebe reserviert. Farbschema-unabhängig und vom Nutzer
mit einem `:hi link` überschreibbar.

**Aufwand.** Mittel. **Risiko.** Gering.

### 6. Sparklines existieren, aber nicht dort, wo man sie sucht

**Befund.** `visualization.lua` kann `generate_sparkline()` /
`create_daily_sparkline()`; genutzt wird das in der Detailansicht und in
`:GithubStats chart`. Die Dashboard-Zeile eines Repos zeigt vier Zahlen und
einen Pfeil — den Verlauf sieht man erst nach `<CR>`.

**Vorschlag.** Eine Sparkline in die bestehende `Period:`-Zeile jedes
Eintrags, gespeist aus dem `daily_breakdown`, das für den Trend ohnehin schon
berechnet wird — also ohne zusätzliche Abfrage. `ENTRY_LINES` bleibt bei 5,
die Zeilenarithmetik unberührt.

**Aufwand.** Klein. **Risiko.** Gering — die Breitenberechnung ist byte- vs.
zeichenbasiert zu beachten; genau der Fehler, den ein Sparkline-Spec schon
einmal gefangen hat.

### 7. Keine Gesamtsumme über alle Repositories

**Befund.** Das Dashboard listet n Repositories; die naheliegendste Frage
("wie entwickelt sich das *insgesamt*?") beantwortet es nicht.
`analytics.query_all_repos()` und `compute_highlights()` liefern die Bausteine
bereits — genutzt werden sie nur vom Export.

**Vorschlag.** Eine Summenzeile im Kopf: Clones/Views gesamt über den aktiven
Bereich, plus Top-Repo. Erhöht `HEADER_LINES` auf 6 — dank der
Single-Source-of-Truth-Konstante eine Einzeiländerung.

**Aufwand.** Klein. **Risiko.** Gering.

---

## P3 — Genauigkeit im Detail

### 8. `3m` und `1y` sind Näherungen, `this_month` ist es nicht

**Befund.** `analytics.parse_time_range()` rechnet `Nm` als N × 30 Tage und
`Ny` als N × 365 Tage. Direkt daneben liefert `date_presets` mit
`this_month` / `this_quarter` / `this_year` kalendergenaue Grenzen. Zwei
Genauigkeitsbegriffe im selben Eingabefeld (`T`-Prompt).

**Vorschlag.** `Nm` / `Ny` über `os.date` / `os.time`-Kalenderarithmetik
führen (Monat bzw. Jahr dekrementieren, Tag klemmen). Verhaltensänderung um
bis zu 5 Tage pro Jahr → changelog-pflichtig. Alternativ: so lassen und die
Näherung im Prompt kennzeichnen. Sie ist heute in `DASHBOARD.md` korrekt
dokumentiert, also kein Fehler — nur eine Inkonsistenz.

**Aufwand.** Klein. **Risiko.** Gering.

---

## Ausdrücklich nicht vorgeschlagen

- **Webhooks / HTTP-Server** (siehe `IDEAS/IDEAS.md`): widerspricht dem
  lokalen Polling-Modell, größter Aufwand im Dokument, kleinster Ertrag für
  einen Einzelnutzer.
- **Häufigeres Fetchen**: Das Traffic-API liefert dieselben 14 Tage. Mehr
  Abfragen erzeugen keine neuen Daten, nur Rate-Limit-Verbrauch.
- **Eigenes Theme-System**: Highlight-Gruppen mit `default = true` erledigen
  dasselbe, ohne dass das Plugin Farben besitzen muss.
- **Datenbank / Kompression** (`IDEAS/IDEAS.md`, Ad-hoc-Notizen): Bei wenigen
  hundert Tageswerten pro Repo ist das Datenvolumen kein Problem. Das
  Kostenproblem ist das *wiederholte Lesen* (P1.2), nicht die Größe — und
  Kompression würde es verschärfen, nicht lösen.

---

## Empfohlene Reihenfolge

1. **P0.1 Auto-Refresh** — behebt eine falsche Zusage, kleiner Eingriff,
   nutzt den vorhandenen Teardown-Pfad.
2. **P1.4 Tests für die Darstellungsschicht** — vor allen weiteren
   Render-Änderungen, damit P2 auf einem Netz landet.
3. **P1.2 Lese-Memo** — größter spürbarer Gewinn pro Tastendruck.
4. **P1.3 Trend-Definition** — klein, aber Verhaltensänderung: früh erledigen,
   solange wenig darauf aufbaut.
5. **P2.5 Highlights** → **P2.6 Sparklines** → **P2.7 Summenzeile** — in
   dieser Reihenfolge, weil jeder Schritt auf dem vorigen aufsetzt.
6. **P3.8** — nur zusammen mit einer ohnehin anstehenden `analytics`-Runde.
