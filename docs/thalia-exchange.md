# Theo liefert Thalia Daten (Binisoft-Austausch, Format v1)

Theo schreibt auf jedem iPhone, iPad und Mac kleine JSON-Dateien in die gemeinsame App Group
`group.at.binisoft.shared`. Thalia liest sie auf demselben Gerät und rechnet daraus ihre Werte.
Theo liest von Thalia nur den Katalog (Ziele und Kategorien). Kein Netz, kein Server.

## Plan

1. **Format im Core-Paket** – `Packages/TheoCore/Sources/TheoCore/ExchangeFormat.swift`, Thalias
   Referenzdatei unverändert kopiert (nur Foundation, läuft unter Linux).
2. **Tatsachen bauen** (`TheoExchange.swift`, Core, nur Werte, keine SwiftData-Typen):
   - `task.done` je erledigter Aufgabe (auch Unteraufgaben und die erledigten Kopien laufender
     Aufgaben), im Kalendertag ihres Erledigt-Zeitpunkts in der Zeitzone des Geräts.
     `id` `task-<UUID der Aufgabe>`, `ref` `grp-<UUID der Gruppe>`, `refTitle` der Pfad der Gruppe
     („Arbeit/Kunden“), ohne Gruppe `ohne-gruppe` / „Ohne Gruppe“.
   - `ph` je erledigter Aufgabe mit Power-Hours, `value` in PH, `unit` `"PH"`, `at` = erledigt am,
     `id` `ph-<UUID der Aufgabe>`. Gezählt wird genau wie im Tagesrückblick: Hat eine Unteraufgabe
     am selben Tag eigene PH, zählt die übergeordnete Aufgabe nicht noch einmal.
   - `thalia` `{category, categoryTitle}` aus der Gruppe; eine Untergruppe ohne eigene Wahl übernimmt
     die ihrer übergeordneten Gruppe, außer sie wählt ausdrücklich „Keine“.
   - Erledigte Aufgaben ausgeschalteter (pausierter) Gruppen zählen mit, wie im Tagesrückblick.
   - Nicht geliefert: gelöschte Aufgaben (Papierkorb), Tage in der Zukunft (Tagesdateien nach
     „heute“, etwa nach einem Wechsel der Zeitzone, werden leer geschrieben), Tage älter als 62 Tage.
     Keine Werte aus Apple Health (Theo hat keine).
3. **Schreiben** (`ThaliaExchangeWriter.swift`, Core): je Tag eine vollständige Datei, nur bei
   geänderten Tatsachen, atomar; ein Tag, der eine Datei hatte und nun nichts mehr hat, bekommt
   `"facts":[]`; Dateien älter als 62 Tage werden gelöscht. `source.json` sofort bei geänderten
   `refs` oder App-Version, sonst einmal am Tag.
4. **App-Schicht** (`App/Sources/Application/ThaliaBridge.swift`, iPhone/iPad/Mac, nie Watch):
   Ordner `<Group>/Theo/exchange`, am Mac erst nach der Entitlement-Prüfung (abseits des
   Main-Threads, nicht beim Start). Anstoß entprellt (2 s) nach jedem Speichern, nach dem
   CloudKit-Import, beim Wechsel in den Vordergrund, beim Tageswechsel und wenn der Schalter oder
   eine Zuordnung sich ändert. Danach die Darwin-Benachrichtigung `at.binisoft.exchange.changed`.
   Nur aus dem über iCloud synchronisierten Speicher, also nie im Demo-, Screenshot-, Übungs-,
   lokalen Ersatz- oder In-Memory-Speicher. Auf dem iPhone hält Theo sich beim Wechsel in den
   Hintergrund kurz wach, bis geschrieben ist; der Mac schreibt beim Beenden noch einmal. Kann ein
   Tag nicht geschrieben werden, laufen die anderen weiter und Thalia wird trotzdem benachrichtigt.
   Ein neues oder frisch installiertes Gerät (oder ein anderes iCloud-Konto) liefert erst, wenn
   iCloud die Daten einmal geladen hat und der Schalter von iCloud bekannt ist. Ein leerer Speicher
   leert nie Tage, die Thalia schon hat; das tut nur der ausgeschaltete Schalter.
5. **Zuordnung „Thalia-Kategorie“** im Gruppen-Editor (iPhone, iPad, Mac gleich): „Keine“ und
   darunter die Kategorien aus Thalias Katalog, nach Ziel gruppiert („3 Arbeit“ → „3.2 Kunden“).
   Untergruppen einer zugeordneten Gruppe haben zusätzlich „Wie die übergeordnete Gruppe (…)“.
   Erneutes Wählen einer Kategorie übernimmt ihren aktuellen Namen aus Thalia.
   Gespeichert in der Gruppe selbst (ihr synchronisiertes Zusatzfeld `extrasRaw`, Schlüssel
   `thalia.category` und `thalia.categoryTitle`): auf allen Geräten gleich, Teil der Sicherungen,
   keine CloudKit-Schemaänderung. Hinweise „Thalias Katalog fehlt auf diesem Gerät – Thalia hier
   einmal öffnen.“ und „Zuordnung prüfen“.
6. **Schalter „An Thalia liefern“** (Standard ein) in den Einstellungen, Abschnitt „Thalia“.
   Synchronisiert über iCloud (Schlüssel-Wert-Speicher, `NSUbiquitousKeyValueStore`), also auf allen
   Geräten gleich. Aus: Jedes Gerät schreibt seine Tage ohne Tatsachen neu (Thalia nimmt die Werte
   heraus) und liefert danach nichts mehr. Dazu „Zuletzt geschrieben: …“ und „Thalia übernimmt die
   Werte, sobald Thalia auf diesem Gerät geöffnet wird.“
7. **Tests** im Core (Swift Testing) mit Thalias Testdateien; ein Linux-Job in CI führt sie unter
   Ubuntu aus (Ergebnis auf dem Branch `ci-linux`), der Mac-Job wie bisher.
8. **Version** 1.1.0, mit einem „What's new“-Schritt in der Tour.

## Entscheidungen (mit Bini abgestimmt)

- Power-Hours = PH erledigter Aufgaben, jeweils der Thalia-Kategorie ihrer Gruppe zugeordnet.
- Zuordnung in der Gruppe selbst (es gibt keinen synchronisierten Einstellungs-Datensatz).
- Der Schalter gilt auf allen Geräten.
- Texte auf Deutsch.
