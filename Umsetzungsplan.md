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
Pester: 6.0.1; Failed: 0
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
Start-AzureInfrastructureCollector.ps1
   |
   +--> PowerShell 7.6 LTS prüfen
   +--> automatische eingebettete Pre-Azure-Validierung
   |      +--> Read-only Gate #1
   |      +--> exakt Pester 6.0.1 prüfen
   |      +--> falls nötig exakt Pester 6.0.1 nur CurrentUser installieren
   |      +--> andere geladene Pester-Versionen aus der Session entfernen
   |      +--> exakt den Pester-6.0.1-Modulpfad importieren
   |      +--> vollständige Pester-Suite
   |      +--> Read-only Gate #2
   |      +--> READY FOR AZURE TEST oder Fail Closed
   |
   +--> Bootstrap Read-only Gate
   +--> Az.Accounts / Az.ResourceGraph prüfen
   +--> fehlende Module nur CurrentUser installieren
   +--> vorhandenen Azure-Kontext nutzen oder interaktiv authentifizieren
   +--> Browser/WAM-Login bei Bedarf auf Device Code zurückfallen
   |
   v
Collect-AzureDocumentation.ps1
   |
   +--> Read-only Gate erneut
   +--> Tenant / Subscription Scope
   +--> Azure Resource Graph / geprüfte Read-only Cmdlets
   +--> Core-Normalisierung
   +--> P3a Network-Normalisierung / Relationships
   +--> Collector.ExportSecurity
   |      +--> sensitive Property-Namen redigieren
   |      +--> sensitive Wertmuster redigieren
   |      +--> Resource-Group-Referenzen kanonisieren
   |      +--> lokale/operatorbezogene Exportmetadaten minimieren
   |
   v
Normalisiertes und gehärtetes JSON-Modell
   |
   +--> readOnlyVerification.json
   +--> manifest.json
   +--> summary.json
   +--> Inventory/resourceGroups.json
   +--> Inventory/resources.json
   +--> Inventory/network.json
   +--> Logs
```

`Tools/Invoke-PreAzureValidation.ps1` bleibt separat für Diagnose und CI nutzbar. Die Pre-Azure-Validierung selbst führt **keine Azure-Authentifizierung und keine Azure-Abfrage** durch.

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

Verbindliche Validierungsversion: **Pester 6.0.1**, zentral definiert als `validation.requiredPesterVersion` in `Config/collector.config.json`.

Die Version wird bewusst exakt gepinnt. Eine zukünftige Pester-Major- oder Minor-Version wird nicht automatisch als validiert betrachtet.

`Tools/Invoke-PreAzureValidation.ps1`:

1. prüft exakt auf Pester 6.0.1,
2. installiert bei Bedarf exakt diese Version aus der bereits registrierten `PSGallery`,
3. verwendet ausschließlich `Install-Module -RequiredVersion 6.0.1 -Scope CurrentUser`,
4. entfernt bereits geladene Pester-Versionen aus der aktuellen Validierungssession,
5. importiert exakt den gefundenen Pester-6.0.1-Modulpfad,
6. verifiziert, dass die benötigten Testbefehle aus dem Modul `Pester` stammen,
7. führt anschließend erst die Testsuite aus.

Die Testsuite verwendet Pester-6-Syntax. Insbesondere wird das in Pester 6 entfernte `Assert-MockCalled` nicht verwendet; Mock-Aufrufe werden mit `Should -Invoke` geprüft.

Ein altes systemweit vorhandenes Pester, z. B. 3.4.0, muss nicht deinstalliert werden und darf die aktuelle Validierung nicht beeinflussen.

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

Im normalen Bedienweg wird die komplette Pre-Azure-Validierung automatisch von `Start-AzureInfrastructureCollector.ps1` ausgeführt. Ein separater Operator-Schritt ist nicht erforderlich.

Normaler Start:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-AzureInfrastructureCollector.ps1
```

Separater Diagnose-/CI-Aufruf:

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
Pester 6.0.1 vorhanden?
      |
      +-- nein --> exakt 6.0.1 CurrentUser installieren
      |
      v
Pester-Session isolieren / exakten Modulpfad importieren
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
- Pester-Version exakt `6.0.1`,
- Pester-Fehleranzahl `0`,
- finales Gate `READ-ONLY VERIFIED`,
- Gesamtstatus `READY FOR AZURE TEST`.

Ändert sich anschließend ausführbarer Code oder die Validierungsversion, erfolgt die Freigabe beim nächsten normalen Start automatisch erneut, bevor Azure angesprochen wird.

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

Neben sensitiven Feld-/Tag-Namen wird der finale Export zusätzlich anhand starker Wertmuster geprüft. Die zentrale Exporthärtung gilt auch für später hinzukommende Fachmodule.

Für P3 gilt zusätzlich: `Microsoft.Network/connections.properties.sharedKey` darf weder abgefragt noch normalisiert oder exportiert werden.

## 5.6 Reproduzierbarkeit

Stabile Felder, konsistente Dateinamen, definierte Sortierung, ISO-8601-Zeitstempel, Resource IDs und Schema-/Collector-Versionen. Resource-Group-Referenzen in Ressourcen werden subscriptionbezogen gegen `resourceGroups.json` kanonisiert.

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
|   +-- Collector.ExportSecurity.psm1
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
|   +-- Resources.kql
|   +-- ResourceGroups.kql
|   +-- Network.kql
+-- Config/
+-- Schemas/
+-- Tests/
+-- Tools/
|   +-- Test-ReadOnlyCompliance.ps1
|   +-- Invoke-PreAzureValidation.ps1
+-- Docs/
|   +-- P3-Network.md
```

---

# 7. Bedienung und Parameter

Bootstrap und Collector unterstützen initial:

- `-TenantId`,
- `-SubscriptionId`,
- `-ResourceGroup`,
- `-OutputPath`,
- `-NonInteractive`.

Ohne `-ResourceGroup` wird standardmäßig der vollständige Scope der ausgewählten Subscription(s) erfasst. Resource-Group-Filtering ist explizit opt-in und erzeugt im Standardlauf keinen versteckten Eingabeprompt.

Der direkte Aufruf von `Collect-AzureDocumentation.ps1` bleibt für Entwicklung und vorbereitete Systeme möglich; dort müssen Runtime-Dependencies bereits vorhanden sein.

Im `-NonInteractive`-Modus dürfen keine Eingabeprompts erforderlich sein.

---

# 8. Authentifizierung und Azure-Kontext

Version 1 unterstützt vorhandene Az-Kontexte und interaktive Anmeldung über `Connect-AzAccount`. Schlägt der normale Browser/WAM-Pfad fehl, verwendet der Bootstrap als Fallback `Connect-AzAccount -UseDeviceAuthentication`; der Kontext bleibt auf `Scope Process` begrenzt.

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

### P3a – Network Topology Foundation

- VNets und Address Spaces,
- Subnets einschließlich NSG-/Route-Table-/NAT-Referenz, Service Endpoints und Delegations-Metadaten,
- VNet Peerings und Peering-Zustand/-Optionen,
- NICs und IP-Konfigurationen,
- Public IPs,
- NSGs und benutzerdefinierte Security Rules,
- Route Tables und Routes,
- Virtual Network Gateways,
- Local Network Gateways,
- Connections ohne `sharedKey`,
- Network Watcher,
- explizite Resource-ID-basierte Relationships.

### P3b – Erweiterte Netzwerkdienste

Nach erfolgreicher P3a-Validierung: Private Endpoints, Private DNS/VNet Links, NAT Gateways als eigene Ressourcen, Load Balancer, Application Gateway, Azure Firewall/Firewall-Policy-Referenzen und weitere sicher explizit projizierbare Netzwerkbeziehungen.

Vollständige rohe `properties`-Blöcke werden auch in P3 nicht als Abkürzung exportiert.

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
|   +-- resourceGroups.json
|   +-- resources.json
|   +-- network.json
+-- Logs/
```

Resource ID ist der bevorzugte technische Primärschlüssel. Arrays werden stabil sortiert. Nicht verfügbare Werte werden nicht erfunden. `Output/` bleibt von Git ausgeschlossen.

`Inventory/network.json` enthält in P3a die Sammlungen `virtualNetworks`, `subnets`, `peerings`, `networkInterfaces`, `ipConfigurations`, `networkSecurityGroups`, `securityRules`, `publicIpAddresses`, `routeTables`, `routes`, `virtualNetworkGateways`, `localNetworkGateways`, `connections`, `networkWatchers` und `relationships` sowie eine eigene Summary.

Export-Minimierung:

- lokale Repository-/Arbeitsplatzpfade werden nicht in `readOnlyVerification.json` ausgegeben,
- das ausführende Azure-Konto/UPN wird nicht in `manifest.json` ausgegeben,
- Tenant-, Subscription- und Resource IDs bleiben als technische Korrelationsschlüssel erhalten,
- Network-Abfragen projizieren nur explizit freigegebene Felder,
- Connection Shared Keys werden nicht abgefragt.

---

# 12. Relationship Engine

Zielbeziehungen unter anderem:

```text
VNet -> ContainsSubnet -> Subnet
VNet -> PeeredWith -> VNet
Subnet -> SecuredBy -> NSG
Subnet -> UsesRouteTable -> Route Table
Subnet -> UsesNatGateway -> NAT Gateway
NIC -> AttachedToVm -> VM
NIC -> SecuredBy -> NSG
NIC -> HasIpConfiguration -> IP Configuration
IP Configuration -> AttachedToSubnet -> Subnet
IP Configuration -> UsesPublicIp -> Public IP
NSG -> ContainsSecurityRule -> Security Rule
Route Table -> ContainsRoute -> Route
Virtual Network Gateway -> AttachedToSubnet -> Subnet
Virtual Network Gateway -> UsesPublicIp -> Public IP
Connection -> UsesVirtualNetworkGateway -> Virtual Network Gateway
Connection -> UsesLocalNetworkGateway -> Local Network Gateway
VM -> Managed Disk
Private Endpoint -> Target Resource
AVD Session Host -> VM
Diagnostic Setting -> Destination
Backup -> Protected Resource
```

P3a verwendet bereits ein Network-spezifisches Relationship-Array. P9 vereinheitlicht später die Relationship-Schemata aller Fachmodule.

---

# 13. Logging und Fehlerbehandlung

Logs enthalten Zeitstempel, Level, Modul/Aktion und Ergebnis; niemals Secrets oder Access Tokens.

Der normale Collector zeigt zusätzlich sichtbare Phasenmeldungen und Objektzähler, damit längere ARG-/Exportvorgänge nicht wie ein stiller Hänger wirken. Mit P3a umfasst der normale Collector fünf sichtbare Phasen.

Kritische Fehler:

- Read-only-Verifikation fehlgeschlagen,
- Pre-Azure-Validierung nicht erfolgreich,
- PowerShell-Mindestversion fehlt,
- Dependency kann nicht bereitgestellt werden,
- Azure-Authentifizierung nicht möglich,
- Tenant/Subscription nicht erreichbar,
- Core-Export nicht möglich.

Ein isolierter P3a-Netzwerkfehler darf bei erfolgreichem Core-Inventar zu `PartialSuccess` führen, nicht zu einem stillen Verlust des Core-Exports.

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

Die KI darf keine nicht durch Quelldaten belegten Fakten erfinden. Insbesondere sollen Netzwerkbeziehungen soweit technisch möglich explizit als Resource-ID-Relationships vorliegen und nicht aus Namenskonventionen erraten werden.

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
- [x] realer Collector-Lauf bestätigt erneut ausschließlich freigegebene Read-only-Pfade

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
- [x] interaktiver Login mit vorhandener Account-Auswahl im Real-Run bestätigt

## P0c – Pre-Azure Validation
- [x] `Tools/Invoke-PreAzureValidation.ps1`
- [x] Pester-Version exakt auf 6.0.1 pinnen
- [x] fehlendes Pester 6.0.1 automatisch nur `CurrentUser` installieren
- [x] geladene Pester-Versionen vor Testlauf isolieren
- [x] Pester-6-Testsyntax (`Should -Invoke`) verwenden
- [x] initiales Read-only-Gate
- [x] vollständige Pester-Suite
- [x] finales Read-only-Gate
- [x] eindeutiger Status `READY FOR AZURE TEST`
- [x] GitHub Actions auf denselben kanonischen Pfad umstellen
- [x] automatische lokale Validierung unter PowerShell 7.6.4: Pester 6.0.1, 19/19 Tests, beide Gates `READ-ONLY VERIFIED` auf dem ersten Real-Run-Stand

## P1 – Core
- [x] Collector-Einstieg
- [x] Context/Auth
- [x] Tenant-/Subscription-Auswahl
- [x] RG-Scope
- [x] Output / Logging / Manifest-Grundstruktur
- [x] sichtbare Phasen-/Fortschrittsausgabe im Collector
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
- [x] erster realer Integrationstest: 1 Subscription, 12 Resource Groups, 134 Ressourcen, 0 Fehler, `Success`, Laufzeit 00:03
- [x] erster Export strukturell geprüft: JSON/Counts/IDs/Summary/Manifest intern konsistent, keine offensichtlichen Secret-Leaks
- [ ] fachliche Stichprobe der Ressourcenzahlen gegen Azure-Iststand

## P2a – Export-Härtung vor P3
- [x] Resource-Group-Namen subscriptionbezogen gegen `resourceGroups.json` kanonisieren
- [x] lokalen `repositoryRoot` aus `readOnlyVerification.json` entfernen
- [x] ausführendes Azure-Konto/UPN aus `manifest.json` entfernen
- [x] zentrale wertbasierte Secret-Redaction ergänzen
- [x] starke Muster für SAS/signierte URLs, Account Keys/Connection Strings, Private Keys, JWTs und eingebettete Credentials konfigurieren
- [x] normale HTTPS-Werte explizit als Nicht-Secret testen
- [x] dedizierte Unit-Tests für Export-Härtung einschließlich Array-Typstabilität ergänzen
- [x] gehärteter Export in wiederholten Real-Runs bestätigt: 12 Resource Groups, 134 Ressourcen, 0 Fehler, stabile IDs/Counts
- [x] RG-Casing, Metadaten-Minimierung, Secret-Leakage und `[]`-Array-Typstabilität im dritten Real-Export bestätigt

## P3 – Netzwerk

### P3a – Network Topology Foundation
- [x] Architektur und Sicherheitsgrenze dokumentiert (`Docs/P3-Network.md`)
- [x] `Queries/Network.kql` mit expliziter Safe-Projection
- [x] `Collector.Network.psm1` für Normalisierung und Relationships
- [x] `Inventory/network.json` in normalen Collector integriert
- [x] Network-Summary in `summary.json` integriert
- [x] `sharedKey` aus Query und Schema explizit ausgeschlossen
- [x] sechs dedizierte P3a-Unit-Tests ergänzt
- [x] statische Read-only-Gegenprüfung: keine neuen Azure-/REST-/CLI-/SDK-Schreibpfade
- [ ] aktuelle automatische Pre-Azure-Validierung erfolgreich (`READ-ONLY VERIFIED`, 0 Testfehler, `READY FOR AZURE TEST`)
- [ ] erster P3a-Real-Export erzeugt und `network.json` fachlich/strukturell geprüft

### P3b – Erweiterte Netzwerkdienste
- [ ] Private Endpoints / Private DNS / VNet Links
- [ ] NAT Gateways als eigene Ressourcen
- [ ] Load Balancer
- [ ] Application Gateway
- [ ] Azure Firewall / Firewall Policy Referenzen
- [ ] zusätzliche Relationships und Real-Export-Validierung

> **P3b beginnt erst nach erfolgreicher P3a-Pre-Azure-Validierung und geprüftem P3a-Real-Export.**

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
- [ ] weitergehende Secret Leakage Tests mit späteren Detailmodulen
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
11. Pester ist für die Pre-Azure-Validierung exakt auf 6.0.1 gepinnt; Versionsänderungen benötigen erneute Verifikation.
12. Keine automatische PowerShell-Repository-Mutation.
13. Vor realen Azure-Läufen muss der aktuelle Stand `READY FOR AZURE TEST` erreichen; im normalen Startpfad wird dies automatisch erzwungen.
14. Architektur-/Scope-Änderungen werden zuerst in diesem Dokument festgelegt.
15. Jeder Fachmodul-Export muss vor dem Schreiben durch die zentrale Export-Härtung laufen.
16. P3/P4 dürfen keine parallelen Sonderwege für Secret-Filtering oder RG-Normalisierung einführen.
17. Network Connections dürfen `sharedKey` weder abfragen noch exportieren.
18. Netzwerkbeziehungen werden soweit möglich über Resource IDs und nicht über Namensheuristiken modelliert.

---

# 17. Definition of Done Collector-Modul

Ein Modul gilt erst als fertig, wenn es kundengenerisch ist, Scope-Filter respektiert, Azure-Aufrufe read-only verifiziert sind, Fehler/Berechtigungen transparent behandelt werden, keine Secrets exportiert werden, Daten stabil sind, die zentrale Export-Härtung verwendet wird, Tests vorhanden sind und die abschließende Pre-Azure-Validierung erfolgreich ist.

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
P2a  Export-Härtung vor P3
P3a  Network Topology Foundation
P3b  Erweiterte Netzwerkdienste
P4   Compute
P5   AVD
P6   Storage / Backup / Key Vault
P7   Security / Governance
P8   Monitoring / Automation
P9   Relationship Engine
P10  Tests / Härtung
P11  Release 1.0
```

**Aktueller nächster Schritt:** Den neuen P3a-Stand über den normalen Ein-Befehl-Start ausführen. Die automatisch eingebettete Pre-Azure-Validierung muss erneut `READ-ONLY VERIFIED` / `READY FOR AZURE TEST` liefern. Mit den sechs neuen Network-Tests werden auf Basis des zuletzt bestätigten Standes 33 erfolgreiche Tests erwartet. Erst danach darf der reale P3a-Azure-Lauf fortgesetzt werden. Anschließend wird `Inventory/network.json` auf Counts, Relationships, RG-Kanonisierung, Schema-Stabilität und Secret-Leakage geprüft.

---

# 20. Offene Architekturentscheidungen

- exakte Mindest-/Pinning-Versionen der Az-Module,
- ZIP-Default,
- Identity Display Names / Microsoft Graph,
- Defender-for-Cloud-Detailtiefe,
- Resource Change History,
- vereinheitlichtes Relationship-Schema für P9,
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
JSON normalisiert, verknüpft und härtet die Fakten
        ->
KI interpretiert und formuliert
        ->
Dokumente und Diagramme präsentieren das Ergebnis
```

**Ohne unmittelbar zuvor erfolgreich abgeschlossene Pre-Azure-Validierung mit `READ-ONLY VERIFIED` und `READY FOR AZURE TEST` darf kein realer Azure-Lauf freigegeben werden.**
