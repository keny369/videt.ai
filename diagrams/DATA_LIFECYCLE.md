# Data Lifecycle Diagram

## Status

- Status: Canonical
- Version: 1.0
- Last Updated: 2026-07-16

## Authority

This is the canonical data lifecycle diagram for F1.

## Scope

This diagram defines lifecycle stages for major data classes from creation through destruction.

## Terminology

Canonical terms are defined in [../specification/015 DATA_LIFECYCLE.md](../specification/015%20DATA_LIFECYCLE.md).

```mermaid
flowchart LR
    CREATE[Create and Ingest] --> VALIDATE[Validate and Classify]
    VALIDATE --> STORE[Store]
    STORE --> TRANSFORM[Transform and Index]
    TRANSFORM --> RETRIEVE[Retrieve and Use]
    RETRIEVE --> EXPORT[Export]
    RETRIEVE --> ARCHIVE[Archive]
    RETRIEVE --> LOGDEL[Logical Delete]
    LOGDEL --> HOLD{Active Legal Hold Intersects?}
    HOLD -->|Yes| BLOCKED[Deletion Job Blocked]
    BLOCKED -->|Hold Released| HOLD
    HOLD -->|No| TOMBSTONE[Write Backup Tombstone]
    TOMBSTONE --> PHYSDEL[Delete Primary, Index, Cache And Key]
    PHYSDEL --> BACKUPPURGE[Backup Purge Or Cryptographic Erasure]
    BACKUPPURGE --> DELETION_AUDIT[Persist Immutable Deletion Evidence - Audit Evidence]
    DELETION_AUDIT --> DESTROY[Irreversible Destruction Complete]
    ARCHIVE --> RESTORE[Restore]
    RESTORE --> RESTOREGUARD[Apply Tombstones Before Read]
    RESTOREGUARD --> RETRIEVE
```

## Related Documents

- [../specification/015 DATA_LIFECYCLE.md](../specification/015%20DATA_LIFECYCLE.md)
- [../specification/019 VERSIONING.md](../specification/019%20VERSIONING.md)
