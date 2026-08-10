# AzureInfrastructureCollector – Umsetzungsplan

> **Status:** Source of Truth  
> **Repository:** `Vertax1337/AzureInfrastructureCollector`  
> **Default Branch:** `main`  
> **Dokumentstatus:** Verbindlicher Entwicklungsplan  
> **Stand:** 2026-08-10  
> **Initiale Zielversion:** `0.1.0`

---

# 0. OBERSTE REGEL – READ-ONLY MUSS VOR JEDER AUSFÜHRUNGSFREIGABE VERIFIZIERT SEIN

> **Diese Regel hat Vorrang vor allen anderen Anforderungen, Architekturentscheidungen, Features, Entwicklungszielen und Zeitplänen dieses Projekts.**

Der **AzureInfrastructureCollector darf unter keinen Umständen Azure-Ressourcen, Azure-Konfigurationen, Azure-Datenbestände oder andere Azure-seitige Zustände verändern.**

Ein Skriptstand, Modul, Hotfix, Testskript oder ausführbarer Code darf erst dann für einen realen Azure-Lauf freigegeben werden, wenn die abschließende Read-only-Verifikation erfolgreich war und eindeutig `READ-ONLY VERIFIED` liefert.

Kann Read-only nicht zweifelsfrei bestätigt werden, gilt der Stand als **nicht freigegeben**.

## 0.1 Zulässige Wirkungen

Zulässig sind ausschließlich:

- Azure-Leseoperationen,
- Azure Resource Graph Abfragen,
- explizit geprüfte lesende Azure PowerShell Cmdlets,
- Authentifizierung ohne Ressourcenänderung,
- lokales PowerShell-/Az-Context-Switching ohne Azure-Ressourcenänderung,
- lokale Normalisierung und Auswertung,
- lokale Export-, Log-, Manifest-, Summary- und ZIP-Erzeugung,
- lokale Installation der explizit benötigten PowerShell-Abhängigkeiten im Benutzerkontext durch den getrennten Bootstrap.

`Connect-AzAccount` und `Set-AzContext -Scope Process` sind zulässig, solange dadurch ausschließlich Authentifizierung bzw. lokaler Sitzungskontext verändert werden.

## 0.2 Verbotene Azure-seitige Wirkungen

Nicht zulässig sind insbesondere:

- Ressourcen erstellen, ändern oder löschen,
- VMs starten, stoppen, neu starten oder deallokieren,
- Netzwerkregeln, Tags, RBAC, Policies oder Locks verändern,
- Backup-, Monitoring- oder Automation-Konfiguration verändern,
- Secrets, Keys oder Zertifikate erzeugen, verändern oder rotieren,
- Daten in Azure Storage, Datenbanken, Key Vault oder andere Azure-Dienste schreiben,
- Deployments oder andere Provider-Aktionen mit zustandsverändernder Wirkung auslösen.

## 0.3 Keine reine Verb-Prüfung

Read-only wird anhand der **tatsächlichen Wirkung** beurteilt. `Set-AzContext -Scope Process` ist zulässig, obwohl das Verb `Set` lautet, weil keine Azure-Ressource verändert wird.

## 0.4 Fail Closed

- eindeutig lesend verifiziert -> zulässig,
- eindeutig lokal ohne Azure-Ressourcenänderung -> zulässig,
- unbekannt -> blockieren,
- unklar -> blockieren,
- potenziell schreibend -> blockieren,
- schreibend -> blockieren.

## 0.5 Pflichtprüfung

Vor jeder realen Azure-Ausführungsfreigabe werden mindestens geprüft:

1. alle PowerShell-Dateien des ausführbaren Scopes,
2. alle Azure PowerShell Cmdlets,
3. alle REST/API-/SDK-Aufrufe,
4. dynamische Befehlsausführung,
5. eingebundene Module und Skripte,
6. KQL-Abfragen,
7. Parameter- und Fallback-Pfade,
8. Änderungen seit der letzten Verifikation.

## 0.6 Verbindlicher Status

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE
Azure data mutations: NONE
Control-plane write operations: NONE
Data-plane write operations: NONE
Local writes: approved local bootstrap/export operations only
```

## 0.7 Automatisches Gate

Das Projekt besitzt ein Fail-Closed-Gate. Unbekannte Azure-Aufrufe, direkte REST-/CLI-Pfade, dynamische Befehlsausführung und nicht genehmigte lokale Mutationspfade blockieren die Freigabe.

Automatische Prüfungen ersetzen nicht die fachliche Prüfung eines neuen Azure-Aufrufs.

## 0.8 Änderungen an dieser Regel

Eine Aufweichung ist nur nach expliziter Entscheidung des Projektverantwortlichen und vorheriger Änderung dieser Source of Truth zulässig.

> **Keine bestätigte Read-only-Verifikation = keine Azure-Ausführungsfreigabe.**

---

# 1. Projektziel

Der AzureInfrastructureCollector ist ein **kundengenerisches, tenantfähiges, reproduzierbares und ausschließlich lesendes Inventarisierungswerkzeug** für Azure-Infrastrukturen.

Er erzeugt ein normalisiertes Datenmodell als Grundlage für:

- technische Bestandsdokumentation,
- Architekturdiagramme,
- KI-gestützte Dokumentation,
- Soll-/Ist- und Snapshot-Vergleiche,
- Sicherheits- und Betriebsdokumentation,
- spätere DOCX-/PDF-Ausgabe.

Datenerfassung und spätere KI-/Dokumentgenerierung bleiben getrennt.

---

# 2. Ausführungsarchitektur

```text
Benutzer
   |
   v
Start-AzureInfrastructureCollector.ps1
   |
   +--> minimaler lokaler PowerShell-Runtime-Preflight
   |      +--> PS 7.2+ vorhanden? sonst kontrollierter Abbruch
   |
   +--> Read-only Gate über den lokalen ausführbaren Source-Code
   |
   +--> Dependency Bootstrap
   |      +--> Az.Accounts prüfen
   |      +--> Az.ResourceGraph prüfen
   |      +--> fehlende Module nur CurrentUser installieren
   |
   v
Collect-AzureDocumentation.ps1
   |
   +--> Read-only Gate erneut
   +--> Azure Auth / lokaler Az-Kontext
   +--> Azure Resource Graph / geprüfte Read-only Cmdlets
   |
   v
Normalisiertes JSON-Modell
   |
   +--> readOnlyVerification.json
   +--> manifest.json
   +--> summary.json
   +--> Inventardaten
   +--> Logs
```

Der minimale Runtime-Preflight vor dem Gate greift **nicht auf Azure zu und verändert lokal nichts**. Er existiert ausschließlich, damit Windows PowerShell 5.1 kontrolliert abgewiesen werden kann, bevor PowerShell-7-spezifischer Guard-Code geladen wird.

---

# 3. Bootstrap / lokale Voraussetzungen

## 3.1 Bevorzugter Einstiegspunkt

```powershell
./Start-AzureInfrastructureCollector.ps1
```

## 3.2 Kein Self-Elevation

Das Projekt darf keine automatische UAC-Elevation durchführen.

Verboten sind insbesondere:

- `Start-Process ... -Verb RunAs`,
- Neustart als Administrator,
- automatisches Nachladen eines administrativen Tokens.

Der normale Collector-Lauf soll ohne lokale Administratorrechte möglich sein.

## 3.3 PowerShell 7

Mindestversion: **PowerShell 7.2**.

PowerShell selbst wird nicht automatisch installiert oder aktualisiert. Fehlt die Mindestversion, bricht der Bootstrap kontrolliert ab. Eine PowerShell-Installation bleibt ein separater bewusster Arbeitsplatz-/Adminvorgang.

## 3.4 Dependency Policy

Initial benötigt:

- `Az.Accounts`,
- `Az.ResourceGraph`.

Bootstrap-Verhalten:

1. vorhandene Module erkennen,
2. vorhandene Installation weiterverwenden,
3. fehlende Module nur über bereits registrierte `PSGallery` beziehen,
4. Installation ausschließlich `Install-Module -Scope CurrentUser`,
5. niemals `AllUsers`,
6. niemals Self-Elevation,
7. keine automatische Repository-Registrierung oder -Änderung,
8. Module nach Installation erneut erkennen und importieren,
9. bei Fehler kontrolliert abbrechen.

Pester ist nur Entwicklungs-/Testabhängigkeit und nicht Voraussetzung für einen normalen Collector-Lauf.

## 3.5 Vom Gate erzwungene lokale Grenze

Zulässig ist im ausführbaren Projektcode ausschließlich die explizite `Install-Module -Scope CurrentUser`-Dependency-Installation.

Das Gate blockiert unter anderem:

- `Install-Module` ohne literal `-Scope CurrentUser`,
- `Update-Module`,
- `Uninstall-Module`,
- `Save-Module`,
- PowerShell-Repository-Registrierung/-Änderung,
- alternative Package-/PSResource-Mutationspfade,
- `Start-Process`.

---

# 4. Collector-Kernprinzipien

## 4.1 Kundengenerisch

Keine fest codierten Kunden-, Tenant-, Subscription-, Resource-Group- oder Ressourcennamen im Core.

## 4.2 Tenantfähig

Ein Lauf besitzt genau einen Tenant-Kontext und kann mehrere Subscriptions erfassen. Mehrere Tenants werden später nacheinander verarbeitet und nie ununterscheidbar in einem Export vermischt.

## 4.3 Resource Graph First

Azure Resource Graph ist die bevorzugte Quelle für breite Inventarisierung. Az PowerShell oder später geprüfte REST-Aufrufe werden nur verwendet, wenn Resource Graph erforderliche Details nicht liefert.

## 4.4 Least Privilege

Lokale Administratorrechte sind nicht vorgesehen. Azure-seitig soll Reader-orientierter Zugriff genügen, soweit einzelne Fachbereiche keine zusätzlichen Leserechte erfordern.

## 4.5 Keine Secrets

Keine Kennwörter, Client Secrets, Storage Keys, SAS Tokens, Private Keys, Access Tokens, API Keys oder sonstigen Credential-Werte werden bewusst exportiert.

## 4.6 Reproduzierbarkeit

Stabile Felder, konsistente Dateinamen, definierte Sortierung, ISO-8601-Zeitstempel, Resource IDs und Schema-/Collector-Versionen.

## 4.7 Best Effort

Optionale Modulfehler können Partial Collection ergeben. Read-only-Verifikationsfehler sind immer kritisch.

---

# 5. Repository-Struktur

```text
AzureInfrastructureCollector/
|
+-- Start-AzureInfrastructureCollector.ps1
+-- Collect-AzureDocumentation.ps1
+-- Umsetzungsplan.md
+-- README.md
+-- CHANGELOG.md
|
+-- Modules/
|   +-- Collector.Bootstrap.psm1
|   +-- Collector.ReadOnlyGuard.psm1
|   +-- Collector.Core.psm1
|   +-- Collector.Network.psm1
|   +-- Collector.Compute.psm1
|   +-- Collector.AVD.psm1
|   +-- Collector.Storage.psm1
|   +-- Collector.Backup.psm1
|   +-- Collector.Security.psm1
|   +-- Collector.Monitoring.psm1
|   +-- Collector.Automation.psm1
|
+-- Queries/
+-- Config/
+-- Schemas/
+-- Tests/
+-- Tools/
+-- Docs/
```

---

# 6. Bedienung und Parameter

Bootstrap und Collector unterstützen initial:

- `-TenantId`,
- `-SubscriptionId`,
- `-ResourceGroup`,
- `-OutputPath`,
- `-NonInteractive`.

Der direkte Aufruf von `Collect-AzureDocumentation.ps1` bleibt für Entwicklung und vorbereitete Systeme möglich; dort müssen Dependencies bereits vorhanden sein.

Im `-NonInteractive`-Modus dürfen keine Eingabeprompts erforderlich sein.

---

# 7. Authentifizierung und Azure-Kontext

Version 1 unterstützt interaktive Anmeldung über `Connect-AzAccount` und vorhandene Az-Kontexte.

Später möglich:

- Managed Identity,
- Service Principal,
- Azure Automation,
- CI/CD.

Credentials dürfen niemals im Repository hinterlegt werden.

---

# 8. Scope-Modell

```text
Tenant
  +-- Subscription A
  |    +-- Resource Group 1
  |    +-- Resource Group 2
  +-- Subscription B
       +-- Resource Group 3
```

---

# 9. Erfassungsumfang Version 1

## Core

Tenant, Subscriptions, Resource Groups, Regionen, Ressourcentypen, Tags, Resource IDs.

## Network

VNets, Subnets, Peerings, NICs, IP-Konfiguration, Public IPs, NSGs/Rules, Routes, NAT, Private Endpoints, Private DNS, Gateways, Load Balancer, Application Gateway, Firewall-Basisdaten.

## Compute

VMs, Size/SKU, OS/Image, Availability, NIC-Zuordnung, OS-/Data-Disks, Disk SKU/Size, optional Power State als Momentaufnahme.

## AVD

Workspaces, Host Pools, Application Groups, Session Hosts, Settings, Start VM on Connect, Scaling Plans und Beziehungen zur VM.

## Storage / Backup / Key Vault

Storage-Konfigurationsmetadaten, Backup-Vaults/-Policies/-Protected Items und Key-Vault-Konfiguration. Keine Blob-/Dateiinhalte, Backup-Inhalte, Secrets, Keys oder Private Keys.

## Security / Governance

RBAC Role Assignments, Role-Definition-Referenzen, Locks, Policy-/Initiative-Assignments; personenbezogene Identitätsdaten werden minimiert.

## Monitoring / Automation

Log Analytics, Diagnostic Settings, Action Groups, Alerts, Automation Accounts, Runbook-Metadaten, Schedules und Associations. Kein Runbook-Quellcode standardmäßig.

---

# 10. Export und Datenmodell

```text
<Tenant>_<Timestamp>/
+-- readOnlyVerification.json
+-- manifest.json
+-- summary.json
+-- Inventory/
+-- Logs/
```

Resource ID ist der bevorzugte technische Primärschlüssel. Arrays werden stabil sortiert. Nicht verfügbare Werte werden nicht erfunden.

`Output/` bleibt von Git ausgeschlossen.

---

# 11. Relationship Engine

Zielbeziehungen unter anderem:

```text
VM -> NIC -> Subnet -> VNet
VM -> Managed Disk
NIC/Subnet -> NSG
Subnet -> Route Table
Private Endpoint -> Target Resource
AVD Session Host -> VM
Diagnostic Setting -> Destination
Backup -> Protected Resource
```

---

# 12. Logging und Fehlerbehandlung

Logs enthalten Zeitstempel, Level, Modul/Aktion und Ergebnis; niemals Secrets oder Access Tokens.

Kritische Fehler:

- Read-only-Verifikation fehlgeschlagen,
- PowerShell-Mindestversion fehlt,
- Dependency kann nicht bereitgestellt werden,
- Azure-Authentifizierung nicht möglich,
- Tenant/Subscription nicht erreichbar,
- Core-Export nicht möglich.

Geplante Exit-Code-Kategorien:

```text
0  Erfolg
1  Partial Success / Warnungen
2  Konfiguration
3  Auth/Berechtigung Core
4  lokaler Export/Dateisystem
5  unerwarteter interner Fehler
6  Read-only-Verifikation
7  Runtime/Dependency-Voraussetzung
```

---

# 13. KI-Grenze

Der Collector benötigt keine KI.

```text
Azure -> Collector -> JSON -> AI Documentation Pipeline -> Markdown/DOCX/PDF/Diagramme
```

Die KI darf keine nicht durch Quelldaten belegten Fakten erfinden.

---

# 14. Entwicklungsphasen

## P0 – Projektgrundlage

- [x] Repository
- [x] Source of Truth
- [x] README / .gitignore / Config
- [x] PowerShell-Mindestversion
- [x] oberste Read-only-Regel
- [ ] Lizenzentscheidung
- [ ] Coding-Konventionen vervollständigen

## P0a – Read-only Verification Gate

- [x] Fail-Closed Guard
- [x] Azure-Allowlist
- [x] direkte REST-/CLI-/dynamische Ausführung blockieren
- [x] `Set-AzContext` nur `-Scope Process`
- [x] separater Prüfaufruf
- [x] Pester-Tests implementiert
- [x] GitHub Actions Gate implementiert
- [x] initiale manuelle/statische Verifikation
- [ ] lokaler PowerShell-Gate-/Pester-Lauf vor erstem Azure-Test

## P0b – Bootstrap / Dependencies

- [x] `Start-AzureInfrastructureCollector.ps1`
- [x] `Collector.Bootstrap.psm1`
- [x] PowerShell 7.2+ prüfen
- [x] fehlende Runtime kontrolliert melden
- [x] `Az.Accounts` automatisch `CurrentUser` installieren
- [x] `Az.ResourceGraph` automatisch `CurrentUser` installieren
- [x] Dependencies nach Installation erneut prüfen/importieren
- [x] keine Self-Elevation
- [x] keine `AllUsers`-Installation
- [x] keine automatische Repository-Mutation
- [x] Bootstrap-Tests implementiert
- [x] Read-only-Gate um Bootstrap-Grenze erweitert
- [ ] lokaler Bootstrap-/Pester-Test vor erstem Azure-Test

## P1 – Core

- [x] Collector-Einstieg
- [x] Context/Auth
- [x] Tenant-/Subscription-Auswahl
- [x] RG-Scope
- [x] Output / Logging / Manifest-Grundstruktur
- [ ] Exit Codes vollständig
- [ ] Read-only-Status vollständig in Manifest integrieren

## P2 – Basisinventar

- [x] Resource Groups
- [x] Ressourcen
- [x] Tags / Regionen / Typen
- [x] Pagination
- [x] Multi-Subscription
- [x] stabile Normalisierung/Sortierung
- [x] Summary
- [ ] realer Integrationstest

## P3 – Netzwerk

- [ ] Netzwerkobjekte und Relationships

## P4 – Compute

- [ ] VM-/Disk-/Availability-Daten und Relationships

## P5 – AVD

- [ ] AVD-Struktur und VM-Beziehungen

## P6 – Storage / Backup / Key Vault

- [ ] Metadaten und Secret-Filtering

## P7 – Security / Governance

- [ ] RBAC / Policies / Locks / Identitätsdatenschutz

## P8 – Monitoring / Automation

- [ ] Monitoring- und Automation-Metadaten

## P9 – Relationship Engine

- [ ] vereinheitlichtes Relationship-Schema

## P10 – Qualitätssicherung / Härtung

- [ ] Integrationstests in heterogenen Testumgebungen
- [ ] Reader-Rechte / fehlende Berechtigungen
- [ ] Secret Leakage Tests
- [ ] JSON Schema Validation
- [ ] ScriptAnalyzer
- [ ] Read-only-Test für jeden neuen Azure-Aufruf

## P11 – Release 1.0

- [ ] vollständige Dokumentation
- [ ] Beispiel-Export
- [ ] Troubleshooting
- [ ] Release ZIP
- [ ] vollständige finale Read-only-Verifikation

---

# 15. Entwicklungsregeln

1. Keine kundenspezifischen Sonderfälle im Core.
2. Keine stillen Annahmen.
3. Keine Secrets in Source Control.
4. Neue Azure-Aufrufe benötigen dokumentierten Read-only-Nachweis.
5. Unbekannte Azure-Aufrufe werden blockiert.
6. Bootstrap und Collector bleiben getrennte Verantwortlichkeiten.
7. Lokale Dependency-Installation nur `CurrentUser`.
8. Keine Self-Elevation.
9. PowerShell 7 wird nicht automatisch installiert.
10. Keine automatische PowerShell-Repository-Mutation.
11. Architektur-/Scope-Änderungen werden zuerst in diesem Dokument festgelegt.

---

# 16. Definition of Done Collector-Modul

Ein Modul gilt erst als fertig, wenn es kundengenerisch ist, Scope-Filter respektiert, Azure-Aufrufe read-only verifiziert sind, Fehler/Berechtigungen transparent behandelt werden, keine Secrets exportiert werden, Daten stabil sind, Tests vorhanden sind und die abschließende Read-only-Verifikation erfolgreich ist.

---

# 17. Definition of Done Version 1.0

Version 1.0 erfordert insbesondere:

1. normaler Lauf ohne lokale Administratorrechte,
2. Bootstrap kann unterstützte fehlende Module im Benutzerkontext bereitstellen,
3. keine Self-Elevation,
4. Tenant-/Multi-Subscription-/RG-Scope,
5. geplante Fachbereiche,
6. strukturierter Export mit Manifest/Summary/Relationships,
7. Secret Filtering und Berechtigungsfehler getestet,
8. realistischer Kundenexport erfolgreich,
9. KI-Dokumentation auf Exportbasis möglich,
10. finale vollständige Verifikation liefert `READ-ONLY VERIFIED`.

Ohne Punkt 10 gibt es keinen ausführbaren Release.

---

# 18. Aktuelle Priorität

```text
P0   Projektgrundlage
P0a  Read-only Verification Gate
P0b  Bootstrap / Dependency Handling
P1   Core / Auth / Tenant / Subscription / Scope
P2   Basisinventar
P3   Netzwerk
P4   Compute
P5   AVD
P6   Storage / Backup / Key Vault
P7   Security / Governance
P8   Monitoring / Automation
P9   Relationship Engine
P10  Tests / Härtung
P11  Release 1.0
```

**Vor dem ersten realen Azure-Test sind jetzt nur noch die lokalen PowerShell-Ausführungen des Gates und der Pester-Suite offen.**

---

# 19. Offene Architekturentscheidungen

- exakte Mindest-/Pinning-Versionen der Az-Module,
- ZIP-Default,
- Identity Display Names / Microsoft Graph,
- Defender-for-Cloud-Detailtiefe,
- Resource Change History,
- Relationship-Schema,
- SemVer-Strategie,
- Repository-Lizenz.

---

# 20. Leitentscheidung

Der AzureInfrastructureCollector ist kein einmaliges Kundenskript, sondern ein wiederverwendbares, tenantfähiges und kundengenerisches **Read-only Inventarisierungswerkzeug**.

```text
Azure ist die Quelle der Wahrheit
        ->
Collector erfasst ausschließlich lesend den Ist-Zustand
        ->
JSON normalisiert die Fakten
        ->
KI interpretiert und formuliert
        ->
Dokumente und Diagramme präsentieren das Ergebnis
```

**Ohne unmittelbar zuvor erfolgreich abgeschlossene Read-only-Verifikation darf kein realer Azure-Lauf freigegeben werden.**
