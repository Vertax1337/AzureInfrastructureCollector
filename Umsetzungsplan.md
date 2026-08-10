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

Der **AzureInfrastructureCollector darf unter keinen Umständen Azure-Ressourcen, Azure-Konfigurationen, Datenbestände oder Azure-seitige Zustände verändern.**

Ein Skriptstand, Modul, Hotfix, Testskript oder ausführbarer Code darf **erst dann zur Ausführung freigegeben bzw. an einen Benutzer zur Ausführung ausgegeben werden, wenn unmittelbar zuvor eine abschließende Read-only-Verifikation durchgeführt wurde und das Ergebnis eindeutig `READ-ONLY VERIFIED` lautet.**

Kann Read-only nicht zweifelsfrei bestätigt werden, gilt der Stand als **nicht freigegeben** und darf nicht zur Ausführung empfohlen oder ausgegeben werden.

## 0.1 Was Read-only in diesem Projekt bedeutet

Zulässig sind ausschließlich Operationen, die Informationen lesen, lokale Verarbeitung durchführen oder lokale Exportdateien erzeugen.

Zulässig sind insbesondere:

- Azure Resource Graph Abfragen,
- Azure REST-Aufrufe mit rein lesender Semantik, insbesondere `GET`,
- Azure PowerShell Cmdlets, deren konkrete Verwendung nachweislich nur Daten liest,
- lokale Normalisierung und Verarbeitung der gelesenen Daten,
- lokale Erstellung von JSON-, Log-, Manifest-, Summary- und ZIP-Dateien,
- Authentifizierung gegen Azure,
- Auswahl bzw. Änderung des **lokalen PowerShell-/Az-Kontexts**, sofern dadurch keine Azure-Ressource geändert wird.

Daher sind beispielsweise `Connect-AzAccount` und `Set-AzContext` grundsätzlich zulässig, weil sie den Authentifizierungs- bzw. lokalen Ausführungskontext steuern und keine Azure-Ressource verändern.

## 0.2 Verbotene Azure-seitige Wirkungen

Nicht zulässig sind insbesondere Azure-Operationen, die:

- Ressourcen erstellen,
- Ressourcen löschen,
- Ressourcen verändern,
- Ressourcen starten oder stoppen,
- VMs neu starten oder deallokieren,
- Netzwerkregeln verändern,
- RBAC-Zuweisungen verändern,
- Policies verändern,
- Locks verändern,
- Tags auf Azure-Ressourcen verändern,
- Backup-Konfigurationen verändern,
- Monitoring-Konfigurationen verändern,
- Automation-Konfigurationen verändern,
- Secrets, Keys oder Zertifikate erzeugen, verändern oder rotieren,
- Daten in Azure Storage, Datenbanken, Key Vaults oder andere Azure-Dienste schreiben,
- Deployments auslösen,
- Provider-Aktionen mit schreibender oder zustandsverändernder Wirkung ausführen.

## 0.3 Keine reine Verb-Prüfung

Read-only darf **nicht ausschließlich anhand des PowerShell-Verbs** beurteilt werden.

Ein pauschales Verbot aller `Set-*`-Cmdlets wäre technisch falsch, weil beispielsweise `Set-AzContext` lediglich den lokalen Kontext setzt. Umgekehrt kann ein Cmdlet mit einem scheinbar harmlosen Verb über Parameter oder eine REST/API-Funktion dennoch einen Azure-seitigen Zustand verändern.

Die Verifikation muss daher die **konkrete Wirkung der verwendeten Operation** bewerten.

## 0.4 Fail-Closed-Prinzip

Für die Read-only-Verifikation gilt **Fail Closed**:

- eindeutig lesend verifiziert -> zulässig,
- eindeutig lokal ohne Azure-Ressourcenänderung -> zulässig,
- unbekannt -> blockieren,
- unklar -> blockieren,
- potenziell schreibend -> blockieren,
- schreibend -> blockieren.

Eine unbekannte Azure-Operation darf niemals mit der Annahme "wird schon lesend sein" freigegeben werden.

## 0.5 Pflichtprüfung vor jeder Ausführungsfreigabe

Vor jeder Ausgabe eines ausführbaren Standes müssen mindestens folgende Punkte geprüft werden:

1. alle PowerShell-Dateien des ausführbaren Scopes,
2. alle verwendeten Azure PowerShell Cmdlets,
3. alle direkten Azure REST/API-Aufrufe,
4. alle dynamisch zusammengesetzten Cmdlet- oder API-Aufrufe,
5. alle eingebundenen Module und Skripte des Projekts,
6. alle KQL-Abfragen,
7. alle Codepfade, die durch Parameter aktiviert werden können,
8. alle Fehler-/Fallback-Pfade,
9. alle optionalen Module, die beim konkreten Lauf geladen werden können,
10. alle Änderungen seit der letzten bestätigten Read-only-Verifikation.

Die Prüfung muss sicherstellen, dass keine Azure-Control-Plane- oder Data-Plane-Schreiboperation enthalten oder erreichbar ist.

## 0.6 Verbindlicher Verifikationsstatus

Ein freigegebener Stand muss vor der Ausführung sinngemäß mit folgendem Status bestätigt werden können:

```text
READ-ONLY VERIFICATION
Status: READ-ONLY VERIFIED
Azure resource mutations: NONE
Azure data mutations: NONE
Control-plane write operations: NONE
Data-plane write operations: NONE
Local writes: Export/Logs only
```

Der genaue technische Prüfbericht darf später erweitert werden. Der Status `READ-ONLY VERIFIED` darf jedoch nur gesetzt werden, wenn alle relevanten Prüfungen erfolgreich sind.

## 0.7 Automatisches Read-only-Gate

Der Collector soll zusätzlich zu Code-Reviews ein automatisches **Read-only-Gate** erhalten.

Ziel:

```text
Code / Module
     |
     v
Read-only Verification Gate
     |
     +-- VERIFIED ------> Ausführung zulässig
     |
     +-- UNKNOWN/FAIL --> Ausführung blockiert
```

Das Gate soll vor Beginn der eigentlichen Azure-Inventarisierung ausgeführt werden und bei einer nicht zulässigen oder unbekannten Operation den Lauf abbrechen.

Automatische Prüfungen ersetzen dabei **nicht** die abschließende fachliche Prüfung eines neuen oder veränderten Azure-Aufrufs.

## 0.8 Änderungen an dieser Regel

Diese oberste Regel darf nicht beiläufig im Rahmen einer Feature-Entwicklung aufgeweicht werden.

Eine Änderung, Ausnahme oder Erweiterung, die Azure-seitige Schreiboperationen ermöglichen würde, erfordert eine **explizite Entscheidung des Projektverantwortlichen/Nutzers und eine bewusste Änderung dieser Source of Truth vor der Implementierung**.

Bis dahin gilt ausnahmslos:

> **Keine bestätigte Read-only-Verifikation = keine Ausführungsfreigabe.**

---

# 1. Zweck dieses Dokuments

Diese Datei ist die **verbindliche Source of Truth** für die Entwicklung des Projekts **AzureInfrastructureCollector**.

Sie beschreibt:

- Ziel und Zweck des Collectors,
- Architektur und technische Grundentscheidungen,
- unterstützte Betriebsarten,
- zu erfassende Azure-Bereiche,
- Sicherheits- und Datenschutzanforderungen,
- Ausgabeformat und Datenmodell,
- Entwicklungsphasen,
- Abnahmekriterien,
- sowie geplante spätere Erweiterungen.

## 1.1 Verbindlichkeit

Bei Abweichungen zwischen Implementierung, Issue, Chat-Verlauf, README oder sonstiger Dokumentation gilt grundsätzlich dieser Umsetzungsplan.

Die **oberste Read-only-Regel aus Kapitel 0 hat innerhalb dieses Dokuments wiederum Vorrang vor allen anderen Festlegungen.**

Änderungen an Architektur, Scope oder technischen Grundentscheidungen sollen zuerst in dieser Datei dokumentiert und anschließend implementiert werden.

---

# 2. Projektziel

Der **AzureInfrastructureCollector** soll Azure-Infrastrukturen automatisiert, reproduzierbar und ausschließlich lesend inventarisieren.

Das Werkzeug soll für wiederkehrende Kundendokumentationen geeignet sein und darf deshalb keine kundenspezifischen Annahmen oder fest codierten Tenant-, Subscription-, Resource-Group- oder Ressourcennamen enthalten.

Der Collector soll eine Azure-Umgebung in ein strukturiertes, maschinenlesbares Exportformat überführen, das anschließend als Grundlage für folgende Aufgaben dienen kann:

- technische Bestandsdokumentationen,
- Architekturdiagramme,
- KI-gestützte Dokumentation,
- Soll-/Ist-Vergleiche,
- Änderungsvergleiche,
- Sicherheitsanalysen,
- Betriebsdokumentationen,
- Word-/PDF-Dokumente.

## 2.1 Zielbild

```text
Azure Tenant / Subscription(s)
            |
            v
 AzureInfrastructureCollector
            |
            +--> Azure Resource Graph
            |
            +--> Az PowerShell / REST APIs
            |
            v
   Normalisiertes JSON-Modell
            |
            +--> Rohdatenexport
            +--> Manifest
            +--> Zusammenfassung
            +--> Logs
            |
            v
      ZIP / Exportordner
            |
            +--> KI-Dokumentation
            +--> Architekturdiagramm
            +--> DOCX / PDF
            +--> Versionsvergleich
```

Datenerfassung und spätere KI-Auswertung/Dokumentgenerierung sind bewusst getrennte Komponenten.

---

# 3. Kernprinzipien

## 3.1 Kundengenerisch

Der Collector darf keine fest programmierten Kundenwerte enthalten. Tenant-ID, Subscription-ID, Resource Groups, Regionen, Ressourcennamen, Tags und Naming-Konventionen werden zur Laufzeit ermittelt oder optional als Parameter übergeben.

## 3.2 Tenantfähig

Dasselbe Paket muss für beliebig viele Azure-Tenants verwendbar sein.

Der Collector soll:

1. verfügbare Tenants erkennen,
2. eine Tenant-Auswahl ermöglichen,
3. verfügbare Subscriptions innerhalb des ausgewählten Tenants erkennen,
4. mehrere Subscriptions erfassen können,
5. optional auf einzelne Resource Groups eingeschränkt werden können.

Die tatsächlich sichtbaren Ressourcen ergeben sich ausschließlich aus den Berechtigungen der verwendeten Identität.

## 3.3 Read-only by Design

Read-only by Design ist nicht nur ein Architekturprinzip, sondern unterliegt der übergeordneten Pflicht aus Kapitel 0.

Alle Azure-Zugriffe sind lesend zu implementieren. Keine Azure-Ressource darf durch den Collector verändert werden.

## 3.4 Least Privilege

Das Werkzeug soll mit möglichst geringen Berechtigungen funktionieren. Für die reine Ressourceninventarisierung ist grundsätzlich Reader-orientierter Zugriff vorzusehen.

Bereiche, die zusätzliche Leserechte benötigen, müssen als nicht verfügbar protokolliert werden, anstatt den gesamten Export unnötig fehlschlagen zu lassen.

## 3.5 Keine Secrets im Export

Folgende Daten dürfen niemals bewusst exportiert werden:

- Kennwörter,
- Client Secrets,
- Storage Account Keys,
- SAS-Tokens,
- Private Keys,
- Zertifikats-Private-Keys,
- Connection Strings mit Geheimnissen,
- Access Tokens,
- API Keys,
- sonstige Credential-Werte.

Potentiell sensitive Properties müssen vor Speicherung entfernt oder maskiert werden.

## 3.6 Reproduzierbarkeit

Zwei Läufe auf derselben unveränderten Infrastruktur sollen strukturell vergleichbare Ergebnisse erzeugen. Dazu gehören stabiles JSON-Schema, konsistente Dateinamen, definierte Sortierung, ISO-8601-Zeitstempel, Resource IDs und Collector-Version im Manifest.

## 3.7 Best Effort statt Totalabbruch

Fehlt für einen einzelnen Erfassungsbereich die Berechtigung oder schlägt eine Detailabfrage fehl, soll der Collector nach Möglichkeit fortfahren. Fehler werden protokolliert, einem Modul zugeordnet und im Manifest bzw. Summary kenntlich gemacht.

**Ausnahme:** Eine fehlgeschlagene Read-only-Verifikation ist immer ein kritischer Fehler und muss den Lauf abbrechen.

---

# 4. Technische Grundarchitektur

## 4.1 Haupttechnologie

Initiale Implementierung:

- PowerShell 7.x,
- Azure PowerShell / `Az.*`,
- Azure Resource Graph / `Search-AzGraph`,
- JSON als primäres Austauschformat.

Windows PowerShell 5.1 ist kein primäres Entwicklungsziel.

## 4.2 Resource Graph First

Azure Resource Graph ist die bevorzugte Quelle für breit angelegte Inventarisierung, insbesondere für allgemeine Ressourcen, Resource Groups, Regionen, Tags, Resource IDs und breite Compute-/Network-/Storage-Basisdaten.

## 4.3 Az PowerShell / REST für Detaildaten

`Az.*`-Cmdlets oder Azure REST APIs werden dort verwendet, wo Resource Graph erforderliche Details nicht liefert, z. B. AVD, Backup, Automation, Diagnostic Settings, Monitoring oder Berechtigungsdetails.

Jeder neu eingeführte Azure-Aufruf muss vor Freigabe gemäß Kapitel 0 auf seine tatsächliche Read-only-Wirkung geprüft werden.

## 4.4 Normalisierungsschicht

Zwischen Erfassung und Export liegt eine Normalisierungsschicht mit stabilen Feldern, Resource IDs als Referenzschlüssel, konsistenten Datentypen, Secret Filtering und definierter Sortierung.

---

# 5. Repository-Struktur

```text
AzureInfrastructureCollector/
|
+-- Collect-AzureDocumentation.ps1
+-- Umsetzungsplan.md
+-- README.md
+-- CHANGELOG.md
+-- LICENSE
|
+-- Modules/
|   +-- Collector.Core.psm1
|   +-- Collector.Compute.psm1
|   +-- Collector.Network.psm1
|   +-- Collector.Storage.psm1
|   +-- Collector.AVD.psm1
|   +-- Collector.Backup.psm1
|   +-- Collector.Security.psm1
|   +-- Collector.Monitoring.psm1
|   +-- Collector.Automation.psm1
|
+-- Queries/
|   +-- Resources.kql
|   +-- ResourceGroups.kql
|   +-- Compute.kql
|   +-- Network.kql
|   +-- Storage.kql
|   +-- Security.kql
|   +-- Changes.kql
|
+-- Config/
|   +-- collector.config.json
|
+-- Schemas/
|   +-- manifest.schema.json
|   +-- resource.schema.json
|
+-- Tests/
|   +-- Unit/
|   +-- Integration/
|
+-- Docs/
    +-- DataModel.md
    +-- Permissions.md
    +-- ModuleReference.md
```

Die Struktur darf im Laufe der Entwicklung angepasst werden, sofern dies in dieser Source of Truth dokumentiert wird.

---

# 6. Einstiegspunkt

Der zentrale Einstiegspunkt ist:

```powershell
./Collect-AzureDocumentation.ps1
```

Er übernimmt:

1. Prüfung der Voraussetzungen,
2. **Read-only-Verifikation des ausführbaren Scopes**, 
3. Azure-Anmeldung bzw. Kontextprüfung,
4. Tenant-Auswahl,
5. Scope-Auswahl,
6. Initialisierung der Module,
7. Datenerfassung,
8. Normalisierung,
9. Validierung,
10. Export,
11. Zusammenfassung.

Die Fachlogik wird möglichst in Modulen gekapselt.

---

# 7. Betriebsarten

## 7.1 Interaktiver Modus

```powershell
./Collect-AzureDocumentation.ps1
```

Der Benutzer wird durch Azure-Kontext, Tenant-Auswahl, Subscription-Auswahl, optionale Resource-Group-Auswahl und Export geführt.

## 7.2 Tenant explizit vorgeben

```powershell
./Collect-AzureDocumentation.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## 7.3 Subscription explizit vorgeben

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -SubscriptionId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
```

Mehrere Subscription IDs sollen unterstützt werden.

## 7.4 Resource Groups einschränken

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId "..." `
    -SubscriptionId "..." `
    -ResourceGroup "RG-PROD","RG-NETWORK"
```

## 7.5 NonInteractive

```powershell
./Collect-AzureDocumentation.ps1 `
    -TenantId "..." `
    -SubscriptionId "..." `
    -OutputPath "C:\AzureDocs" `
    -NonInteractive
```

Der NonInteractive-Modus darf keine Eingaben über `Read-Host` verlangen.

---

# 8. Authentifizierung und Azure-Kontext

Version 1 unterstützt interaktive Anmeldung über `Connect-AzAccount` und soll vorhandene Azure-Kontexte wiederverwenden.

Später sollen Managed Identity, Service Principal, Azure Automation und CI/CD unterstützt werden können.

Credentials dürfen niemals im Repository hinterlegt werden.

Authentifizierung und lokales Context-Switching gelten nur dann als zulässig, wenn sie keine Azure-Ressource oder Azure-Daten verändern.

---

# 9. Scope-Modell

Ein Collector-Lauf besitzt genau einen logischen Tenant-Kontext, kann darin aber mehrere Subscriptions erfassen.

```text
Tenant
  |
  +-- Subscription A
  |      +-- Resource Group 1
  |      +-- Resource Group 2
  |
  +-- Subscription B
         +-- Resource Group 3
```

Ein späterer Batch-Modus kann mehrere Tenants nacheinander erfassen. Ergebnisse verschiedener Tenants bleiben getrennt.

---

# 10. Erfassungsumfang – Version 1

## 10.1 Core / Tenant / Subscription

- Tenant ID / Display Name,
- Subscription ID / Name / State,
- Resource Groups,
- Regionen,
- Ressourcenanzahl,
- Ressourcentypen,
- Tags,
- Resource IDs.

## 10.2 Compute

- Virtual Machines,
- VM Size / SKU,
- OS Type,
- Image-Informationen,
- Availability Zone / Set,
- NIC-Zuordnungen,
- Managed Disks,
- OS-/Data-Disks,
- Disk SKU / Size,
- Boot Diagnostics Status,
- optional Power State als Momentaufnahme.

## 10.3 Netzwerk

- VNets / Address Spaces,
- Subnets,
- Peerings,
- NICs / IP Configurations,
- Private / Public IPs,
- NSGs / Rules / Associations,
- Route Tables / Routes,
- NAT Gateways,
- Load Balancer,
- Application Gateway,
- VPN / Virtual Network Gateways,
- Local Network Gateways,
- Private Endpoints / Private Link,
- Azure Firewall,
- Private DNS Zones / VNet Links.

## 10.4 Storage

- Storage Accounts,
- SKU / Region,
- Public Network Access,
- TLS-/HTTPS-Konfiguration,
- Network ACL Basisinformationen,
- Private Endpoints,
- File Shares / Blob Container nur soweit sinnvoll und ohne Inhaltsdaten.

Keine Dateiinhalte oder Blob-Inhalte werden erfasst.

## 10.5 Azure Virtual Desktop

- Workspaces,
- Host Pools,
- Application Groups,
- Workspace-Zuordnungen,
- Session Hosts,
- Session Host Status,
- VM Resource IDs,
- Load Balancing Type,
- Host Pool Type,
- Max Session Limit,
- Validation Environment,
- Start VM on Connect,
- Scaling Plans / Zuordnungen.

Benutzerbezogene Sessiondaten sollen standardmäßig nicht dauerhaft exportiert werden.

## 10.6 Backup / Recovery

- Recovery Services Vaults,
- Backup Vaults,
- Backup Policies,
- geschützte Ressourcen,
- Retention-Grundkonfigurationen,
- Soft Delete,
- Immutable-Konfiguration,
- Resource Guard Beziehungen.

Keine Backup-Inhalte werden exportiert.

## 10.7 Security / Governance

- Azure RBAC Role Assignments,
- Scopes,
- Role Definition Name/ID,
- Principal ID / Type,
- Resource Locks,
- Policy Assignments / Initiatives,
- Defender for Cloud Basisinformationen, soweit mit Leserechten verfügbar.

Personenbezogene Identitätsinformationen werden minimiert; primäre Referenz bleibt die Principal ID.

## 10.8 Monitoring

- Log Analytics Workspaces,
- Diagnostic Settings / Destinations,
- Action Groups,
- Metric Alerts,
- Activity Log Alerts.

Keine eigentlichen Log-Inhalte werden standardmäßig exportiert.

## 10.9 Automation

- Automation Accounts,
- Runbook-Metadaten,
- Typ / Veröffentlichungsstatus,
- Schedules,
- Schedule-/Runbook-Verknüpfungen,
- Managed Identity Status.

Runbook-Quellcode wird standardmäßig nicht exportiert.

## 10.10 Key Vault

Zu erfassen sind ausschließlich Konfigurationsmetadaten wie Vault Name, Resource ID, Region, RBAC-/Access-Policy-Modell, Public Network Access, Private Endpoints, Soft Delete und Purge Protection.

Nicht zu erfassen sind Secret Values, Key Material oder Certificate Private Keys.

---

# 11. Exportformat

Ein Lauf erzeugt einen eigenen tenantbezogenen Exportordner mit Manifest, Summary, Log und modularen JSON-Dateien.

Zielstruktur:

```text
AzureDocumentation_<Tenant>_<Timestamp>/
|
+-- manifest.json
+-- summary.json
+-- collector.log
+-- 00-Tenant/
+-- 01-Inventory/
+-- 02-Network/
+-- 03-Compute/
+-- 04-AVD/
+-- 05-Storage/
+-- 06-Security/
+-- 07-Backup/
+-- 08-Monitoring/
+-- 09-Automation/
+-- 10-Relations/
```

Optional kann nach erfolgreichem Lauf ein ZIP erzeugt werden.

---

# 12. Manifest

Jeder Export enthält eine `manifest.json` mit technischer Provenienz.

Mindestens enthalten:

- Schema-Version,
- Collector-Version,
- Start-/Endzeit,
- Tenant,
- Subscriptions,
- Scope,
- Modulstatus,
- Ressourcenanzahl,
- Fehler/Warnungen,
- Read-only-Verifikationsstatus.

Zielerweiterung:

```json
{
  "mode": "ReadOnly",
  "readOnlyVerification": {
    "status": "READ-ONLY VERIFIED",
    "azureResourceMutations": 0,
    "azureDataMutations": 0
  }
}
```

---

# 13. Summary

`summary.json` enthält kompakte Mengen- und Statusinformationen, z. B. Anzahl Subscriptions, Resource Groups, Ressourcen, VMs, VNets, Subnets, Public IPs, Private Endpoints, Storage Accounts, AVD-Objekte, Vaults, Role Assignments, Policies, Automation Accounts sowie fehlgeschlagene Module und Warnungen.

---

# 14. Beziehungen zwischen Ressourcen

Ein zentrales Ziel ist ein Relationship-Modell statt nur einer Ressourcenliste.

Beispiele:

```text
VM -> NIC -> Subnet -> VNet
NIC -> NSG
Subnet -> Route Table
Subnet -> NSG
Private Endpoint -> Target Resource
AVD Session Host -> VM -> NIC -> Subnet
VM -> Managed Disk
Diagnostic Setting -> Log Analytics Workspace
```

Normalisiertes Zielformat:

```json
{
  "sourceResourceId": "/subscriptions/.../virtualMachines/vm-app",
  "relationship": "usesNetworkInterface",
  "targetResourceId": "/subscriptions/.../networkInterfaces/nic-vm-app"
}
```

---

# 15. Logging

Jeder Lauf erzeugt `collector.log` mit INFO, WARN, ERROR und optional DEBUG.

Logs enthalten Zeitstempel, Modul, Level, Aktion und Ergebnis. Secrets und Access Tokens dürfen nicht in Logs geschrieben werden.

Die erfolgreiche Read-only-Verifikation muss protokolliert werden. Bei fehlgeschlagener Verifikation muss vor Azure-Inventarisierung abgebrochen werden.

---

# 16. Fehlerbehandlung

Ein Fehler in einem optionalen Collector-Modul soll nicht automatisch den gesamten Lauf abbrechen.

Kritische Fehler mit Abbruch sind insbesondere:

- Read-only-Verifikation nicht erfolgreich,
- keine Azure-Authentifizierung möglich,
- Tenant nicht erreichbar,
- keine gültige Subscription im Scope,
- Exportziel nicht beschreibbar,
- Core-Inventar nicht erstellbar.

Geplante Exit Codes:

```text
0 = Erfolg
1 = Erfolg mit Warnungen / Partial Collection
2 = Konfigurationsfehler
3 = Authentifizierungs-/Berechtigungsfehler auf Core-Ebene
4 = Export-/Dateisystemfehler
5 = unerwarteter interner Fehler
6 = Read-only-Verifikation fehlgeschlagen / nicht eindeutig
```

---

# 17. Konfiguration

`Config/collector.config.json` enthält ausschließlich nicht-sensitive Standardwerte.

Priorität:

1. sichere interne Defaults,
2. Konfigurationsdatei,
3. explizite Kommandozeilenparameter.

Die Read-only-Grundregel darf **nicht per Konfigurationsparameter deaktiviert oder überschrieben werden**.

---

# 18. Modulkonzept

Fachmodule sollen eine definierte Schnittstelle besitzen und mindestens Name, Status, ItemsCollected, Warnings, Errors, Duration und OutputFiles melden.

Jedes neue Fachmodul unterliegt vor Ausführungsfreigabe vollständig Kapitel 0.

---

# 19. Datenqualität

## 19.1 Resource ID als Primärreferenz

Azure Resource IDs sind der bevorzugte technische Schlüssel. Ressourcennamen allein dürfen nicht als eindeutige Referenz verwendet werden.

## 19.2 Sortierung

Arrays sollen stabil nach Subscription ID, Resource Group, Resource Type und Resource Name sortiert werden.

## 19.3 Null-Werte

Nicht verfügbare Daten dürfen nicht erfunden werden. Der Unterschied zwischen "nicht vorhanden" und "nicht abfragbar" soll erkennbar bleiben.

---

# 20. Sicherheit des Exports

Exportdateien enthalten schützenswerte interne Infrastrukturinformationen wie interne IP-Adressen, Servernamen, Netzwerkbeziehungen, NSG-Regeln, Resource IDs und Rollenstrukturen.

Exporte dürfen nicht unkontrolliert weitergegeben oder in öffentliche Git-Repositories committed werden und müssen nach Kundenvorgaben gespeichert werden.

---

# 21. KI-Grenze

Der Collector benötigt in Version 1 keine KI. Er erzeugt deterministische Infrastrukturinformationen.

```text
Collector -> JSON / ZIP -> AI Documentation Pipeline -> Beschreibung / Diagramm / DOCX / PDF
```

KI-Halluzinationen müssen von der Datenerfassung getrennt bleiben.

---

# 22. Spätere KI-Dokumentation

Eine spätere Stufe soll aus dem Export strukturierte technische Dokumentationen erzeugen können, z. B. Tenant-/Subscription-Struktur, Gesamtarchitektur, Resource Groups, Network, Compute, AVD, Storage, Backup, Monitoring, Automation, RBAC, Governance, Abhängigkeiten, Sicherheitsbetrachtung und Ressourceninventar.

KI-Ausgaben dürfen nicht als Fakt dargestellt werden, wenn die Quelldaten dies nicht belegen.

---

# 23. Architekturdiagramme

Das normalisierte Ressourcen- und Relationship-Modell soll automatische Diagramme ermöglichen. Primäres Zwischenformat kann Mermaid sein; später sind auch Graphviz, draw.io-kompatible Daten, SVG oder PNG möglich.

---

# 24. Versions- und Änderungsvergleich

Ein späteres Ziel ist der Vergleich zweier Collector-Snapshots mit Added/Changed/Removed-Ressourcen. Der Exportaufbau ist bereits früh so stabil zu gestalten, dass solche Vergleiche möglich sind.

---

# 25. Azure Resource Changes

Azure Resource Graph Change History kann später ergänzend integriert werden. Sie ersetzt nicht den langfristigen eigenen Snapshot-Vergleich.

---

# 26. Nicht-Ziele der initialen Version

Version 1 ist ausdrücklich kein:

- Azure Deployment Tool,
- Configuration Management Tool,
- Vulnerability Scanner,
- Penetration Testing Tool,
- Kostenoptimierungs-Autopilot,
- Backup-System,
- Monitoring-System,
- Secret-Backup,
- vollständiger Entra-ID-Exporter,
- vollständiger Microsoft-365-Exporter.

Der Fokus liegt auf Azure-Infrastrukturinventarisierung für Dokumentation.

---

# 27. Entwicklungsphasen

## Phase 0 – Projektgrundlage

- [x] Repository anlegen
- [x] `Umsetzungsplan.md` als Source of Truth erstellen
- [x] grundlegende Repository-Struktur beginnen
- [x] `README.md` erstellen
- [x] `.gitignore` erstellen
- [ ] Lizenzentscheidung treffen
- [x] PowerShell-Mindestversion initial definieren
- [ ] Coding-Konventionen vollständig definieren
- [x] Basis-Konfigurationsschema anlegen
- [x] oberste Read-only-Regel definieren
- [ ] automatisches Read-only-Gate implementieren

## Phase 1 – Core Collector

- [x] `Collect-AzureDocumentation.ps1` erstellen
- [x] `Collector.Core.psm1` erstellen
- [x] Voraussetzungen prüfen
- [x] `Az.Accounts` prüfen
- [x] `Az.ResourceGraph` prüfen
- [x] Azure-Kontext erkennen
- [x] interaktive Anmeldung unterstützen
- [x] Tenant-Erkennung / Auswahl implementieren
- [x] Subscription-Erkennung / Auswahl implementieren
- [x] Resource-Group-Scope implementieren
- [x] Output-Verzeichnis erzeugen
- [x] Logging implementieren
- [x] Manifest-Grundstruktur erzeugen
- [ ] Exit Codes vollständig implementieren
- [ ] Read-only-Verifikationsstatus in Manifest/Log integrieren

## Phase 2 – Basisinventar über Azure Resource Graph

- [x] Resource Groups erfassen
- [x] Ressourcen erfassen
- [x] Ressourcentypen über Summary ableiten
- [x] Tags erfassen
- [x] Regionen erfassen
- [x] Pagination unterstützen
- [x] mehrere Subscriptions unterstützen
- [x] Resource-Group-Filter anwenden
- [x] Daten normalisieren
- [x] stabile Sortierung implementieren
- [x] `summary.json` erzeugen
- [ ] Integrationstest gegen reale Test-Subscription

## Phase 3 – Network Collector

- [ ] VNets / Subnets / Peerings
- [ ] NICs / IP Configurations / Public IPs
- [ ] NSGs / Rules
- [ ] Route Tables / Routes
- [ ] NAT Gateways
- [ ] Private Endpoints
- [ ] Private DNS
- [ ] Gateways / Load Balancer / App Gateway / Firewall
- [ ] Netzwerk-Relationships

## Phase 4 – Compute Collector

- [ ] Virtual Machines
- [ ] VM Size / OS / Images
- [ ] Availability
- [ ] OS-/Data-Disks
- [ ] NIC Relationships
- [ ] optional Power State

## Phase 5 – AVD Collector

- [ ] Workspaces
- [ ] Host Pools
- [ ] Application Groups
- [ ] Session Hosts
- [ ] Settings / Start VM on Connect
- [ ] Scaling Plans
- [ ] Session Host -> VM Relationship

## Phase 6 – Storage, Backup und Key Vault

- [ ] Storage Accounts / Security / Network
- [ ] Recovery Services / Backup Vaults
- [ ] Backup Policies / Protected Items
- [ ] Key Vault Metadaten
- [ ] Secret Filtering verifizieren

## Phase 7 – Security und Governance

- [ ] RBAC Role Assignments
- [ ] Role Definitions Referenzen
- [ ] Resource Locks
- [ ] Policy / Initiative Assignments
- [ ] Principal-Datenschutzkonzept

## Phase 8 – Monitoring und Automation

- [ ] Log Analytics
- [ ] Diagnostic Settings
- [ ] Action Groups / Alerts
- [ ] Automation Accounts
- [ ] Runbook-Metadaten
- [ ] Schedules / Associations

## Phase 9 – Relationship Engine

- [ ] Relationship-Schema
- [ ] Resource IDs normalisieren
- [ ] Compute -> Network / Disk
- [ ] Network -> Network
- [ ] AVD -> Compute
- [ ] Private Endpoint -> Resource
- [ ] Diagnostic Settings -> Destination
- [ ] Backup -> Protected Resource
- [ ] Automation Associations

## Phase 10 – Qualitätssicherung und Härtung

- [ ] automatisches Fail-Closed Read-only-Gate
- [ ] Read-only-Tests für jeden Azure-Aufruf
- [ ] Pester Unit Tests ausbauen
- [ ] Integration Tests gegen Test-Subscription
- [ ] leere / mehrere Subscriptions testen
- [ ] eingeschränkte Reader-Rechte testen
- [ ] fehlende Modulberechtigungen testen
- [ ] AVD / Private Endpoints / Sonderfälle testen
- [ ] Secret Leakage Tests
- [ ] JSON Schema Validation
- [ ] PowerShell ScriptAnalyzer

## Phase 11 – Release 1.0

- [ ] README vervollständigen
- [ ] Permissions-Dokumentation
- [ ] Beispielaufrufe
- [ ] synthetischer Beispiel-Export
- [ ] Troubleshooting
- [ ] CHANGELOG / Versionierung
- [ ] Release ZIP
- [ ] finale vollständige Read-only-Verifikation

Ziel: kundengenerisch einsetzbarer und verifiziert ausschließlich lesender Azure Infrastructure Collector.

---

# 28. Spätere Ausbaustufen

Mögliche Komponenten nach stabiler Collector-Version:

- Documentation Generator für Markdown/DOCX/PDF,
- AI Analyzer,
- Diagram Generator,
- Snapshot Diff,
- Scheduled Collection,
- Historisierung.

Die Speicherung von Kundenexporten in Git muss bewusst entschieden werden und ist nicht Standard.

---

# 29. Entwicklungsregeln

## 29.1 Keine kundenspezifischen Sonderfälle im Core

Kundenbesonderheiten sollen generisch über Feature-Erkennung, Konfiguration, Provider oder objektbasierte Logik modelliert werden.

## 29.2 Keine stillen Annahmen

Kann ein Wert nicht sicher bestimmt werden, wird er nicht geraten.

## 29.3 Keine Secrets in Source Control

Erlaubt sind Platzhalter und synthetische Testdaten; echte Secrets, Tokens, Kennwörter, Private Keys und produktive Credential-Dateien sind verboten.

## 29.4 Rückwärtskompatibilität des Exports

Ab Version `1.0.0` werden Breaking Changes am JSON-Schema über eine neue Major Schema Version kenntlich gemacht.

## 29.5 Neue Azure-Aufrufe benötigen Read-only-Nachweis

Jeder neu hinzugefügte Azure-Cmdlet-, REST-, SDK- oder API-Aufruf muss vor Merge/Freigabe fachlich darauf geprüft werden, ob er ausschließlich lesende Wirkung besitzt.

Ein neuer Azure-Aufruf ohne eindeutigen Read-only-Nachweis gilt als nicht freigegeben.

---

# 30. Definition of Done für Module

Ein Collector-Modul gilt erst als fertig, wenn:

- [ ] es kundengenerisch funktioniert,
- [ ] mehrere Subscriptions unterstützt werden,
- [ ] Scope-Filter respektiert werden,
- [ ] es ausschließlich read-only arbeitet,
- [ ] **alle Azure-Aufrufe als read-only verifiziert sind**,
- [ ] Fehler sauber behandelt werden,
- [ ] fehlende Berechtigungen nicht verschleiert werden,
- [ ] keine Secrets exportiert werden,
- [ ] Daten stabil sortiert werden,
- [ ] JSON valide ist,
- [ ] Unit Tests für Kernlogik existieren,
- [ ] das Modul im Manifest seinen Status meldet,
- [ ] die Dokumentation aktualisiert ist,
- [ ] die abschließende Read-only-Verifikation erfolgreich ist.

---

# 31. Definition of Done für Version 1.0

Version 1.0 gilt erst als erreicht, wenn:

1. der Collector auf einem neuen administrativen Arbeitsplatz ohne projektspezifische Anpassung ausführbar ist,
2. interaktive Anmeldung und Tenant-Auswahl möglich sind,
3. mehrere Subscriptions unterstützt werden,
4. Resource Groups optional eingegrenzt werden können,
5. Core-, Compute-, Network-, AVD-, Storage-, Backup-, Security-, Monitoring- und Automation-Daten erfasst werden,
6. Exportdaten maschinenlesbar und strukturiert vorliegen,
7. Manifest und Summary erzeugt werden,
8. Ressourcenbeziehungen modelliert werden,
9. Secret Filtering getestet ist,
10. eingeschränkte Berechtigungen kontrolliert behandelt werden,
11. der Collector keine Azure-Konfiguration oder Azure-Daten verändert,
12. ein realistischer Kundenexport erfolgreich durchgeführt wurde,
13. der Export für KI-Dokumentation verwendbar ist,
14. **die vollständige finale Read-only-Verifikation den Status `READ-ONLY VERIFIED` liefert.**

Ohne Punkt 14 darf Version 1.0 nicht als ausführbarer Release freigegeben werden.

---

# 32. Aktuelle Priorität

```text
P0  Projektgrundlage
P0a Read-only Verification Gate
P1  Core / Auth / Tenant / Subscription / Scope
P2  Basisinventar über Resource Graph
P3  Netzwerk
P4  Compute
P5  AVD
P6  Storage / Backup / Key Vault
P7  Security / Governance
P8  Monitoring / Automation
P9  Relationship Engine
P10 Tests / Härtung
P11 Release 1.0
```

**P0a hat sicherheitstechnisch Vorrang vor allen weiteren ausführbaren Entwicklungsständen.**

Die KI-Dokumentgenerierung beginnt erst, sobald das Collector-Datenmodell ausreichend stabil ist.

---

# 33. Offene Architekturentscheidungen

- exakte Az-Modul-Versionen,
- Modulabhängigkeiten vs. dynamische Installation,
- ZIP standardmäßig aktiv oder optional,
- Identity Display Names / Microsoft Graph,
- Detailtiefe Defender for Cloud,
- Resource Change History in Version 1 oder später,
- Relationship-JSON-Schema,
- Release-/SemVer-Strategie,
- Lizenz des Repositories,
- konkrete technische Umsetzung des statischen/dynamischen Read-only-Gates.

Entscheidungen werden in diesem Dokument nachgeführt.

---

# 34. Leitentscheidung

Der **AzureInfrastructureCollector** soll kein einmaliges Skript für eine konkrete Azure-Umgebung werden, sondern ein wiederverwendbares, tenantfähiges und kundengenerisches **Read-only Inventarisierungswerkzeug**, das als verlässliche Datengrundlage für automatisierte Azure-Dokumentation dient.

```text
Azure ist die Quelle der Wahrheit
        ->
Collector erfasst den Ist-Zustand
        ->
JSON normalisiert die Fakten
        ->
KI interpretiert und formuliert
        ->
Dokumente und Diagramme präsentieren das Ergebnis
```

Die KI darf die Infrastruktur beschreiben und analysieren – der Collector liefert die Fakten.

**Über allem steht jedoch die Sicherheitsregel: Ohne unmittelbar zuvor erfolgreich abgeschlossene Read-only-Verifikation darf kein ausführbarer Collector-Stand zur Ausführung freigegeben werden.**