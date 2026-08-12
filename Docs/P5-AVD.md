# P5 – Azure Virtual Desktop

## Ziel

P5 erweitert den AzureInfrastructureCollector um ein kundengenerisches, normalisiertes und ausschließlich lesendes Azure-Virtual-Desktop-Inventar. Es werden nur tatsächlich vorhandene AVD-Ressourcen des ausgewählten Tenant-/Subscription-/Resource-Group-Scopes verarbeitet.

P5 verwendet ausschließlich den bereits bestehenden Azure-Resource-Graph-Zugriffspfad:

```text
Azure Resource Graph
  -> Resources + DesktopVirtualizationResources
  -> Queries/AVD.kql
  -> Invoke-CollectorResourceGraph / Search-AzGraph
  -> Collector.AVD.psm1
  -> Collector.ExportSecurity.psm1
  -> Inventory/avd.json
```

Für `Microsoft.DesktopVirtualization/hostpools/sessionhosts` wird die spezielle Azure-Resource-Graph-Tabelle `DesktopVirtualizationResources` verwendet. Es wird kein zusätzliches AVD-PowerShell-Cmdlet, kein REST-Aufruf, keine Azure CLI und kein SDK-Schreibpfad eingeführt.

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

## Fehlerverhalten

P5 ist ein Fachmodul. Ein isolierter P5-Fehler darf bei weiterhin erfolgreichem Core-/P3-/P4-Inventar zu `PartialSuccess` führen. Ein Read-only-/Pre-Azure-Validierungsfehler bleibt immer kritisch und blockiert Azure vollständig.

## Definition of Done P5

P5 gilt erst als abgeschlossen, wenn:

- [x] AVD-Scope und Sicherheits-/Datenminimierungsgrenze dokumentiert sind
- [x] `Queries/AVD.kql` mit `Resources` und `DesktopVirtualizationResources` implementiert ist
- [x] `Collector.AVD.psm1` implementiert ist
- [x] Unit-/Regressionstests für Query-Safety, Workspace, Host Pool, Application Group, Session Host, Scaling Plan und leere Arrays vorhanden sind
- [x] `Collect-AzureDocumentation.ps1` P5 vollständig integriert
- [x] `Inventory/avd.json` und `summary.avd` im normalen Collector integriert
- [ ] automatische Pre-Azure-Validierung des finalen P5-Stands mit 0 Testfehlern und `READ-ONLY VERIFIED` / `READY FOR AZURE TEST` erfolgreich
- [ ] realer P5-Kundenexport erzeugt
- [ ] `avd.json` gegen Core/P4, Relationships, Orphans, Array-/Schema-Stabilität und Secret-/PII-Leakage geprüft

> **P5 ist implementiert, aber noch nicht real validiert. Durch die P5-Codeänderungen ist die vorherige P4-Laufzeitfreigabe für den aktuellen ausführbaren Stand nicht mehr ausreichend. Vor dem ersten P5-Azure-Lauf muss die automatische Pre-Azure-Validierung erneut erfolgreich sein.**
