# AzureInfrastructureCollector – Umsetzungsplan

> **Status:** Source of Truth  
> **Repository:** `Vertax1337/AzureInfrastructureCollector`  
> **Default Branch:** `main`  
> **Dokumentstatus:** Verbindlicher Entwicklungsplan  
> **Stand:** 2026-08-10  
> **Initiale Zielversion:** `0.1.0`

---

# 0. OBERSTE REGEL – READ-ONLY MUSS VOR JEDER AZURE-AUSFÜHRUNGSFREIGABE VERIFIZIERT SEIN

> **Diese Regel hat Vorrang vor allen anderen Anforderungen, Architekturentscheidungen, Features, Entwicklungszielen und Zeitplänen dieses Projekts.**

Der **AzureInfrastructureCollector darf unter keinen Umständen Azure-Ressourcen, Azure-Konfigurationen, Azure-Datenbestände oder andere Azure-seitige Zustände verändern.**

Ein ausführbarer Stand darf erst dann für einen realen Azure-Lauf freigegeben werden, wenn die vorgeschriebene Pre-Azure-Validierung erfolgreich abgeschlossen wurde und sowohl die abschließende Read-only-Verifikation `READ-ONLY VERIFIED` als auch der Gesamtstatus `READY FOR AZURE TEST` erreicht wurden.

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
- lokale Installation explizit benötigter PowerShell-Abhängigkeiten im Benutzerkontext mit `-Scope CurrentUser`.

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
8. lokale Dependency-/Elevationspfade,
9. Änderungen seit der letzten Verifikation.

## 0.6 Verbindliche Statuswerte

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE DETECTED
Azure data mutations: NONE DETECTED
Control-plane write operations: NONE DETECTED
Data-plane write operations: NONE DETECTED
Local writes: approved local CurrentUser bootstrap/export operations only
```

```text
PRE-AZURE VALIDATION RESULT
Status: READY FOR AZURE TEST
Initial read-only gate: READ-ONLY VERIFIED
Pester: <version>; Failed: 0
Final read-only gate: READ-ONLY VERIFIED
Azure access performed: NO
Administrator elevation: NOT USED
```

> **Keine bestätigte Read-only-Verifikation und kein `READY FOR AZURE TEST` = keine Azure-Ausführungsfreigabe.**

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
Entwicklung / neuer ausführbarer Stand
   |
   v
Tools/Invoke-PreAzureValidation.ps1
   |
   +--> PowerShell 7.6 LTS prüfen
   +--> Read-only Gate #1
   +--> Pester 5.5.0+ prüfen
   +--> falls nötig Pester nur CurrentUser installieren
   +--> vollständige Pester-Suite
   +--> Read-only Gate #2
   |
   +--> READY FOR AZURE TEST
            |
            v
Start-AzureInfrastructureCollector.ps1
   |
   +--> PowerShell-Runtime-Preflight
   +--> Read-only Gate
   +--> Az.Accounts / Az.ResourceGraph prüfen
   +--> fehlende Module nur CurrentUser installieren
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

Die Pre-Azure-Validierung selbst führt **keine Azure-Authentifizierung und keine Azure-Abfrage** durch.

---

# 3. Lokale Voraussetzungen und Bootstrap

## 3.1 PowerShell Runtime

Verbindliche Mindest-Runtime: **PowerShell 7.6 LTS** (`pwsh.exe`, mindestens `7.6.0`).

Begründung: Der Collector soll nur auf einer von Microsoft aktuell unterstützten LTS-Runtime ausgeführt werden. PowerShell 7.2 ist nicht mehr freigegeben, da dessen Support beendet ist. PowerShell 6.x und Windows PowerShell 5.1 sind ebenfalls keine unterstützten Runtime-Pfade.

PowerShell selbst wird **nicht automatisch installiert oder aktualisiert**. Fehlt die Mindestversion, wird kontrolliert abgebrochen. Installation oder Upgrade von PowerShell bleibt ein bewusster separater Arbeitsplatz-/Adminvorgang.

## 3.2 Kein Self-Elevation

Das Projekt darf keine automatische UAC-Elevation durchführen.

Verboten sind insbesondere:

- `Start-Process ... -Verb RunAs`,
- Neustart als Administrator,
- automatisches Nachladen eines administrativen Tokens.

Der normale Collector-Lauf und die Pre-Azure-Validierung sollen ohne lokale Administratorrechte möglich sein.

## 3.3 Runtime-Dependencies

Initial benötigt der Collector:

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

## 3.4 Validierungs-Dependency Pester

Pester ist keine Runtime-Abhängigkeit des normalen Collectors, sondern die verpflichtende Testabhängigkeit der Pre-Azure-Validierung.

Aktuelle Mindestversion: **Pester 5.5.0**, zentral definiert als `validation.minimumPesterVersion` in `Config/collector.config.json`.

`Tools/Invoke-PreAzureValidation.ps1` darf fehlendes Pester ausschließlich mit `Install-Module -Scope CurrentUser` aus der bereits registrierten `PSGallery` installieren.

## 3.5 Vom Gate erzwungene lokale Grenze

Das Gate blockiert unter anderem:

- `Install-Module` ohne literal `-Scope CurrentUser`,
- `Update-Module`,
- `Uninstall-Module`,
- `Save-Module`,
- PowerShell-Repository-Registrierung/-Änderung,
- alternative Package-/PSResource-Mutationspfade,
- `Start-Process`,
- direkte REST/Web-Ausführung,
- Azure CLI,
- dynamische Befehlsausführung.

---

# 4. Pre-Azure-Validierung

Kanonischer Befehl:

```powershell
./Tools/Invoke-PreAzureValidation.ps1
```

Explizit aus einer anderen Shell:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tools\Invoke-PreAzureValidation.ps1
```

Ablauf:

```text
PowerShell 7.6 LTS
      |
      v
Read-only Gate #1
      |
      v
Pester vorhanden?
      |
      +-- nein --> CurrentUser installieren
      |
      v
Pester-Suite ./Tests
      |
      v
Read-only Gate #2
      |
      +-- alles erfolgreich --> READY FOR AZURE TEST
      |
      +-- Fehler/unklar ------> BLOCKED
```

Ein realer Azure-Test des aktuellen Standes ist nur zulässig, wenn:

- initiales Gate `READ-ONLY VERIFIED`,
- Pester-Fehleranzahl `0`,
- finales Gate `READ-ONLY VERIFIED`,
- Gesamtstatus `READY FOR AZURE TEST`.

Ändert sich anschließend ausführbarer Code, ist die Freigabe erneut durchzuführen.

`.github/workflows/read-only-gate.yml` verwendet denselben kanonischen Validierungspfad und besitzt nur `contents: read` auf das Repository.

---

# 5. Collector-Kernprinzipien

## 5.1 Kundengenerisch

Keine fest codierten Kunden-, Tenant-, Subscription-, Resource-Group- oder Ressourcennamen im Core.

## 5.2 Tenantfähig

Ein Lauf besitzt genau einen Tenant-Kontext und kann mehrere Subscriptions erfassen. Mehrere Tenants werden später nacheinander verarbeitet und nie ununterscheidbar in einem Export vermischt.

## 5.3 Resource Graph First

Azure Resource Graph ist die bevorzugte Quelle für breite Inventarisierung. Az PowerShell oder später geprüfte REST-Aufrufe werden nur verwendet, wenn Resource Graph erforderliche Details nicht liefert.

## 5.4 Least Privilege

Lokale Administratorrechte sind nicht vorgesehen. Azure-seitig soll Reader-orientierter Zugriff genügen, soweit einzelne Fachbereiche keine zusätzlichen Leserechte erfordern.

## 5.5 Keine Secrets

Keine Kennwörter, Client Secrets, Storage Keys, SAS Tokens, Private Keys, Access Tokens, API Keys oder sonstigen Credential-Werte werden bewusst exportiert.

## 5.6 Reproduzierbarkeit

Stabile Felder, konsistente Dateinamen, definierte Sortierung, ISO-8601-Zeitstempel, Resource IDs und Schema-/Collector-Versionen.

## 5.7 Best Effort

Optionale Modulfehler können Partial Collection ergeben. Read-only-/Pre-Azure-Verifikationsfehler sind immer kritisch.

---

# 6. Repository-Struktur

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
|   +-- Test-ReadOnlyCompliance.ps1
|   +-- Invoke-PreAzureValidation.ps1
+-- Docs/
```

---

# 7. Bedienung und Parameter

Bootstrap und Collector unterstützen initial:

- `-TenantId`,
- `-SubscriptionId`,
- `-ResourceGroup`,
- `-OutputPath`,
- `-NonInteractive`.

Der direkte Aufruf von `Collect-AzureDocumentation.ps1` bleibt für Entwicklung und vorbereitete Systeme möglich; dort müssen Runtime-Dependencies bereits vorhanden sein.

Im `-NonInteractive`-Modus dürfen keine Eingabeprompts erforderlich sein.

---

# 8. Authentifizierung und Azure-Kontext

Version 1 unterstützt interaktive Anmeldung über `Connect-AzAccount` und vorhandene Az-Kontexte.

Später möglich:

- Managed Identity,
- Service Principal,
- Azure Automation,
- CI/CD.

Credentials dürfen niemals im Repository hinterlegt werden.

---

# 9. Scope-Modell

```text
Tenant
  +-- Subscription A
  |    +-- Resource Group 1
  |    +-- Resource Group 2
  +-- Subscription B
       +-- Resource Group 3
```

---

# 10. Erfassungsumfang Version 1

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

# 11. Export und Datenmodell

```text
<Tenant>_<Timestamp>/
+-- readOnlyVerification.json
+-- manifest.json
+-- summary.json
+-- Inventory/
+-- Logs/
```

Resource ID ist der bevorzugte technische Primärschlüssel. Arrays werden stabil sortiert. Nicht verfügbare Werte werden nicht erfunden. `Output/` bleibt von Git ausgeschlossen.

---

# 12. Relationship Engine

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

# 13. Logging und Fehlerbehandlung

Logs enthalten Zeitstempel, Level, Modul/Aktion und Ergebnis; niemals Secrets oder Access Tokens.

Kritische Fehler:

- Read-only-Verifikation fehlgeschlagen,
- Pre-Azure-Validierung nicht erfolgreich,
- PowerShell-Mindestversion fehlt,
- Dependency kann nicht bereitgestellt werden,
- Azure-Authentifizierung nicht möglich,
- Tenant/Subscription nicht erreichbar,
- Core-Export nicht möglich.

Exit-Code-Kategorien:

```text
0   Erfolg / READY FOR AZURE TEST
1   Partial Success / Warnungen
2   Konfiguration
3   Auth/Berechtigung Core
4   lokaler Export/Dateisystem
5   unerwarteter interner Fehler
6   Read-only-Verifikation
7   PowerShell-Runtime
8   lokale Dependency/Validation-Dependency
9   Pester-Testfehler / Testzustand nicht beweisbar
10  Pre-Azure-/Read-only-Freigabe blockiert
```

---

# 14. KI-Grenze

Der Collector benötigt keine KI.

```text
Azure -> Collector -> JSON -> AI Documentation Pipeline -> Markdown/DOCX/PDF/Diagramme
```

Die KI darf keine nicht durch Quelldaten belegten Fakten erfinden.

---

# 15. Entwicklungsphasen

## P0 – Projektgrundlage
- [x] Repository
- [x] Source of Truth
- [x] README / .gitignore / Config
- [x] PowerShell-Runtime-Baseline: 7.6 LTS
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
- [x] lokaler standalone Read-only-Gate-Lauf mit `READ-ONLY VERIFIED` auf vorherigem Stand

## P0b – Bootstrap / Dependencies
- [x] `Start-AzureInfrastructureCollector.ps1`
- [x] `Collector.Bootstrap.psm1`
- [x] PowerShell 7.6 LTS prüfen
- [x] `Az.Accounts` automatisch `CurrentUser` installieren
- [x] `Az.ResourceGraph` automatisch `CurrentUser` installieren
- [x] Dependencies nach Installation erneut prüfen/importieren
- [x] keine Self-Elevation
- [x] keine `AllUsers`-Installation
- [x] keine automatische Repository-Mutation
- [x] Bootstrap-Tests implementiert
- [x] Read-only-Gate um Bootstrap-Grenze erweitert

## P0c – Pre-Azure Validation
- [x] `Tools/Invoke-PreAzureValidation.ps1`
- [x] Pester-Mindestversion zentral konfigurieren
- [x] fehlendes Pester automatisch nur `CurrentUser` installieren
- [x] initiales Read-only-Gate
- [x] vollständige Pester-Suite
- [x] finales Read-only-Gate
- [x] eindeutiger Status `READY FOR AZURE TEST`
- [x] GitHub Actions auf denselben kanonischen Pfad umstellen
- [ ] lokaler Lauf unter PowerShell 7.6 LTS liefert `READY FOR AZURE TEST`

## P1 – Core
- [x] Collector-Einstieg
- [x] Context/Auth
- [x] Tenant-/Subscription-Auswahl
- [x] RG-Scope
- [x] Output / Logging / Manifest-Grundstruktur
- [ ] Exit Codes vollständig im Collector harmonisieren
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
- [ ] vollständige finale Read-only-/Pre-Azure-Verifikation

---

# 16. Entwicklungsregeln

1. Keine kundenspezifischen Sonderfälle im Core.
2. Keine stillen Annahmen.
3. Keine Secrets in Source Control.
4. Neue Azure-Aufrufe benötigen dokumentierten Read-only-Nachweis.
5. Unbekannte Azure-Aufrufe werden blockiert.
6. Bootstrap und Collector bleiben getrennte Verantwortlichkeiten.
7. Lokale Dependency-Installation nur `CurrentUser`.
8. Keine Self-Elevation.
9. PowerShell wird nicht automatisch installiert oder aktualisiert.
10. Unterstützte Runtime ist PowerShell 7.6 LTS oder neuer, solange eine spätere Version explizit verifiziert ist.
11. Keine automatische PowerShell-Repository-Mutation.
12. Vor realen Azure-Läufen muss der aktuelle Stand `READY FOR AZURE TEST` erreichen.
13. Architektur-/Scope-Änderungen werden zuerst in diesem Dokument festgelegt.

---

# 17. Definition of Done Collector-Modul

Ein Modul gilt erst als fertig, wenn es kundengenerisch ist, Scope-Filter respektiert, Azure-Aufrufe read-only verifiziert sind, Fehler/Berechtigungen transparent behandelt werden, keine Secrets exportiert werden, Daten stabil sind, Tests vorhanden sind und die abschließende Pre-Azure-Validierung erfolgreich ist.

---

# 18. Definition of Done Version 1.0

Version 1.0 erfordert insbesondere:

1. normaler Lauf ohne lokale Administratorrechte,
2. unterstützte Runtime PowerShell 7.6 LTS,
3. Bootstrap kann unterstützte fehlende Module im Benutzerkontext bereitstellen,
4. keine Self-Elevation,
5. Tenant-/Multi-Subscription-/RG-Scope,
6. geplante Fachbereiche,
7. strukturierter Export mit Manifest/Summary/Relationships,
8. Secret Filtering und Berechtigungsfehler getestet,
9. realistischer Kundenexport erfolgreich,
10. KI-Dokumentation auf Exportbasis möglich,
11. finale vollständige Read-only-Verifikation liefert `READ-ONLY VERIFIED`,
12. finale Pre-Azure-/Release-Validierung liefert `READY FOR AZURE TEST`.

Ohne Punkte 11 und 12 gibt es keinen ausführbaren Release.

---

# 19. Aktuelle Priorität

```text
P0   Projektgrundlage
P0a  Read-only Verification Gate
P0b  Bootstrap / Dependency Handling
P0c  Pre-Azure Validation
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

**Vor dem ersten realen Azure-Test ist ausschließlich der lokale erfolgreiche Lauf von `Tools/Invoke-PreAzureValidation.ps1` unter PowerShell 7.6 LTS mit `Status: READY FOR AZURE TEST` offen.**

---

# 20. Offene Architekturentscheidungen

- exakte Mindest-/Pinning-Versionen der Az-Module,
- ZIP-Default,
- Identity Display Names / Microsoft Graph,
- Defender-for-Cloud-Detailtiefe,
- Resource Change History,
- Relationship-Schema,
- SemVer-Strategie,
- Repository-Lizenz.

---

# 21. Leitentscheidung

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

**Ohne unmittelbar zuvor erfolgreich abgeschlossene Pre-Azure-Validierung mit `READ-ONLY VERIFIED` und `READY FOR AZURE TEST` darf kein realer Azure-Lauf freigegeben werden.**
