# P6 – Storage / Backup / Key Vault

## Ziel

P6 erweitert den AzureInfrastructureCollector um drei getrennte, normalisierte und ausschließlich lesende Inventardomänen:

- Azure Storage Accounts
- Azure Backup / Data Protection
- Azure Key Vault

Die drei Domänen werden gemeinsam als P6-Collector-Phase ausgeführt, aber in getrennte Exportdateien geschrieben:

```text
Inventory/storage.json
Inventory/backup.json
Inventory/keyVault.json
```

Die Trennung ist bewusst gewählt, damit Datenmodell, Secret-Grenzen und spätere Dokumentbausteine unabhängig bleiben.

## Azure-Zugriffsarchitektur

P6 verwendet ausschließlich den bereits bestehenden Azure-Resource-Graph-Pfad:

```text
Resources
  -> Queries/Storage.kql
  -> Queries/KeyVault.kql
  -> Queries/Backup.TopLevel.kql

RecoveryServicesResources
  -> Queries/Backup.Resources.kql

alle Queries
  -> Invoke-CollectorResourceGraph / Search-AzGraph
  -> lokale Normalisierung
  -> Collector.ExportSecurity
  -> JSON-Export
```

Es werden keine neuen Azure PowerShell Fachcmdlets, keine REST-Aufrufe, keine Azure CLI und kein SDK-Schreibpfad eingeführt. Die beiden Backup-Tabellen werden getrennt abgefragt und erst lokal zusammengeführt.

## P6a – Storage

### Scope

Erfasst werden `Microsoft.Storage/storageAccounts` mit insbesondere:

- ARM Resource ID, Name, Subscription, Resource Group, Region und Tags
- Kind
- SKU / Redundanz
- Access Tier
- Minimum TLS Version
- HTTPS-only
- Public Network Access
- Shared-Key-Zugriff erlaubt/gesperrt
- Blob Public Access erlaubt/gesperrt
- Default-to-OAuth
- HNS / Data Lake Gen2
- NFSv3
- SFTP
- Local-User-Feature
- Large File Shares
- Network ACL Default Action / Bypass
- VNet/Subnet-Regeln als ARM IDs
- IP-Regeln

### Relationships

```text
Storage Account -> AllowsSubnet -> P3 Subnet
```

Private-Endpoint-Beziehungen werden nicht aus Storage-Rohdaten dupliziert; sofern vorhanden, werden sie bereits über das P3-Private-Endpoint-Modell Resource-ID-basiert abgebildet.

### Ausgeschlossen

P6a fragt/exportiert insbesondere nicht:

- Account Keys
- `listKeys`
- SAS Tokens / SAS Signatures
- Connection Strings
- Shared Access Signatures
- Credential-Werte
- vollständige rohe Storage-Properties
- CMK-/Key-Vault-Key-URIs

## P6b – Backup

### ARG-Unterstützung

Top-Level-Vaults werden aus `Resources` gelesen:

- `Microsoft.RecoveryServices/vaults`
- `Microsoft.DataProtection/backupVaults`

Backup-Metadaten werden separat aus `RecoveryServicesResources` gelesen:

- `Microsoft.RecoveryServices/vaults/backupPolicies`
- `Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems`
- `Microsoft.DataProtection/backupVaults/backupPolicies`
- `Microsoft.DataProtection/backupVaults/backupInstances`

Die beiden Tabellen werden nicht per Cross-Table-`union` verbunden; die Ergebnisse werden erst lokal im Collector zusammengeführt.

### Recovery Services Vaults

Normalisiert werden insbesondere:

- SKU
- Public Network Access
- Standard-Tier-Storage-Redundanz
- Cross Region Restore
- Cross Subscription Restore
- Soft Delete State / Retention
- Enhanced Security State
- Immutability State

### Data Protection Backup Vaults

Normalisiert werden insbesondere:

- Storage Settings / Redundanz
- Soft Delete State / Retention
- Immutability State
- Cross Region Restore
- Cross Subscription Restore

CMK-Key-URIs und Identity-Detailobjekte werden bewusst nicht normalisiert.

### Backup Policies

P6 normalisiert eine providerübergreifende Policy-Grundstruktur:

- ARM ID / Name
- Parent Vault ARM ID
- Provider Model (`RecoveryServices` / `DataProtection`)
- Data Source Types als stabiles Array
- Protected Item Count, soweit geliefert
- Schedule Run Frequency, soweit als stabiles Metadatum geliefert
- Policy-/Retention-Typ, soweit geliefert

Komplexe provider- und workload-spezifische Schedule-/Retention-Detailbäume werden im P6-MVP nicht roh exportiert.

### Protected Items / Backup Instances

Normalisiert werden:

- Protected Item / Backup Instance ARM ID
- Parent Vault ARM ID
- Friendly Name
- Data Source / Backup Management Type
- geschützte Resource ARM ID
- Backup Policy ARM ID / Name
- aktueller Protection State
- Last Recovery Point als lokale UTC-/ISO-8601-Normalisierung

### Relationships

```text
Vault -> ContainsBackupPolicy -> Backup Policy
Recovery Services Vault -> ContainsProtectedItem -> Protected Item
Backup Vault -> ContainsBackupInstance -> Backup Instance
Protected Item / Backup Instance -> UsesBackupPolicy -> Backup Policy
Protected Item / Backup Instance -> ProtectsResource -> Azure Resource
```

Die Zuordnung zu P4-VMs, Storage Accounts oder anderen Azure-Ressourcen erfolgt ausschließlich über die von Azure gelieferten ARM IDs. Es gibt keine Namensheuristik.

### Ausgeschlossen

P6b fragt/exportiert insbesondere nicht:

- `datasourceAuthCredentials`
- Secret Store Values / Credential Values
- Key Vault Key URIs / CMK-Key-Material
- Identity-Detailobjekte mit nicht benötigten IDs
- Backup-Job-Historie
- Restore Requests
- vollständige rohe Policy-/Protected-Item-Properties

Backup-Job-Historie ist kein Bestandteil von P6. Sie kann später im Monitoring-/Operations-Kontext bewertet werden.

## P6c – Key Vault

### Scope

Erfasst werden `Microsoft.KeyVault/vaults` mit:

- ARM Resource ID, Name, Subscription, Resource Group, Region und Tags
- SKU
- Authorization Model (`RBAC` / `AccessPolicy`), abgeleitet ausschließlich aus `enableRbacAuthorization`
- Soft Delete
- Purge Protection
- Soft-Delete-Retention
- Public Network Access
- Enabled for Deployment
- Enabled for Disk Encryption
- Enabled for Template Deployment
- Network ACL Default Action / Bypass
- VNet/Subnet-Regeln als ARM IDs
- IP-Regeln

### Relationships

```text
Key Vault -> AllowsSubnet -> P3 Subnet
```

Private-Endpoint-Beziehungen werden, sofern vorhanden, über P3 abgebildet.

### Ausgeschlossen

P6c fragt/exportiert insbesondere nicht:

- Secret Values
- Key Material
- Certificate Private Keys / PFX
- Keys-/Secrets-/Certificates-Data-Plane-Listen
- `accessPolicies`
- Object IDs / Tenant IDs aus Access Policies
- Vault URI
- Secret-/Key-URIs
- vollständige rohe Vault-Properties

Key-/Secret-/Certificate-Objektmetadaten sind im P6-MVP bewusst nicht enthalten, da dafür ein zusätzlicher Data-Plane-Leseweg und eine gesonderte Least-Privilege-/Read-only-Prüfung erforderlich wären.

## Exportmodelle

### `storage.json`

```json
{
  "schemaVersion": "1.0",
  "summary": {},
  "storageAccounts": [],
  "relationships": []
}
```

### `backup.json`

```json
{
  "schemaVersion": "1.0",
  "summary": {},
  "recoveryServicesVaults": [],
  "backupVaults": [],
  "backupPolicies": [],
  "recoveryProtectedItems": [],
  "dataProtectionBackupInstances": [],
  "relationships": []
}
```

### `keyVault.json`

```json
{
  "schemaVersion": "1.0",
  "summary": {},
  "keyVaults": [],
  "relationships": []
}
```

Leere Collections bleiben echte JSON-Arrays `[]`.

## Collector-Integration

P6 ist als eigene Phase 6 von 8 in `Collect-AzureDocumentation.ps1` integriert. Storage, Key Vault und Backup besitzen getrennte `try/catch`-Grenzen, damit ein isolierter P6-Unterbereich bei erfolgreichem Core/P3/P4/P5 nicht die übrigen P6-Domänen verdeckt.

Phase 7 schreibt zusätzlich `storage.json`, `backup.json` und `keyVault.json`. Phase 8 ergänzt `summary.storage`, `summary.backup` und `summary.keyVault` sowie die P6-Relationship-Counts in Log/Konsolenausgabe.

Die bereits real validierten P3-/P4-/P5-Module und Queries wurden für P6 nicht verändert. P6 wird ausschließlich zusätzlich hinter P5 integriert.

## Statische Read-only-Gegenprüfung

Der aktuelle P6-Diff führt ausschließlich zusätzliche Azure-Resource-Graph-Abfragen über den vorhandenen `Invoke-CollectorResourceGraph`-/`Search-AzGraph`-Pfad ein. Im P6-Ausführungspfad wurden keine neuen Az-Fachcmdlets, REST-/Web-Aufrufe, Azure-CLI-Befehle, SDK-Schreibpfade oder Data-Plane-Key-/Secret-Abfragen ergänzt.

Dies ist ausdrücklich nur die **statische** Gegenprüfung. Durch die neuen ausführbaren P6-Dateien ist die Laufzeitfreigabe des zuvor validierten P5-Stands für den aktuellen `main` nicht mehr ausreichend. Vor einem realen P6-Azure-Lauf muss die komplette automatische Pre-Azure-Validierung erneut erfolgreich sein.

## Fehler- und Statussemantik

P6 ist ein Fachmodul. Ein isolierter P6-Fehler darf bei weiterhin erfolgreichem Core/P3/P4/P5 zu `PartialSuccess` führen. Jeder Read-only-/Pre-Azure-Validierungsfehler blockiert Azure weiterhin vollständig.

Protection State und Last Recovery Point sind Momentaufnahmen des Erfassungszeitpunkts und keine historische SLA-/Backup-Erfolgsstatistik.

## Definition of Done P6

- [x] Microsoft-/ARG-Unterstützung für Storage, Key Vault und Backup geprüft
- [x] Scope und Secret-/PII-Grenzen dokumentiert
- [x] getrennte Queries für `Resources` und `RecoveryServicesResources` implementiert
- [x] `Collector.Storage.psm1` implementiert
- [x] `Collector.Backup.psm1` implementiert
- [x] `Collector.KeyVault.psm1` implementiert
- [x] Unit-/Regressionstests für Query-Safety, Normalisierung, Relationships, Array-Shape und Empty Arrays ergänzt
- [x] P6 vollständig in `Collect-AzureDocumentation.ps1` integriert
- [x] `storage.json`, `backup.json`, `keyVault.json` und Summary-Bereiche im normalen Collector integriert
- [x] statische Read-only-Gegenprüfung des finalen ausführbaren P6-Stands: kein neuer Azure-Write-/REST-/CLI-/SDK-/Data-Plane-Secret-Pfad erkannt
- [ ] automatische Pre-Azure-Validierung mit 0 Testfehlern, `READ-ONLY VERIFIED` und `READY FOR AZURE TEST`
- [ ] realer P6-Kundenexport erzeugt
- [ ] P6-Exports gegen Core/P3/P4/P5, Relationships, Orphans, Array-/Schema-Stabilität und Secret-Leakage geprüft

> **P6 ist vollständig implementiert und statisch gegengeprüft, aber noch nicht für Azure freigegeben bzw. real validiert. Der aktuelle ausführbare Stand muss vor Azure erneut die vollständige automatische Pre-Azure-Validierung bestehen.**
