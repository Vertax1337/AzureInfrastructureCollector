# P5 – Azure Virtual Desktop

## Ziel

P5 erweitert den AzureInfrastructureCollector um ein kundengenerisches, normalisiertes und ausschließlich lesendes Azure-Virtual-Desktop-Inventar. Es werden nur tatsächlich vorhandene AVD-Ressourcen des ausgewählten Tenant-/Subscription-/Resource-Group-Scopes verarbeitet.

P5 verwendet ausschließlich den bereits bestehenden Azure-Resource-Graph-Zugriffspfad:

```text
Azure Resource Graph
  -> Resources
       -> Queries/AVD.kql
  -> DesktopVirtualizationResources
       -> Queries/AVD.SessionHosts.kql
  -> Invoke-CollectorResourceGraph / Search-AzGraph
  -> lokale Zusammenführung der Ergebniszeilen
  -> Collector.AVD.psm1
  -> Collector.ExportSecurity.psm1
  -> Inventory/avd.json
```

Für `Microsoft.DesktopVirtualization/hostpools/sessionhosts` wird die spezielle Azure-Resource-Graph-Tabelle `DesktopVirtualizationResources` verwendet. Es wird kein zusätzliches AVD-PowerShell-Cmdlet, kein REST-Aufruf, keine Azure CLI und kein SDK-Schreibpfad eingeführt.

Die beiden ARG-Tabellen werden absichtlich in getrennten Queries gelesen. Azure Resource Graph unterstützt über das SDK keine allgemeine Cross-Table-`union`-Abfrage zwischen `Resources` und `DesktopVirtualizationResources`. Die Ergebnisarrays werden deshalb erst lokal im Collector zusammengeführt.

## Scope

P5 erfasst:

- `Microsoft.DesktopVirtualization/workspaces`
- `Microsoft.DesktopVirtualization/hostpools`
- `Microsoft.DesktopVirtualization/applicationgroups`
- `Microsoft.DesktopVirtualization/hostpools/sessionhosts`
- `Microsoft.DesktopVirtualization/scalingplans`

### Workspaces

Normalisiert werden:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Friendly Name
- Public Network Access
- Application-Group-Resource-IDs

### Host Pools

Normalisiert werden insbesondere:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Friendly Name
- Host Pool Type
- Load Balancer Type
- Max Session Limit
- Personal Desktop Assignment Type
- Preferred App Group Type
- Public Network Access
- Start VM on Connect
- Validation Environment
- Management Type, soweit geliefert
- technische UDP-Modi, soweit geliefert
- sichere Agent-Update-Metadaten einschließlich Wartungsfenstern

### Application Groups

Normalisiert werden:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Friendly Name
- Application Group Type
- Host-Pool-Resource-ID
- Show In Feed

P5 erfasst bewusst keine einzelnen veröffentlichten `applicationGroups/applications`. Damit werden insbesondere ausführbare Dateipfade und Command-Line-Argumente nicht in P5 aufgenommen.

### Session Hosts

Normalisiert werden ausschließlich technische Betriebsmetadaten:

- Session-Host-Resource-ID und Name
- Parent Host Pool Resource ID
- Friendly Name
- Status und Status Timestamp
- Allow New Session
- Session Count sowie Active/Disconnected/Pending Counts, soweit geliefert
- Agent Version
- OS Version
- SxS Stack Version
- Update State
- Last Heartbeat
- Last Update Time
- Resource ID der zugrunde liegenden Azure VM

Die direkte VM-Resource-ID wird für die Verbindung zum bereits normalisierten P4-Compute-Modell verwendet.

### Scaling Plans

Normalisiert werden:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Friendly Name
- Exclusion Tag
- Host Pool Type
- Time Zone
- Host-Pool-Referenzen einschließlich `scalingPlanEnabled`
- technische Schedule-Parameter für Ramp Up, Peak, Ramp Down und Off Peak
- Scaling Method, soweit geliefert
- Create/Delete-Min-/Max-Host-Pool-Größen, soweit geliefert

## Exportmodell

`Inventory/avd.json` besitzt folgende Top-Level-Struktur:

```json
{
  "schemaVersion": "1.0",
  "summary": {},
  "workspaces": [],
  "hostPools": [],
  "applicationGroups": [],
  "sessionHosts": [],
  "scalingPlans": [],
  "relationships": []
}
```

Leere Collections bleiben echte JSON-Arrays `[]`.

## Relationships

P5 erzeugt ausschließlich Resource-ID-basierte Beziehungen:

```text
Workspace -> ReferencesApplicationGroup -> Application Group
Application Group -> UsesHostPool -> Host Pool
Host Pool -> ContainsSessionHost -> Session Host
Session Host -> BackedByVm -> P4 Virtual Machine
Scaling Plan -> TargetsHostPool -> Host Pool
```

Die Session-Host-Parent-Beziehung wird ausschließlich deterministisch aus der eigenen Session-Host-ARM-ID abgeleitet. Die VM-Beziehung wird ausschließlich aus `properties.resourceId` des Session Hosts übernommen. Es werden keine VM-Namen oder DNS-Namen heuristisch auf Azure-Ressourcen gemappt.

## Sicherheits- und Datenminimierungsgrenze

P5 fragt bzw. exportiert bewusst nicht:

- Host-Pool `registrationInfo` oder Registration Token
- Host-Pool `ssoClientSecretKeyVaultPath`
- Host-Pool `vmTemplate`
- Host-Pool `customRdpProperty` als frei konfigurierbaren Rohtext
- OBO Tenant IDs
- Session-Host `assignedUser`
- interne Session-Host Object IDs oder VM GUIDs
- Session-Host Health-Check-Detailobjekte
- Session-Host `updateErrorMessage`
- einzelne AVD User Sessions oder deren Benutzeridentitäten
- veröffentlichte Application-Child-Ressourcen, File Paths oder Command-Line-Argumente
- Scaling-Plan `rampDownNotificationMessage`
- vollständige rohe AVD-`properties`-Objekte

Die zentrale `Collector.ExportSecurity.psm1`-Härtung wird vor dem Schreiben von `avd.json` zusätzlich auf das vollständige normalisierte AVD-Modell angewendet.

## Session-Host-Status-Semantik

Status, Session-Zahlen und Heartbeat sind ausschließlich Momentaufnahmen des Erfassungszeitpunkts. Sie werden nicht als historische Verfügbarkeits- oder Nutzungsstatistik interpretiert.

Ein fehlender Status, fehlender Heartbeat oder fehlende VM-Resource-ID wird als nicht von Azure Resource Graph geliefert behandelt. Fehlende Werte werden nicht ergänzt oder aus Namen hergeleitet.

## Core-/P4-Abgleich

Top-Level-AVD-Ressourcen wie Workspaces, Host Pools, Application Groups und Scaling Plans stammen aus `Resources` und können gegen `resources.json` abgeglichen werden.

Session Hosts stammen dagegen aus `DesktopVirtualizationResources` und müssen nicht als eigene Zeilen in `resources.json` vorhanden sein. Für sie wird stattdessen geprüft:

- Parent Host Pool existiert im P5-Inventar,
- `virtualMachineResourceId`, soweit geliefert, existiert im P4-Compute-Inventar,
- Relationships sind eindeutig und orphan-frei innerhalb der bekannten Referenzgrenzen.

## Erster Real-Run und Query-Hotfix 2026-08-12

Der erste P5-Lauf erreichte vor Azure erfolgreich:

- PowerShell 7.6.4
- Pester 6.0.1
- 10 Testdateien
- 59/59 Tests bestanden
- initiales und finales Read-only-Gate jeweils `READ-ONLY VERIFIED`
- `READY FOR AZURE TEST`
- vor Azure `Azure access performed: NO`
- keine Administrator-Elevation

P3 und P4 liefen anschließend weiterhin erfolgreich. Die erste P5-Abfrage schlug jedoch mit Azure Resource Graph `BadRequest` fehl; der Collector reagierte korrekt mit `PartialSuccess`, schrieb ein leeres schema-stabiles `avd.json` und veränderte keine Azure-Ressource.

Ursache war die ursprünglich in einer einzelnen Query verwendete Cross-Table-`union`-Konstruktion zwischen `Resources` und `DesktopVirtualizationResources`. Die Resource-Graph-SDK-Grenze erlaubt diese Tabellenkombination nicht als allgemeines `union`.

Der Hotfix trennt deshalb die Abfragen in:

- `Queries/AVD.kql` -> ausschließlich Top-Level-AVD-Ressourcen aus `Resources`
- `Queries/AVD.SessionHosts.kql` -> ausschließlich Session Hosts aus `DesktopVirtualizationResources`

Beide werden weiterhin ausschließlich über `Invoke-CollectorResourceGraph` / `Search-AzGraph` ausgeführt; erst danach werden die Ergebniszeilen lokal zusammengeführt. Zusätzliche Regressionstests verhindern künftig wieder eine Cross-Table-`union`-Konstruktion.

Da ausführbarer Code geändert wurde, muss der Hotfix vor einem erneuten Azure-Lauf wieder die vollständige automatische Pre-Azure-Validierung bestehen.

## Fehlerverhalten

P5 ist ein Fachmodul. Ein isolierter P5-Fehler darf bei weiterhin erfolgreichem Core-/P3-/P4-Inventar zu `PartialSuccess` führen. Ein Read-only-/Pre-Azure-Validierungsfehler bleibt immer kritisch und blockiert Azure vollständig.

## Definition of Done P5

P5 gilt erst als abgeschlossen, wenn:

- [x] AVD-Scope und Sicherheits-/Datenminimierungsgrenze dokumentiert sind
- [x] getrennte `Queries/AVD.kql` und `Queries/AVD.SessionHosts.kql` ohne unsupported Cross-Table-`union` implementiert sind
- [x] `Collector.AVD.psm1` implementiert ist
- [x] Unit-/Regressionstests für Query-Safety, Query-Split, Workspace, Host Pool, Application Group, Session Host, Scaling Plan und leere Arrays vorhanden sind
- [x] `Collect-AzureDocumentation.ps1` P5 vollständig integriert
- [x] `Inventory/avd.json` und `summary.avd` im normalen Collector integriert
- [ ] automatische Pre-Azure-Validierung des finalen P5-Hotfix-Stands mit 0 Testfehlern und `READ-ONLY VERIFIED` / `READY FOR AZURE TEST` erfolgreich
- [ ] erfolgreicher P5-Kundenexport nach Query-Hotfix erzeugt
- [ ] `avd.json` gegen Core/P4, Relationships, Orphans, Array-/Schema-Stabilität und Secret-/PII-Leakage geprüft

> **P5 ist implementiert und der erste Real-Run-Fehler wurde behoben, aber der Hotfix ist noch nicht erneut Pre-Azure-/real validiert.**
