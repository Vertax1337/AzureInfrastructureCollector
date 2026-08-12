# P4 – Compute

## Ziel

P4 erweitert den AzureInfrastructureCollector um ein kundengenerisches, normalisiertes und ausschließlich lesendes Compute-Inventar. Es werden nur tatsächlich vorhandene Compute-Ressourcen des ausgewählten Tenant-/Subscription-/Resource-Group-Scopes verarbeitet.

P4 verwendet denselben bestehenden Azure-Zugriffspfad wie Core und P3:

```text
Azure Resource Graph
  -> Queries/Compute.kql
  -> Invoke-CollectorResourceGraph / Search-AzGraph
  -> Collector.Compute.psm1
  -> Collector.ExportSecurity.psm1
  -> Inventory/compute.json
```

Es wird kein zusätzliches Azure-Cmdlet, kein REST-Aufruf, keine Azure CLI und kein SDK-Schreibpfad eingeführt.

## Scope

P4 erfasst:

- `Microsoft.Compute/virtualMachines`
- `Microsoft.Compute/disks`
- `Microsoft.Compute/availabilitySets`

### Virtual Machines

Normalisiert werden insbesondere:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Availability Zones
- VM Size
- Provisioning State
- Power State als optionale Momentaufnahme aus Azure Resource Graph Extended Properties
- Marketplace-/Gallery-Image-Referenz
- Availability-Set-Referenz
- OS-Disk-Metadaten
- Data-Disk-Metadaten
- Network-Interface-Referenzen

Der Power State ist Best Effort. Fehlt `properties.extended.instanceView.powerState.code`, bleibt das Feld leer; daraus wird kein Zustand erfunden.

### Managed Disks

Normalisiert werden insbesondere:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- Availability Zones
- Storage SKU (`skuName` / `skuTier`)
- Performance Tier, soweit Azure dieses Feld liefert
- Größe in GiB
- OS Type, soweit vorhanden
- Disk State
- Creation Option
- `managedBy` als Resource-ID-Referenz

### Availability Sets

Normalisiert werden insbesondere:

- Resource ID, Name, Subscription, Resource Group, Region und Tags
- SKU
- Fault Domain Count
- Update Domain Count
- enthaltene VM Resource IDs
- Proximity Placement Group Resource ID, soweit vorhanden

## Exportmodell

`Inventory/compute.json` hat folgende Top-Level-Struktur:

```json
{
  "schemaVersion": "1.0",
  "summary": {},
  "virtualMachines": [],
  "managedDisks": [],
  "availabilitySets": [],
  "relationships": []
}
```

VM-Objekte enthalten normalisierte Unterobjekte bzw. Arrays für:

- `imageReference`
- `osDisk`
- `networkInterfaces`
- `dataDisks`

Leere Collections bleiben echte JSON-Arrays `[]`.

## Relationships

P4 erzeugt ausschließlich Resource-ID-basierte Beziehungen:

```text
VM -> UsesNetworkInterface -> Network Interface
VM -> UsesOsDisk -> Managed Disk
VM -> UsesDataDisk -> Managed Disk
VM -> UsesAvailabilitySet -> Availability Set
Managed Disk -> ManagedByResource -> Azure Resource
Availability Set -> ContainsVm -> VM
Availability Set -> UsesProximityPlacementGroup -> Proximity Placement Group
```

Beziehungen werden nur erzeugt, wenn Azure eine nichtleere Resource ID liefert. Fehlende Beziehungen werden nicht aus Namen erraten.

## Sicherheits- und Datenminimierungsgrenze

P4 fragt bzw. exportiert bewusst keine vollständigen VM-`properties`-Blöcke und insbesondere nicht:

- `osProfile`
- Administrator-Benutzernamen oder Kennwörter
- SSH Public Keys / SSH-Konfiguration
- `userData`
- Boot-Diagnostics-Storage-URIs
- VM Extension Settings oder `protectedSettings`
- VM Extensions als eigene P4-Ressourcen
- Restore Point Collections
- Key-/Secret-URLs aus Disk Encryption
- `encryptionSettingsCollection`

`vmDataDisks` wird von Azure Resource Graph als verschachteltes Datenobjekt geliefert. `Collector.Compute.psm1` übernimmt daraus ausschließlich die explizit freigegebenen Felder Name, LUN, Caching, Create/Delete Option, Größe, Managed-Disk-ID, Storage Account Type und Write Accelerator. Unmanaged-VHD-/Image-URIs sowie Disk-Encryption-Set-Referenzen werden nicht in `compute.json` normalisiert. Ein Regressionstest erzwingt diese Exportgrenze.

Die zentrale `Collector.ExportSecurity.psm1`-Härtung wird vor dem Schreiben von `compute.json` zusätzlich auf das vollständige normalisierte Compute-Modell angewendet.

## Power-State-Semantik

`powerState` ist ausschließlich eine Momentaufnahme des Erfassungszeitpunkts und kein historischer Laufzeitnachweis. Ein fehlender Wert ist `unknown/not returned`, nicht automatisch `stopped`, `deallocated` oder `running`.

## Fehlerverhalten

P4 ist ein Fachmodul. Ein isolierter P4-Fehler darf bei weiterhin erfolgreichem Core-Inventar zu `PartialSuccess` führen. Ein Read-only-/Pre-Azure-Validierungsfehler bleibt dagegen immer kritisch und blockiert Azure vollständig.

## Definition of Done P4

P4 gilt erst als abgeschlossen, wenn:

- [x] Compute-Scope und Sicherheitsgrenze dokumentiert sind
- [x] `Queries/Compute.kql` implementiert ist
- [x] `Collector.Compute.psm1` implementiert ist
- [x] Unit-/Regressionstests für Query, VM, Disks, Availability Sets, Secret-/URI-Minimierung und leere Arrays vorhanden sind
- [ ] `Collect-AzureDocumentation.ps1` P4 vollständig integriert
- [ ] automatische Pre-Azure-Validierung des finalen P4-Stands mit 0 Testfehlern und `READ-ONLY VERIFIED` / `READY FOR AZURE TEST` erfolgreich
- [ ] realer P4-Kundenexport erzeugt
- [ ] `compute.json` gegen Core-Inventar, Relationships, Orphans, Array-/Schema-Stabilität und Secret Leakage geprüft

Bis diese letzten Punkte bestätigt sind, ist P4 implementiert bzw. in Implementierung, aber noch nicht real validiert.
