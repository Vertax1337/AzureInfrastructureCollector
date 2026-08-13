# AzureInfrastructureCollector – Umsetzungsplan

> **Status:** Source of Truth  
> **Repository:** `Vertax1337/AzureInfrastructureCollector`  
> **Default Branch:** `main`  
> **Dokumentstatus:** Verbindlicher Entwicklungsplan  
> **Stand:** 2026-08-13  
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
   +--> P3 Network-Normalisierung / Relationships (P3a + P3b)
   +--> P4 Compute-Normalisierung / Relationships
   +--> P5 AVD-Normalisierung / Relationships
   +--> P6 Storage-Normalisierung / Relationships
   +--> P6 Backup-Normalisierung / Relationships
   +--> P6 Key-Vault-Normalisierung / Relationships
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
   +--> Inventory/compute.json
   +--> Inventory/avd.json
   +--> Inventory/storage.json
   +--> Inventory/backup.json
   +--> Inventory/keyVault.json
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

Für P3 gilt zusätzlich:

- `Microsoft.Network/connections.properties.sharedKey` darf weder abgefragt noch normalisiert oder exportiert werden,
- Private-Link-`requestMessage` und Connection-State-Beschreibungen werden nicht normalisiert/exportiert,
- Application-Gateway-Zertifikatsmaterial wird nicht normalisiert/exportiert,
- Azure-Firewall-Regelkollektionen werden in P3b nicht normalisiert/exportiert,
- Firewall-Policy-Transport-Security-/Zertifikatsdaten werden in P3b nicht normalisiert/exportiert.

Für P4 gilt zusätzlich:

- VM `osProfile`, Administrator-/SSH-Konfiguration und `userData` werden nicht abgefragt/exportiert,
- VM Extensions und Restore Point Collections gehören nicht zum P4-Scope,
- Boot-Diagnostics-Storage-URIs werden nicht exportiert,
- Key-/Secret-URLs und `encryptionSettingsCollection` werden nicht exportiert,
- verschachtelte Data-Disk-Objekte werden auf explizit freigegebene Metadaten reduziert; Unmanaged-VHD-/Image-URIs und Disk-Encryption-Set-Details werden nicht normalisiert/exportiert.

Für P5 gilt zusätzlich:

- Host-Pool-Registration-Informationen und Registration Tokens werden nicht abgefragt/exportiert,
- SSO-Secret-Key-Vault-Pfade, VM Templates und rohe `customRdpProperty`-Freitexte werden nicht exportiert,
- Session-Host `assignedUser`, interne Object IDs/VM GUIDs, Health-Check-Detailobjekte und Update-Fehlermeldungen werden nicht exportiert,
- einzelne AVD User Sessions und deren Benutzeridentitäten gehören nicht zum P5-Scope,
- veröffentlichte Application-Child-Ressourcen mit File Paths/Command-Line-Argumenten gehören nicht zum P5-Scope,
- Scaling-Plan-Benachrichtigungstexte werden nicht exportiert.

Für P6 gilt zusätzlich:

- Storage Account Keys, `listKeys`, SAS/SharedAccessSignature und Connection Strings werden nicht abgefragt/exportiert,
- vollständige Storage-Rohproperties und CMK-/Key-Vault-Key-URIs werden nicht exportiert,
- Backup `datasourceAuthCredentials`, Secret-Store-Werte, CMK-Key-Material und Identity-Detailobjekte werden nicht exportiert,
- Backup-Job-Historie und Restore Requests gehören nicht zum P6-Scope,
- Key Vault Secret Values, Key Material, Certificate Private Keys/PFX und Keys-/Secrets-/Certificates-Data-Plane-Listen werden nicht abgefragt/exportiert,
- Key-Vault-`accessPolicies`, Object-/Tenant-IDs aus Access Policies, Vault URI sowie Secret-/Key-URIs werden nicht exportiert.

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
|   +-- Collector.KeyVault.psm1
|   +-- Collector.Security.psm1
|   +-- Collector.Monitoring.psm1
|   +-- Collector.Automation.psm1
|
+-- Queries/
|   +-- Resources.kql
|   +-- ResourceGroups.kql
|   +-- Network.kql
|   +-- Compute.kql
|   +-- AVD.kql
|   +-- AVD.SessionHosts.kql
|   +-- Storage.kql
|   +-- KeyVault.kql
|   +-- Backup.TopLevel.kql
|   +-- Backup.Resources.kql
+-- Config/
+-- Schemas/
+-- Tests/
+-- Tools/
|   +-- Test-ReadOnlyCompliance.ps1
|   +-- Invoke-PreAzureValidation.ps1
+-- Docs/
|   +-- P3-Network.md
|   +-- P4-Compute.md
|   +-- P5-AVD.md
|   +-- P6-Storage-Backup-KeyVault.md
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
- Local Network Gateways einschließlich IP-/FQDN-Endpunkt,
- Connections ohne `sharedKey`,
- Network Watcher,
- explizite Resource-ID-basierte Relationships.

### P3b – Erweiterte Netzwerkdienste

P3b erweitert dasselbe Network-Modell um:

- Private Endpoints und normalisierte Private-Link-Verbindungen,
- Private DNS Zones und VNet Links,
- NAT Gateways als eigene Ressourcen inklusive Public-IP-/Public-IP-Prefix-Referenzen,
- Load Balancer mit Frontends, Backend Pools/Adressen, Rules, Probes und Outbound Rules,
- Application Gateways mit IP-/Frontend-/Port-/Backend-/Listener-/Routing-/Probe-/Path-Map-Struktur,
- Azure Firewalls mit SKU, Threat-Intel-Modus, Policy-/Virtual-Hub-/Subnet-/Public-IP-Referenzen,
- Firewall Policies mit SKU-/Threat-Intel-/Base-Policy-Metadaten,
- zusätzliche deterministische Resource-ID-basierte Relationships.

P3b erfasst bewusst keine Application-Gateway-Zertifikatsinhalte, keine Azure-Firewall-Regelkollektionen und keine Firewall-Policy-Transport-Security-/Zertifikatsdaten. Vollständige rohe `properties`-Blöcke werden auch in P3 nicht als Abkürzung exportiert.

## Compute

P4 erfasst kundengenerisch:

- Virtual Machines,
- VM Size,
- Provisioning State,
- Availability Zones und Availability-Set-Referenzen,
- Marketplace-/Gallery-Image-Metadaten,
- NIC-Referenzen,
- OS-Disk-Metadaten und Managed-Disk-ID,
- Data-Disk-Metadaten und Managed-Disk-IDs,
- Managed Disks mit SKU/Tier/Größe/OS-Type/Disk-State/Managed-By,
- Availability Sets mit Fault-/Update-Domain-Counts, VM-Referenzen und optionaler Proximity-Placement-Group-ID,
- optionalen VM Power State als Best-Effort-Momentaufnahme.

Der Power State ist kein historischer Laufzeitnachweis. Ein nicht von Azure Resource Graph zurückgegebener Zustand bleibt leer und wird nicht interpretiert. VM Extensions, Restore Point Collections, `osProfile`, Boot-Diagnostics-URIs und Secret-/Key-/Encryption-Detaildaten sind bewusst nicht Teil von P4.

## AVD

P5 erfasst kundengenerisch:

- Workspaces einschließlich Application-Group-Referenzen,
- Host Pools einschließlich Host-Pool-Type, Load-Balancing, Max-Session-Limit, Public Network Access und Start VM on Connect,
- Application Groups einschließlich Type, Host-Pool-Referenz und Show In Feed,
- Session Hosts einschließlich technischer Status-/Session-/Agent-/OS-/Heartbeat-Metadaten und direkter VM-Resource-ID,
- Scaling Plans einschließlich Host-Pool-Referenzen, Zeitzone und technischen Scaling-Schedule-Parametern,
- Resource-ID-basierte Beziehungen zwischen Workspace, Application Group, Host Pool, Session Host, P4-VM und Scaling Plan.

Top-Level-AVD-Ressourcen werden aus `Resources` gelesen; Session Hosts werden über `DesktopVirtualizationResources` erfasst. P5 exportiert keine User Sessions, Assigned Users, Registration Tokens, SSO-Secret-Pfade, VM Templates, rohe RDP-Freitexte, Application-Command/File-Paths, Health-/Update-Fehlermeldungstexte oder Scaling-Notification-Freitexte.

## Storage / Backup / Key Vault

P6 besteht aus drei getrennten normalisierten Domänen.

### Storage

Erfasst werden `Microsoft.Storage/storageAccounts` mit Konfigurationsmetadaten wie Kind, SKU/Redundanz, Access Tier, TLS/HTTPS, Public Network Access, Shared-Key-/Blob-Public-Access-Konfiguration, OAuth-Default, HNS/Data Lake Gen2, NFS/SFTP und Network ACLs. VNet/Subnet-Regeln werden als ARM IDs normalisiert.

Beziehung:

```text
Storage Account -> AllowsSubnet -> P3 Subnet
```

### Backup

Top-Level-Vaults werden aus `Resources` gelesen; Policies und Protected Items/Backup Instances werden separat aus `RecoveryServicesResources` gelesen und erst lokal zusammengeführt.

Erfasst werden:

- Recovery Services Vaults,
- Data Protection Backup Vaults,
- Backup Policies,
- Recovery Services Protected Items,
- Data Protection Backup Instances,
- Protection State und Last Recovery Point als Momentaufnahme,
- Resource-ID-basierte Policy-, Vault- und Protected-Resource-Beziehungen.

Beziehungen:

```text
Vault -> ContainsBackupPolicy -> Backup Policy
Recovery Services Vault -> ContainsProtectedItem -> Protected Item
Backup Vault -> ContainsBackupInstance -> Backup Instance
Protected Item / Backup Instance -> UsesBackupPolicy -> Backup Policy
Protected Item / Backup Instance -> ProtectsResource -> Azure Resource
```

### Key Vault

Erfasst werden ausschließlich Vault-Konfigurationsmetadaten wie SKU, RBAC-vs-Access-Policy-Modell, Soft Delete, Purge Protection, Retention, Public Network Access und Network ACLs. Key-/Secret-/Certificate-Inhalte werden nicht gelesen.

Beziehung:

```text
Key Vault -> AllowsSubnet -> P3 Subnet
```

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
|   +-- compute.json
|   +-- avd.json
|   +-- storage.json
|   +-- backup.json
|   +-- keyVault.json
+-- Logs/
```

Resource ID ist der bevorzugte technische Primärschlüssel. Arrays werden stabil sortiert. Nicht verfügbare Werte werden nicht erfunden. `Output/` bleibt von Git ausgeschlossen.

`Inventory/network.json` enthält nach P3a/P3b insbesondere:

- `virtualNetworks`, `subnets`, `peerings`,
- `networkInterfaces`, `ipConfigurations`,
- `networkSecurityGroups`, `securityRules`,
- `publicIpAddresses`, `routeTables`, `routes`,
- `virtualNetworkGateways`, `localNetworkGateways`, `connections`, `networkWatchers`,
- `privateEndpoints`, `privateLinkConnections`,
- `privateDnsZones`, `privateDnsVirtualNetworkLinks`,
- `natGateways`,
- `loadBalancers`, `loadBalancerFrontendIpConfigurations`, `loadBalancerBackendPools`, `loadBalancerBackendAddresses`, `loadBalancerRules`, `loadBalancerProbes`, `loadBalancerOutboundRules`,
- `applicationGateways`, `applicationGatewayIpConfigurations`, `applicationGatewayFrontendIpConfigurations`, `applicationGatewayFrontendPorts`, `applicationGatewayBackendPools`, `applicationGatewayBackendAddresses`, `applicationGatewayBackendHttpSettings`, `applicationGatewayHttpListeners`, `applicationGatewayRequestRoutingRules`, `applicationGatewayProbes`, `applicationGatewayUrlPathMaps`, `applicationGatewayPathRules`,
- `azureFirewalls`, `azureFirewallIpConfigurations`, `firewallPolicies`,
- `relationships`,
- eine Network-Summary mit den jeweiligen Counts.

`Inventory/compute.json` enthält nach P4 insbesondere:

- `virtualMachines` mit `imageReference`, `osDisk`, `networkInterfaces` und `dataDisks`,
- `managedDisks`,
- `availabilitySets`,
- `relationships`,
- eine Compute-Summary mit VM-/Disk-/Availability-/Referenz-/Power-State-/Relationship-Counts.

`Inventory/avd.json` enthält nach P5 insbesondere:

- `workspaces`,
- `hostPools`,
- `applicationGroups`,
- `sessionHosts`,
- `scalingPlans`,
- `relationships`,
- eine AVD-Summary mit Ressourcen-, Referenz-, Schedule-, Start-VM-on-Connect- und Relationship-Counts.

`Inventory/storage.json` enthält nach P6 insbesondere:

- `storageAccounts`,
- `relationships`,
- eine Storage-Summary.

`Inventory/backup.json` enthält nach P6 insbesondere:

- `recoveryServicesVaults`,
- `backupVaults`,
- `backupPolicies`,
- `recoveryProtectedItems`,
- `dataProtectionBackupInstances`,
- `relationships`,
- eine Backup-Summary.

`Inventory/keyVault.json` enthält nach P6 insbesondere:

- `keyVaults`,
- `relationships`,
- eine Key-Vault-Summary.

Export-Minimierung:

- lokale Repository-/Arbeitsplatzpfade werden nicht in `readOnlyVerification.json` ausgegeben,
- das ausführende Azure-Konto/UPN wird nicht in `manifest.json` ausgegeben,
- Tenant-, Subscription- und Resource IDs bleiben als technische Korrelationsschlüssel erhalten,
- Network-, Compute-, AVD-, Storage-, Backup- und Key-Vault-Abfragen projizieren nur explizit freigegebene Felder,
- Connection Shared Keys werden nicht abgefragt,
- Private-Link-Freitext wird nicht normalisiert/exportiert,
- Application-Gateway-Zertifikatsmaterial wird nicht normalisiert/exportiert,
- Azure-Firewall-Regelkollektionen werden in P3b nicht normalisiert/exportiert,
- P4 exportiert kein `osProfile`, keine VM-Extensions/-ProtectedSettings, keine Unmanaged-VHD-/Image-URIs und keine Key-/Secret-URLs oder Disk-Encryption-Detailobjekte,
- P5 exportiert keine Registration-/SSO-Secrets, VM-Template-/RDP-Freitexte, Assigned Users/User Sessions, Health-/Update-Fehlertexte, Application-Ausführungspfade oder Scaling-Notification-Texte,
- P6 exportiert keine Storage Keys/SAS/Connection Strings, keine Backup-Credentials/Secret-Store-Werte/CMK-Key-Material und keine Key-Vault-Secret-/Key-/Certificate-Inhalte oder Access-Policy-Identitätsdetails.

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

Private Endpoint -> AttachedToSubnet -> Subnet
Private Endpoint -> ContainsPrivateLinkConnection -> Private Link Connection
Private Link Connection -> ConnectsToResource -> Target Resource
Private Endpoint -> ConnectsToResource -> Target Resource
Private DNS Zone -> ContainsVirtualNetworkLink -> VNet Link
Private DNS VNet Link -> LinkedToVNet -> VNet
Private DNS Zone -> LinkedToVNet -> VNet
NAT Gateway -> UsesPublicIp -> Public IP
NAT Gateway -> UsesPublicIpPrefix -> Public IP Prefix

Load Balancer -> ContainsLoadBalancerFrontend -> Frontend
Load Balancer -> ContainsLoadBalancerBackendPool -> Backend Pool
Load Balancer -> ContainsLoadBalancerRule -> Rule
Load Balancer -> ContainsLoadBalancerProbe -> Probe
Load Balancer -> ContainsLoadBalancerOutboundRule -> Outbound Rule
Load Balancer Frontend -> AttachedToSubnet / UsesPublicIp / UsesPublicIpPrefix
Load Balancer Rule -> UsesLoadBalancerFrontend / UsesLoadBalancerBackendPool / UsesLoadBalancerProbe

Application Gateway -> ContainsApplicationGatewayIpConfiguration -> IP Configuration
Application Gateway IP Configuration -> AttachedToSubnet -> Subnet
Application Gateway -> ContainsApplicationGatewayFrontend -> Frontend
Application Gateway Frontend -> AttachedToSubnet / UsesPublicIp
Application Gateway -> ContainsApplicationGatewayBackendPool -> Backend Pool
Application Gateway -> ContainsApplicationGatewayHttpListener -> Listener
Application Gateway -> ContainsApplicationGatewayRoutingRule -> Routing Rule
Routing Rule -> UsesApplicationGatewayHttpListener / BackendPool / BackendHttpSettings / UrlPathMap
Application Gateway -> UsesFirewallPolicy -> Firewall Policy

Azure Firewall -> UsesFirewallPolicy -> Firewall Policy
Azure Firewall -> AttachedToVirtualHub -> Virtual Hub
Azure Firewall -> ContainsAzureFirewallIpConfiguration -> IP Configuration
Azure Firewall IP Configuration -> AttachedToSubnet / UsesPublicIp
Firewall Policy -> InheritsFromFirewallPolicy -> Base Policy

VM -> UsesNetworkInterface -> Network Interface
VM -> UsesOsDisk -> Managed Disk
VM -> UsesDataDisk -> Managed Disk
VM -> UsesAvailabilitySet -> Availability Set
Managed Disk -> ManagedByResource -> Azure Resource
Availability Set -> ContainsVm -> VM
Availability Set -> UsesProximityPlacementGroup -> Proximity Placement Group

Workspace -> ReferencesApplicationGroup -> Application Group
Application Group -> UsesHostPool -> Host Pool
Host Pool -> ContainsSessionHost -> Session Host
Session Host -> BackedByVm -> VM
Scaling Plan -> TargetsHostPool -> Host Pool

Storage Account -> AllowsSubnet -> Subnet
Key Vault -> AllowsSubnet -> Subnet
Vault -> ContainsBackupPolicy -> Backup Policy
Recovery Services Vault -> ContainsProtectedItem -> Protected Item
Backup Vault -> ContainsBackupInstance -> Backup Instance
Protected Item / Backup Instance -> UsesBackupPolicy -> Backup Policy
Protected Item / Backup Instance -> ProtectsResource -> Azure Resource

Diagnostic Setting -> Destination
```

P3, P4, P5 und P6 verwenden derzeit fachmodulspezifische Relationship-Arrays. P9 vereinheitlicht später die Relationship-Schemata aller Fachmodule.

Azure Resource IDs bleiben der bevorzugte technische Schlüssel. Für ausgewählte untergeordnete Azure-Objekte ohne eigene Resource ID dürfen ausschließlich deterministische Child-IDs unterhalb der Azure-Parent-ID erzeugt werden; keine Namensheuristik darf eine Beziehung zu einer externen Ressource erfinden. Für P5 wird die Parent-Host-Pool-ID eines Session Hosts deterministisch aus dessen eigener ARM-ID abgeleitet; die VM-Beziehung stammt ausschließlich aus der von Azure gelieferten Session-Host-`resourceId`. Für P6 werden Backup-Policy-, Vault- und Protected-Resource-Beziehungen ausschließlich aus Azure gelieferten ARM IDs aufgebaut.

---

# 13. Logging und Fehlerbehandlung

Logs enthalten Zeitstempel, Level, Modul/Aktion und Ergebnis; niemals Secrets oder Access Tokens.

Der normale Collector zeigt zusätzlich sichtbare Phasenmeldungen und Objektzähler, damit längere ARG-/Exportvorgänge nicht wie ein stiller Hänger wirken. Der aktuelle P6-Stand besitzt 8 Phasen: P3 Network wird in Phase 3/8, P4 Compute in Phase 4/8, P5 AVD in Phase 5/8 und P6 Storage / Backup / Key Vault in Phase 6/8 erfasst; Phase 7/8 schreibt die normalisierten Inventardateien und Phase 8/8 erzeugt Summary/Manifest.

Kritische Fehler:

- Read-only-Verifikation fehlgeschlagen,
- Pre-Azure-Validierung nicht erfolgreich,
- PowerShell-Mindestversion fehlt,
- Dependency kann nicht bereitgestellt werden,
- Azure-Authentifizierung nicht möglich,
- Tenant/Subscription nicht erreichbar,
- Core-Export nicht möglich.

Ein isolierter P3-Netzwerk-, P4-Compute-, P5-AVD- oder P6-Storage-/Backup-/Key-Vault-Fehler darf bei erfolgreichem Core-Inventar zu `PartialSuccess` führen, nicht zu einem stillen Verlust des Core-Exports. P6 besitzt innerhalb der Phase getrennte Fehlergrenzen für Storage, Backup und Key Vault.

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
Azure -> Collector -> JSON -> DocumentationEngine / AI Documentation Pipeline -> Markdown/DOCX/PDF/Diagramme
```

Die KI darf keine nicht durch Quelldaten belegten Fakten erfinden. Insbesondere sollen Beziehungen soweit technisch möglich explizit als Resource-ID-Relationships vorliegen und nicht aus Namenskonventionen erraten werden. Die eigentliche Dokumentations-/Diagrammlogik gehört nicht in den Collector.

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
- [x] P3a-Unit-/Regressionstests einschließlich Export-Shape und Local-Gateway-FQDN ergänzt
- [x] statische Read-only-Gegenprüfung: keine neuen Azure-/REST-/CLI-/SDK-Schreibpfade
- [x] P3a-Real-Export nach Export-Shape-/FQDN-Fix erfolgreich: 12 RG, 134 Core-Ressourcen, 22 Network-Ressourcen, 44 eindeutige Relationships, 0 Orphans, 0 Collector-Fehler, `READ-ONLY VERIFIED`
- [x] `network.json` fachlich/strukturell geprüft: stabile Arrays, FQDN-Endpunkt korrekt, keine Secret-Leakage; exakter Pester-Zähler wird derzeit nicht im ZIP persistiert

### P3b – Erweiterte Netzwerkdienste
- [x] Private Endpoints / Private-Link-Verbindungen
- [x] Private DNS Zones / VNet Links
- [x] NAT Gateways als eigene Ressourcen
- [x] Load Balancer einschließlich Frontends, Backend Pools/Adressen, Rules, Probes und Outbound Rules
- [x] Application Gateway einschließlich Topologie-/Routing-Komponenten ohne Zertifikatsmaterial
- [x] Azure Firewall / Firewall Policy Referenzen ohne Firewall-Regelkollektionen
- [x] zusätzliche Resource-ID-basierte Relationships
- [x] acht dedizierte P3b-Unit-Tests ergänzt
- [x] statische Read-only-Gegenprüfung: kein neues Azure-Cmdlet, kein REST-/CLI-/SDK-Pfad; bestehender `Search-AzGraph`-Wrapper unverändert
- [x] automatische Pre-Azure-Validierung des finalen P3b-Stands erfolgreich: PowerShell 7.6.4, Pester 6.0.1, 46/46 Tests, beide Gates `READ-ONLY VERIFIED`, `READY FOR AZURE TEST`, vor Freigabe `Azure access performed: NO`
- [x] P3b-Real-Export 2026-08-12 erfolgreich geprüft: 12 RG, 134 Core-Ressourcen, 22 Network-Ressourcen, 44 eindeutige Relationships, 0 Orphans, 0 Collector-Fehler, `Success`, `READ-ONLY VERIFIED`
- [x] P3b-Zero-State gegen den tatsächlichen Kunden-Iststand verifiziert: alle 27 P3b-Collections sind echte leere Arrays und das Core-Inventar enthält gleichzeitig 0 Private Endpoints/Private DNS/NAT Gateways/Load Balancer/Application Gateways/Azure Firewalls/Firewall Policies
- [x] Export-Härtung im P3b-Real-Export bestätigt: keine Adapter-/`Length`-Artefakte, keine verschachtelten Arrays, keine RG-Casing-Abweichungen und keine Treffer für `sharedKey`, Private-Link-`requestMessage`, Zertifikats-/PFX-Material, Firewall-Regelkollektionen oder starke Credential-Muster

> **P3a und P3b sind damit für den aktuellen Entwicklungsstand abgeschlossen. Positive Real-Azure-Pfade für P3b-Ressourcentypen, die in dieser Kundenumgebung nicht vorhanden sind, bleiben als heterogene Integrationstests unter P10 offen und blockieren P4 nicht.**

## P4 – Compute
- [x] Architektur und Sicherheits-/Datenminimierungsgrenze dokumentiert (`Docs/P4-Compute.md`)
- [x] `Queries/Compute.kql` mit expliziter Projektion für Virtual Machines, Managed Disks und Availability Sets
- [x] `Collector.Compute.psm1` für VM-/Disk-/Availability-Normalisierung und Resource-ID-Relationships
- [x] VM Size, Image-Metadaten, Zones/Availability Set, NIC-Referenzen sowie OS-/Data-Disk-Metadaten implementiert
- [x] Managed-Disk-SKU/Tier/Size/OS-Type/Disk-State/Managed-By implementiert
- [x] Availability-Set-Fault-/Update-Domain-Counts, VM-Referenzen und optionale PPG-Referenz implementiert
- [x] optionaler ARG-Power-State als Best-Effort-Momentaufnahme implementiert; fehlende Werte werden nicht interpretiert
- [x] `Inventory/compute.json` und `summary.compute` in den normalen Collector integriert
- [x] P4 als Phase 4 von 6 in sichtbare Collector-Ausgabe und Fehler-/PartialSuccess-Pfad integriert
- [x] sechs dedizierte P4-Unit-/Regressionstests für Query-Safety, VM, Disk, Availability Set, sensitive URI/Encryption-Minimierung und leere Arrays ergänzt
- [x] statische Read-only-Gegenprüfung: kein neues Azure-Cmdlet, kein REST-/CLI-/SDK-Pfad; bestehender `Invoke-CollectorResourceGraph`/`Search-AzGraph`-Pfad wird wiederverwendet
- [x] automatische Pre-Azure-Validierung des finalen P4-Stands erfolgreich: PowerShell 7.6.4, Pester 6.0.1, 9 Testdateien, 52/52 Tests, beide Gates `READ-ONLY VERIFIED`, `READY FOR AZURE TEST`, vor Freigabe `Azure access performed: NO`, keine Administrator-Elevation
- [x] P4-Real-Export 2026-08-12 erfolgreich: 12 RG, 134 Core-Ressourcen, 11 Compute-Quellressourcen, 4 VMs, 7 Managed Disks, 0 Availability Sets, 18 Compute-Relationships, 0 Collector-Fehler, `Success`
- [x] `compute.json` fachlich/strukturell geprüft: P4-Scope 1:1 gegen Core, 4 NIC-/4 OS-Disk-/3 Data-Disk-Referenzen konsistent, alle 7 `managedByResourceId` korrekt, 0 doppelte Relationships, 0 Orphan-Quellen/-Ziele, 4/4 Power-State-Snapshots
- [x] P4-Export-Härtung bestätigt: stabile Arrays, keine PowerShell-Adapter-Artefakte, keine RG-Casing-Abweichungen und keine Treffer für `osProfile`, Admin-/Password-/SSH-/UserData-/ProtectedSettings-Inhalte, Boot-Diagnostics-URIs, Secret-/Key-URLs, `encryptionSettingsCollection`, Private-Key-/SAS-/Account-Key-/JWT-/Credential-Muster oder nicht freigegebene URI-/Encryption-Detailwerte
- [x] P3-Rückwärtskompatibilität im P4-Real-Export bestätigt: `resourceGroups.json`, `resources.json` und `network.json` gegenüber dem unmittelbar vorherigen P3b-Export inhaltlich unverändert

> **P4 Compute ist für den aktuellen Entwicklungsstand abgeschlossen. Weitere heterogene Compute-Szenarien, insbesondere positive Availability-Set-/Zone-/Gallery-Sonderfälle, bleiben Bestandteil der späteren P10-Integrationstests und blockieren P5 nicht.**

## P5 – AVD
- [x] Architektur und Sicherheits-/PII-Minimierungsgrenze dokumentiert (`Docs/P5-AVD.md`)
- [x] `Queries/AVD.kql` für Workspaces, Host Pools, Application Groups und Scaling Plans implementiert
- [x] `Queries/AVD.SessionHosts.kql` für Session Hosts über `DesktopVirtualizationResources` implementiert; kein Cross-Table-`union`
- [x] kein zusätzlicher AVD-Cmdlet-/REST-/CLI-/SDK-Pfad
- [x] `Collector.AVD.psm1` für AVD-Normalisierung und Resource-ID-Relationships implementiert
- [x] Workspace-/Application-Group-Referenzen, Host-Pool-Betriebseinstellungen und Start VM on Connect implementiert
- [x] Session-Host-Status-/Session-/Agent-/OS-/Heartbeat-Metadaten sowie direkte P4-VM-Resource-ID implementiert
- [x] Session-Host-Zeitstempel lokal invariant als UTC/ISO-8601 normalisiert
- [x] Scaling-Plan-Host-Pool-Referenzen und sichere technische Schedule-Parameter implementiert
- [x] `Inventory/avd.json` und `summary.avd` in den normalen Collector integriert
- [x] P5 als Phase 5 des aktuellen Collector-Ablaufs integriert
- [x] Unit-/Regressionstests für Query-Safety, Query-Split, UTC-/ISO-Zeitstempel, Workspace, Host Pool, Application Group, Session Host, Scaling Plan und leere Arrays ergänzt
- [x] sensitive/PII-haltige AVD-Pfade bewusst ausgeschlossen: Registration Tokens, SSO-Secret-Pfade, VM Templates, rohe RDP-Freitexte, Assigned Users/User Sessions, Health-/Update-Fehlerdetails, Application-Ausführungspfade und Scaling-Notification-Texte
- [x] statische Read-only-Gegenprüfung: kein neues Azure-Cmdlet, kein REST-/CLI-/SDK-Schreibpfad; bestehender `Invoke-CollectorResourceGraph`/`Search-AzGraph`-Pfad wird wiederverwendet
- [x] automatische Pre-Azure-Validierung des finalen P5-Stands erfolgreich: PowerShell 7.6.4, Pester 6.0.1, 12 Testdateien, 62/62 Tests, beide Gates `READ-ONLY VERIFIED`, `READY FOR AZURE TEST`, vor Azure `Azure access performed: NO`, keine Administrator-Elevation
- [x] finaler P5-Real-Export 2026-08-12 erfolgreich: 4 Top-Level-AVD-Ressourcen + 1 Session Host = 5 Quellzeilen, 1 Workspace, 1 Host Pool, 2 Application Groups, 1 Session Host, 0 Scaling Plans, 6 Relationships, 0 Fehler, `Success`
- [x] `avd.json` gegen Core/P4 und Export-Härtung geprüft: SessionHost->VM korrekt, 0 doppelte Relationships, 0 Orphan-Quellen/-Ziele, ISO-8601-Zeitstempel, keine verschachtelten Arrays/ETS-Artefakte und keine Registration-/AssignedUser-/Credential-/UPN-Leakage

> **P5 Azure Virtual Desktop ist für den aktuellen Entwicklungsstand abgeschlossen. Positive heterogene AVD-Szenarien wie Scaling Plans und mehrere Session Hosts bleiben Bestandteil späterer P10-Integrationstests und blockieren P6/P7 nicht.**

## P6 – Storage / Backup / Key Vault
- [x] Architektur und Sicherheits-/Secret-Grenzen dokumentiert (`Docs/P6-Storage-Backup-KeyVault.md`)
- [x] drei getrennte Exportdomänen beschlossen und implementiert: `storage.json`, `backup.json`, `keyVault.json`
- [x] `Queries/Storage.kql` und `Collector.Storage.psm1` implementiert
- [x] `Queries/KeyVault.kql` und `Collector.KeyVault.psm1` implementiert
- [x] `Queries/Backup.TopLevel.kql` für Vaults aus `Resources` implementiert
- [x] `Queries/Backup.Resources.kql` für Policies/Protected Items/Backup Instances aus `RecoveryServicesResources` implementiert
- [x] Backup-Tabellen werden getrennt gelesen und erst lokal zusammengeführt; kein Cross-Table-`union`
- [x] Storage->Subnetz-, KeyVault->Subnetz- sowie Vault/Policy/ProtectedItem/ProtectedResource-Relationships implementiert
- [x] Last Recovery Point lokal invariant als UTC/ISO-8601 normalisiert
- [x] P6 vollständig in den normalen Collector als Phase 6 von 8 integriert; Storage, Backup und Key Vault besitzen getrennte Fehlergrenzen
- [x] `summary.storage`, `summary.backup` und `summary.keyVault` integriert
- [x] Secret-/PII-Grenzen für Storage Keys/SAS/Connection Strings, Backup Credentials/Secret Stores/CMK und Key-Vault-Inhalte/Access-Policy-Identitäten abgesichert
- [x] Unit-/Regressionstests für Query-Safety, Normalisierung, Relationships, Array-Shape und Empty Arrays ergänzt
- [x] statische Read-only-Gegenprüfung: keine neuen Fachcmdlets, kein REST/Web-/CLI-/SDK-Schreibpfad; Azure-Zugriff bleibt ausschließlich über den bestehenden Resource-Graph-Wrapper
- [x] automatische Pre-Azure-Validierung des finalen P6-Stands erfolgreich: PowerShell 7.6.4, Pester 6.0.1, 15 Testdateien, 73/73 Tests, beide Gates `READ-ONLY VERIFIED`, `READY FOR AZURE TEST`, vor Azure `Azure access performed: NO`, keine Administrator-Elevation
- [x] finaler P6-Real-Export 2026-08-12 erfolgreich: 8 Storage Accounts, 1 Key Vault, 2 Recovery Services Vaults, 0 Backup Vaults, 8 Backup Policies, 4 Recovery Services Protected Items, 0 Backup Instances, 21 P6-Relationships insgesamt, 0 Fehler, `Success`
- [x] P6-Relationships vollständig geprüft: 8/8 `ContainsBackupPolicy`, 4/4 `ContainsProtectedItem`, 4/4 `UsesBackupPolicy`, 4/4 `ProtectsResource`, 0 Duplikate, 0 Orphan-Quellen, 0 Orphan-Ziele
- [x] vier geschützte Ressourcen korrekt per ARM ID aufgelöst: 3 vorhandene P4-VMs und 1 vorhandener Storage Account
- [x] Export-Härtung bestätigt: Summary-Bereiche konsistent, keine verschachtelten Arrays/ETS-Artefakte/RG-Casing-Abweichungen und keine Account-Key-/SAS-/Connection-String-/Private-Key-/PFX-/Backup-Credential-/Secret-/Key-URI-/AccessPolicy-/JWT-/UPN-Leakage
- [x] P3/P4/P5-Rückwärtskompatibilität im P6-Real-Export bestätigt: `resourceGroups.json`, `resources.json`, `network.json`, `compute.json` und `avd.json` gegenüber dem unmittelbar vorherigen validierten P5-Export inhaltlich unverändert

> **P6 Storage / Backup / Key Vault ist für den aktuellen Entwicklungsstand abgeschlossen. Data-Protection-Backup-Vault-/Backup-Instance-Positivpfade sowie weitere heterogene Storage-/Key-Vault-Netzwerkszenarien bleiben Bestandteil späterer P10-Integrationstests und blockieren P7 nicht.**

## P7 – Security / Governance
- [ ] RBAC / Policies / Locks / Identitätsdatenschutz

## P8 – Monitoring / Automation
- [ ] Monitoring- und Automation-Metadaten

## P9 – Relationship Engine
- [ ] vereinheitlichtes Relationship-Schema

## P10 – Qualitätssicherung / Härtung
- [ ] Integrationstests in heterogenen Testumgebungen, insbesondere positive Real-Azure-Abdeckung für P3b-Ressourcentypen, zusätzliche Compute-Szenarien wie Availability Sets/Zones/Gallery-Varianten, AVD Scaling Plans/mehrere Session Hosts sowie Data-Protection-Backup-Vault-/Backup-Instance- und weitere Storage-/Key-Vault-Netzwerkszenarien
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
16. P3/P4/P5/P6 dürfen keine parallelen Sonderwege für Secret-Filtering oder RG-Normalisierung einführen.
17. Network Connections dürfen `sharedKey` weder abfragen noch exportieren.
18. Netzwerkbeziehungen werden soweit möglich über Resource IDs und nicht über Namensheuristiken modelliert.
19. P3b darf Private-Link-Freitext, Application-Gateway-Zertifikatsmaterial, Azure-Firewall-Regelkollektionen oder Firewall-Policy-Zertifikats-/Transport-Security-Daten nicht exportieren, solange hierfür keine separate spätere Sicherheitsentscheidung getroffen wurde.
20. Synthetische Child-IDs dürfen nur deterministisch unterhalb einer bekannten Azure-Parent-ID erzeugt werden und niemals eine externe Resource-ID erfinden.
21. P4 darf VM-`osProfile`, Admin-/SSH-/UserData-Daten, VM Extension Settings, Boot-Diagnostics-Storage-URIs, Unmanaged-VHD-/Image-URIs sowie Key-/Secret-/Disk-Encryption-Detailwerte nicht in `compute.json` exportieren.
22. Ein fehlender P4-Power-State darf niemals als bestimmter VM-Zustand interpretiert oder ergänzt werden.
23. P5 darf Registration Tokens, SSO-Secret-Pfade, Assigned Users/User Sessions, Application-Ausführungspfade sowie frei formulierte Health-/Update-/Scaling-Notification-Texte nicht in `avd.json` exportieren.
24. P5 darf Session-Host-zu-VM-Beziehungen ausschließlich aus der von Azure gelieferten VM-Resource-ID ableiten; DNS-/VM-Namensheuristiken sind dafür nicht zulässig.
25. P6 darf Storage Keys/SAS/Connection Strings, Backup Credentials/Secret-Store-Werte/CMK-Key-Material oder Key-Vault-Secret-/Key-/Certificate-Inhalte nicht exportieren.
26. P6 darf Backup-zu-Ressource- und Policy-Beziehungen ausschließlich aus Azure gelieferten ARM IDs ableiten; Namensheuristiken sind dafür nicht zulässig.

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
P3a  Network Topology Foundation                 ✅ abgeschlossen
P3b  Erweiterte Netzwerkdienste                 ✅ abgeschlossen
P4   Compute                                     ✅ abgeschlossen
P5   AVD                                         ✅ abgeschlossen
P6   Storage / Backup / Key Vault                ✅ abgeschlossen
P7   Security / Governance                       ⬅️ nächster Block
P8   Monitoring / Automation
P9   Relationship Engine
P10  Tests / Härtung
P11  Release 1.0
```

**Aktueller nächster Schritt:** P7 Security / Governance. P5 und P6 sind implementiert, erfolgreich durch die automatische Pre-Azure-Validierung gelaufen und real gegen Azure validiert. Der aktuell bestätigte P6-Lauf besitzt 15 Testdateien / 73 Tests, beide Read-only-Gates `READ-ONLY VERIFIED`, `READY FOR AZURE TEST`, vor Azure `Azure access performed: NO` sowie einen anschließenden erfolgreichen Collector-Lauf mit 0 Fehlern. Für P7 müssen Scope, Identitätsdaten-Minimierung, ARG-/Read-only-Datenquellen, Relationships und Sicherheitsgrenzen vor der Implementierung gegen den bestehenden Stand geprüft werden. Jede P7-Codeänderung invalidiert die aktuelle Laufzeitfreigabe und erfordert vor einem neuen realen Azure-Lauf erneut die vollständige automatische Pre-Azure-Validierung.

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
DocumentationEngine / KI interpretiert und formuliert
        ->
Dokumente und Diagramme präsentieren das Ergebnis
```

**Ohne unmittelbar zuvor erfolgreich abgeschlossene Pre-Azure-Validierung mit `READ-ONLY VERIFIED` und `READY FOR AZURE TEST` darf kein realer Azure-Lauf freigegeben werden.**
