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

Ein Skriptstand, Modul, Hotfix, Testskript oder ausführbarer Code darf erst dann zur Ausführung freigegeben werden, wenn unmittelbar zuvor die abschließende Read-only-Verifikation erfolgreich war und eindeutig den Status `READ-ONLY VERIFIED` liefert.

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

Read-only wird anhand der **tatsächlichen Wirkung** beurteilt, nicht nur anhand des Cmdlet-Verbs. `Set-AzContext -Scope Process` ist beispielsweise zulässig, obwohl das Verb `Set` lautet, weil dabei keine Azure-Ressource verändert wird.

## 0.4 Fail-Closed-Prinzip

- eindeutig lesend verifiziert -> zulässig,
- eindeutig lokal ohne Azure-Ressourcenänderung -> zulässig,
- unbekannt -> blockieren,
- unklar -> blockieren,
- potenziell schreibend -> blockieren,
- schreibend -> blockieren.

## 0.5 Pflichtprüfung vor jeder Freigabe

Vor jeder Ausführungsfreigabe werden mindestens geprüft:

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

## 0.7 Automatisches Read-only-Gate

Der Collector besitzt ein automatisches Fail-Closed-Gate. Ein unbekannter Azure-Aufruf oder eine blockierte Ausführungsmethode verhindert den Start der Azure-Inventarisierung.

Automatische Prüfungen ersetzen nicht die fachliche Prüfung eines neu eingeführten Azure-Aufrufs.

## 0.8 Änderungen an dieser Regel

Eine Aufweichung dieser Regel ist nur nach expliziter Entscheidung des Projektverantwortlichen und vorheriger Änderung dieser Source of Truth zulässig.

> **Keine bestätigte Read-only-Verifikation = keine Ausführungsfreigabe.**

---

# 1. Projektziel

Der AzureInfrastructureCollector ist ein **kundengenerisches, tenantfähiges, reproduzierbares und ausschließlich lesendes Inventarisierungswerkzeug** für Azure-Infrastrukturen.

Er erzeugt ein normalisiertes, maschinenlesbares Datenmodell als Grundlage für:

- technische Bestandsdokumentation,
- Architekturdiagramme,
- KI-gestützte Dokumentation,
- Soll-/Ist- und Snapshot-Vergleiche,
- Sicherheits- und Betriebsdokumentation,
- spätere DOCX-/PDF-Ausgabe.

Die Datenerfassung und die spätere KI-/Dokumentgenerierung bleiben getrennte Komponenten.

---

# 2. Grundarchitektur

```text
Benutzer
   |
   v
Start-AzureInfrastructureCollector.ps1
   |
   +--> Read-only Gate (lokaler Source-Code-Check)
   +--> PowerShell-Version prüfen
   +--> benötigte PowerShell-Module prüfen
   +--> fehlende Az-Module ausschließlich CurrentUser installieren
   |
   v
Collect-AzureDocumentation.ps1
   |
   +--> Read-only Gate erneut
   +--> Azure Auth / lokaler Kontext
   +--> Azure Resource Graph / verifizierte Read-only Cmdlets
   |
   v
Normalisiertes JSON-Modell
   |
   +--> manifest.json
   +--> summary.json
   +--> readOnlyVerification.json
   +--> modulare Inventardaten
   +--> Logs
```

## 2.1 Trennung Bootstrap / Collector

### Bootstrap

`Start-AzureInfrastructureCollector.ps1` ist der bevorzugte Benutzer-Einstiegspunkt.

Er darf ausschließlich lokale Voraussetzungen verwalten:

- PowerShell-Version prüfen,
- benötigte PowerShell-Module prüfen,
- fehlende Module im Scope `CurrentUser` installieren,
- keine Azure-Ressourcen verändern,
- keine UAC-Elevation auslösen,
- anschließend den eigentlichen Collector aufrufen.

### Collector

`Collect-AzureDocumentation.ps1` enthält die Azure-Inventarisierungsorchestrierung. Der Collector selbst installiert keine Dependencies und führt keine Self-Elevation durch.

## 2.2 Kein Self-Elevation

Das Projekt darf **keine automatische UAC-Elevation** durchführen.

Insbesondere nicht zulässig:

- `Start-Process ... -Verb RunAs`,
- Neustart des Skripts als Administrator,
- automatisches Nachladen eines administrativen Tokens.

Der normale Collector-Betrieb soll ohne lokale Administratorrechte möglich sein.

## 2.3 PowerShell 7

Mindestversion initial: **PowerShell 7.2**.

PowerShell 7 selbst wird **nicht automatisch installiert oder aktualisiert**. Ist die Mindestversion nicht vorhanden, bricht der Bootstrap mit einer verständlichen Meldung ab. Eine eventuell notwendige Installation von PowerShell 7 bleibt ein bewusster separater Arbeitsplatz-/Adminvorgang.

## 2.4 Dependency-Policy

Initial benötigte Module:

- `Az.Accounts`,
- `Az.ResourceGraph`.

Verhalten des Bootstrap:

1. Vorhandensein prüfen.
2. Vorhandene geeignete Installation weiterverwenden.
3. Fehlende Module ausschließlich über PowerShell Gallery mit `Install-Module -Scope CurrentUser` installieren.
4. Keine `AllUsers`-Installation.
5. Keine UAC-Elevation.
6. Nach Installation erneut prüfen und importieren.
7. Bei Fehler kontrolliert abbrechen.

Pester ist eine Entwicklungs-/Testabhängigkeit und wird nicht für einen normalen Collector-Lauf benötigt.

---

# 3. Kernprinzipien

## 3.1 Kundengenerisch

Keine fest codierten Kunden-, Tenant-, Subscription-, Resource-Group- oder Ressourcennamen im Core.

## 3.2 Tenantfähig

Ein Lauf besitzt genau einen Tenant-Kontext und kann darin eine oder mehrere Subscriptions erfassen. Ein späterer Batch-Modus kann mehrere Tenants nacheinander verarbeiten; Ergebnisse verschiedener Tenants bleiben getrennt.

## 3.3 Resource Graph First

Azure Resource Graph ist die bevorzugte Quelle für breite Inventarisierung. Az PowerShell oder später geprüfte REST-Aufrufe werden nur eingesetzt, wenn Resource Graph erforderliche Details nicht liefert.

## 3.4 Least Privilege

Lokale Administratorrechte sind für den normalen Collector-Lauf nicht vorgesehen. Azure-seitig soll Reader-orientierter Zugriff genügen, soweit ein Fachbereich keine zusätzlichen Leserechte benötigt.

## 3.5 Keine Secrets

Keine Kennwörter, Client Secrets, Storage Keys, SAS Tokens, Private Keys, Access Tokens, API Keys oder sonstigen Credential-Werte werden bewusst exportiert.

## 3.6 Reproduzierbarkeit

Stabile Felder, konsistente Dateinamen, definierte Sortierung, ISO-8601-Zeitstempel, Resource IDs und Schema-/Collector-Versionen.

## 3.7 Best Effort

Optionale Modulfehler sollen möglichst als Partial Collection behandelt werden. Read-only-Verifikationsfehler sind immer kritisch und blockieren den Lauf.

---

# 4. Repository-Struktur

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

# 5. Bedienung

## 5.1 Empfohlener Einstieg

```powershell
./Start-AzureInfrastructureCollector.ps1
```

Ablauf:

1. lokales Read-only-Gate,
2. PowerShell-Runtime prüfen,
3. Dependencies prüfen/installieren,
4. Collector starten,
5. Collector prüft Read-only erneut,
6. Azure Auth/Scope,
7. Inventarisierung,
8. Export.

## 5.2 Direkter Collector-Aufruf

`Collect-AzureDocumentation.ps1` bleibt für Entwicklung und vorbereitete Systeme direkt nutzbar. In diesem Fall müssen die Dependencies bereits vorhanden sein.

## 5.3 Parameter

Bootstrap und Collector unterstützen initial:

- `-TenantId`,
- `-SubscriptionId`,
- `-ResourceGroup`,
- `-OutputPath`,
- `-NonInteractive`.

Im `-NonInteractive`-Modus müssen Authentifizierung und Scope deterministisch vorliegen; es dürfen keine Eingabeprompts entstehen.

---

# 6. Authentifizierung und Azure-Kontext

Version 1 unterstützt interaktive Anmeldung über `Connect-AzAccount` und vorhandene Az-Kontexte.

Später möglich:

- Managed Identity,
- Service Principal,
- Azure Automation,
- CI/CD.

Credentials dürfen niemals im Repository hinterlegt werden.

---

# 7. Scope-Modell

```text
Tenant
  +-- Subscription A
  |    +-- Resource Group 1
  |    +-- Resource Group 2
  +-- Subscription B
       +-- Resource Group 3
```

Ressourcen verschiedener Tenants dürfen nicht ununterscheidbar in einem gemeinsamen Export vermischt werden.

---

# 8. Erfassungsumfang Version 1

## Core

Tenant, Subscriptions, Resource Groups, Regionen, Ressourcentypen, Tags, Resource IDs.

## Network

VNets, Subnets, Peerings, NICs, IP-Konfiguration, Public IPs, NSGs/Rules, Routes, NAT, Private Endpoints, Private DNS, Gateways, Load Balancer, Application Gateway, Firewall-Basisdaten.

## Compute

VMs, Size/SKU, OS/Image, Availability, NIC-Zuordnung, OS-/Data-Disks, Disk SKU/Size, optional Power State als Momentaufnahme.

## AVD

Workspaces, Host Pools, Application Groups, Session Hosts, Settings, Start VM on Connect, Scaling Plans und Beziehungen zur VM.

## Storage / Backup / Key Vault

Storage-Konfigurationsmetadaten, Backup-Vaults/-Policies/-Protected Items sowie Key-Vault-Konfiguration. Keine Blob-/Dateiinhalte, Backup-Inhalte, Secrets, Keys oder Private Keys.

## Security / Governance

RBAC Role Assignments, Role-Definition-Referenzen, Locks, Policy-/Initiative-Assignments; personenbezogene Identitätsdaten werden minimiert.

## Monitoring / Automation

Log Analytics, Diagnostic Settings, Action Groups, Alerts, Automation Accounts, Runbook-Metadaten, Schedules und Associations. Kein Runbook-Quellcode standardmäßig.

---

# 9. Export und Datenmodell

Ein Lauf erzeugt einen tenantbezogenen Exportordner mit:

```text
<Tenant>_<Timestamp>/
+-- readOnlyVerification.json
+-- manifest.json
+-- summary.json
+-- Inventory/
+-- Logs/
```

Spätere Fachmodule ergänzen eigene Unterordner.

Resource ID ist der bevorzugte technische Primärschlüssel für Beziehungen.

Arrays werden stabil sortiert. Nicht verfügbare Werte werden nicht erfunden.

---

# 10. Relationship Engine

Ziel ist ein einheitliches Beziehungsmodell, unter anderem:

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

# 11. Logging und Fehlerbehandlung

Logs enthalten mindestens Zeitstempel, Level, Modul/Aktion und Ergebnis; niemals Secrets oder Access Tokens.

Kritische Fehler:

- Read-only-Verifikation fehlgeschlagen,
- PowerShell-Mindestversion fehlt,
- erforderliche Dependency kann nicht bereitgestellt werden,
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
6  Read-only-Verifikation fehlgeschlagen
7  Runtime/Dependency-Voraussetzung fehlgeschlagen
```

---

# 12. Sicherheit des Exports

Exporte enthalten schützenswerte Infrastrukturinformationen und dürfen nicht unkontrolliert weitergegeben oder in öffentliche Git-Repositories committed werden. `Output/` bleibt von Git ausgeschlossen.

---

# 13. KI-Grenze

Der Collector benötigt keine KI. Die KI verarbeitet erst den deterministischen Export.

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
- [x] direkte REST-/CLI-/dynamische Ausführung im MVP blockieren
- [x] `Set-AzContext` nur `-Scope Process`
- [x] separater Prüfaufruf
- [x] Pester-Tests
- [x] GitHub Actions Gate
- [x] initiale manuelle Verifikation

## P0b – Bootstrap / Dependencies

- [ ] `Start-AzureInfrastructureCollector.ps1`
- [ ] `Collector.Bootstrap.psm1`
- [ ] PowerShell 7.2+ prüfen
- [ ] fehlende Runtime kontrolliert melden
- [ ] `Az.Accounts` automatisch `CurrentUser` installieren
- [ ] `Az.ResourceGraph` automatisch `CurrentUser` installieren
- [ ] Dependencies nach Installation erneut verifizieren
- [ ] keine Self-Elevation
- [ ] Bootstrap-Tests
- [ ] Read-only-Gate nach Bootstrap-Erweiterung erneut verifizieren

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

- [ ] Metadaten, Secret-Filtering verifizieren

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
4. Neue Azure-Aufrufe benötigen einen dokumentierten Read-only-Nachweis.
5. Unbekannte Azure-Aufrufe werden durch das Gate blockiert.
6. Bootstrap und Collector bleiben getrennte Verantwortlichkeiten.
7. Lokale Dependency-Installation nur `CurrentUser`.
8. Keine Self-Elevation.
9. PowerShell 7 wird nicht automatisch installiert.
10. Architektur-/Scope-Änderungen werden zuerst in diesem Dokument festgelegt.

---

# 16. Definition of Done für ein Collector-Modul

Ein Modul gilt erst als fertig, wenn:

- kundengenerisch,
- Multi-Subscription-fähig,
- Scope-Filter respektiert,
- Azure-Aufrufe read-only verifiziert,
- Fehler/Berechtigungen transparent,
- keine Secrets,
- stabile Daten/JSON,
- Unit Tests,
- Manifest-/Dokumentationsintegration,
- abschließende Read-only-Verifikation erfolgreich.

---

# 17. Definition of Done Version 1.0

Version 1.0 erfordert insbesondere:

1. kundengenerische Ausführung ohne lokale Administratorrechte für den normalen Lauf,
2. Bootstrap kann fehlende unterstützte PowerShell-Module im Benutzerkontext bereitstellen,
3. keine Self-Elevation,
4. Tenant-/Multi-Subscription-/RG-Scope,
5. alle geplanten Fachbereiche,
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

P0a und P0b sind vor dem ersten realen Azure-Test abzuschließen.

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

**Über allem steht: Ohne unmittelbar zuvor erfolgreich abgeschlossene Read-only-Verifikation darf kein ausführbarer Collector-Stand zur Ausführung freigegeben werden.**
