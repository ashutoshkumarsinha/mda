# MDE — High-Level Design & GUI Specification

> **Status:** Draft v0.2  
> **Last updated:** 2026-07-02  
> **Companion doc:** [Product & Functional Specification](./spec.md) — requirements, phases, and acceptance criteria  
> **Index:** [docs/README.md](./README.md)

Design inspiration: [Caliu](https://caliuapp.com/)

---

## 1. System Architecture Overview

MDE uses a native, local-first architecture built on the Apple ecosystem. The client manages all text parsing, graphing, and indexing on-device. The cloud layer acts purely as a secure, end-to-end encrypted synchronization relay.

```
+-----------------------------------------------------------------------------+
|                         NATIVE MAC/IOS CLIENT (SWIFT)                       |
|                                                                             |
|   +-----------------------+     +-------------------+     +-------------+   |
|   |  SwiftUI Views        | --> | TextKit 2 Engine  | --> | GRDB Engine |   |
|   |  (Sidebar, Graph, UI) |     | (NSTextStorage)   |     | (SQLite)    |   |
|   +-----------------------+     +-------------------+     +-------------+   |
|               ^                          |                       |          |
|               | State                    v AST Tokens            v FTS5     |
|   +---------------------------------------------------------------------+   |
|   |               Background Processing Actor (Swift Concurrency)       |   |
|   +---------------------------------------------------------------------+   |
+-----------------------------------------------------------------------------+
                                       ^
                                       | CloudKit Sync / CryptoKit
                                       v
+-----------------------------------------------------------------------------+
|                            APPLE CLOUD STORAGE                              |
|                                                                             |
|   +---------------------------------------------------------------------+   |
|   | Private iCloud Container (Encrypted Record Blobs & CRDT Deltas)     |   |
|   +---------------------------------------------------------------------+   |
+-----------------------------------------------------------------------------+
```

---

## 2. Component Design

### 2.1 UI & Layout Layer (SwiftUI + TextKit 2)

- **App structure:** Single-window multi-column layout on macOS; split-view collapsing layout on iOS/iPadOS.
- **Text view representable:** A custom wrapper around `NSTextView` / `UITextView` to hook into TextKit 2. This bypasses SwiftUI's generic limitations to provide high-performance text manipulations.
- **Hybrid token rendering:** A custom `NSTextStorage` subclass tracks the current cursor position (`NSRange`). When the cursor enters a Markdown block, formatting tokens (e.g., `**`, `#`, `[[`) are visible. When the cursor leaves, the tokens are programmatically hidden using font attributes with zero alpha or collapsed formatting metrics, leaving clean rich text.

### 2.2 Core Processing Engine (Swift)

- **AST parser:** Employs Apple's open-source `swift-markdown` library. As text streams from the user, typing events are debounced by 300 ms.
- **Background worker (Actor):** A dedicated Swift Actor processes the updated string to construct an Abstract Syntax Tree (AST), ensuring zero lag on the main UI thread.
- **Link & tag extractor:** Scans the AST nodes for inline tags (`#work/active`) and WikiLinks (`[[Project Alpha]]`). It converts these nodes into relationship entities.

### 2.3 Storage & Indexing Engine (GRDB + SQLite)

- **Local database:** Powered by `GRDB.swift` running an embedded SQLite instance.
- **Search engine:** Uses SQLite's FTS5 extension. Note text updates synchronously rewrite the full-text search index, allowing sub-millisecond keyword matches.
- **Graph engine:** Stores structural link paths in an edge table `(source_note_id, target_note_id)`. Complex nested tags are fetched recursively using Common Table Expressions (CTEs).

### 2.4 Sync & Security Pipeline (CloudKit + CryptoKit)

- **Data unit:** Notes are broken down into metadata records and text delta records using state-based CRDTs.
- **Zero-knowledge encryption:** The client generates a unique symmetric key stored securely in the local Apple Keychain. Text content is encrypted using `CryptoKit.AES.GCM` before transmission. CloudKit only manages raw encrypted data blocks; Apple cannot read the note text.

### 2.5 Platform integrations (v5–v6)

- **Core Spotlight:** `SpotlightIndexer` writes `CSSearchableItem` entries keyed `vaultID/noteID`. `SpotlightDeepLink` handles `com.apple.corespotlightitem` continuations to select the note in the active vault.
- **Glance data:** `VaultGlanceStore` writes daily-note title/snippet to App Group `group.name.aks.mde` for Widget and Watch targets.
- **Extensions:** `mdeShareExtension` (iOS share sheet → pending text), `mdeWidgetExtension` (WidgetKit timeline), `mdeWatchApp` (watchOS glance).

---

## 3. GUI Design Specification

MDE uses a strict minimalist aesthetic: 0.5 pt rules, generous margins, deep monotone variations, and color accents reserved exclusively for actionable states (like links and active tags).

### 3.1 Layout Schematics

#### macOS (3-column layout)

```
+------------+------------------------+---------------------------------------+
|  TAGS      |  NOTES                 |  CANVAS EDITOR                        |
|            |                        |                                       |
|  # All     |  [10:42 AM]            |  # Project Overview                   |
|  # inbox   |  Project Overview      |                                       |
|  # ideas   |  Notes regarding t...  |  This is a hybrid markdown engine.    |
|            |                        |  You can link to [[Meeting Notes]]    |
|  ▼ work    |  [Yesterday]           |  or tag this item inline as           |
|    active  |  Weekly Retro          |  #work/active.                        |
|    archive |  Action items from...  |                                       |
|            |                        |  - [ ] Complete HLD                   |
|            |                        |  - [x] Write UI Specs                 |
|            |                        |                                       |
+------------+------------------------+---------------------------------------+
```

#### iOS (collapsible view layer stack)

```
[ View 1: Sidebar ]        [ View 2: Note List ]       [ View 3: Full Editor ]
+-------------------+      +-------------------+      +-------------------+
|  Tags         (X) |      | Back      Notes   |      | Back              |
|  # All            | ---> | Q Search...       | ---> | # Project Overview|
|  # inbox          |      |                   |      |                   |
|  ▼ work           |      | Project Overview  |      | This is a hybrid  |
|    active         |      | Weekly Retro      |      | markdown engine...|
+-------------------+      +-------------------+      +-------------------+
```

### 3.2 Key UI Components

#### Tag tree navigation sidebar (left column)

- **Behavior:** Displays a nested hierarchy generated dynamically from the SQLite tag path matrix.
- **Interaction:** Clicking a parent tag (e.g., `#work`) reveals a dropdown containing sub-tags (`active`, `archive`). Selecting any tag updates the adjacent note list query predicate immediately.
- **Visual styling:** Chromeless design using system font weights. Inactive states match primary text at secondary color opacity (60%). Active selections use subtle capsule backgrounds.

#### Dynamic note card list (middle column)

- **Header:** Integrated native search bar wired to FTS5.
- **Cards:** Each item lists a relative timestamp, a clean text title, and an unformatted plain-text snippet.
- **Context actions:** Right-clicking or long-pressing a card opens a context menu with options to Pin to Top, Merge Notes, or Delete.

#### Hybrid canvas surface (main workspace column)

- **Typography:** Proportional tracking, system monospaced text for block elements, and high-readability layout configurations.
- **Inline transformations:**
  - **Headers:** `# Title` scales up and turns bold dynamically. The `#` indicator opacity drops to 15% unless focused.
  - **Links:** `[[Link Name]]` removes brackets automatically when the cursor steps away, rendering as an underlined colored token.
  - **Lists & checkboxes:** `- [ ]` generates a native, clickable SwiftUI checkbox inline over the text storage layout layer.

---

## 4. Key Data Flows

### 4.1 Real-time render pipeline

```
[User Types Text]
       │
       ▼
[TextKit 2 updates NSTextStorage] ────► [Renders raw glyphs immediately]
       │
       ▼ (300ms Debounce)
[Background Actor initiates swift-markdown AST Parse]
       │
       ├───► [Extract Links/Tags] ───► [Update Graph Cache] ───► [Refresh Sidebar View]
       │
       └───► [Generate Formatting Attribute Map]
                   │
                   ▼ (Main Thread Injection)
             [Apply Font Alpha/Scaling to NSTextStorage Attributes]
                   │
                   ▼
             [Clean rich-text view rendered to user]
```

### 4.2 Background sync architecture

```
[Local Edit Confirmed] ──► [Write Encrypted Payload to GRDB]
                                   │
                                   ▼
                       [Trigger CloudKit Sync Engine]
                                   │
                                   ▼
                       [Push AES-GCM Encrypted Chunks]
                                   │
                                   ▼
                       [Apple CloudKit Database]
                                   │
                                   ▼ (Push Notification)
                       [Remote Device Receives Chunk]
                                   │
                                   ▼
                       [Decrypt via Keychain Local Key]
                                   │
                                   ▼
                       [Merge changes using CRDT Matrix]
```

---

## 5. Technology Stack Summary

| Layer | Technology |
|-------|------------|
| Frontend layout | SwiftUI (macOS 14+ / iOS 17+) |
| Text processor | TextKit 2 + `swift-markdown` |
| Database | GRDB.swift + SQLite (FTS5) |
| Concurrency | Swift Actors, `async`/`await` |
| Cloud network | CloudKit |
| Crypto | CryptoKit (AES-GCM-256) |

---

## 6. Database Schema

Production-grade schema using GRDB.swift and SQLite. Includes FTS5 full-text search, an adjacency-list edge table for the bidirectional note graph, a self-referencing hierarchy for nested tags, and sync tracking fields for a state-based CRDT pipeline.

### 6.1 FTS5 rowid strategy

SQLite FTS5 requires an **integer** `rowid` for content-synced virtual tables. UUIDs live in a separate `id` column for app-level identity and CloudKit records.

| Column | Type | Role |
|--------|------|------|
| `rowid` | `INTEGER PRIMARY KEY AUTOINCREMENT` | SQLite internal key; FTS5 `content_rowid` target |
| `id` | `TEXT UNIQUE NOT NULL` | UUID string exposed to app and sync layer |

All foreign keys (`note_tag.note_id`, `note_link.source_id`, etc.) reference `note.id` (UUID text), not `rowid`.

### 6.2 Swift migration (`DatabaseMigrator`)

```swift
import Foundation
import GRDB

struct DatabaseSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial_schema") { db in

            // 1. NOTES TABLE
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .text).notNull().unique() // UUID
                t.column("title", .text).notNull().defaults(to: "")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("is_deleted", .boolean).notNull().defaults(to: false)

                // CRDT / sync metadata
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("client_updated_at", .datetime).notNull()
                t.column("checksum", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_note_id", on: "note", columns: ["id"])
            try db.create(index: "idx_note_updated_at", on: "note", columns: ["updated_at"])
            try db.create(index: "idx_note_is_pinned", on: "note", columns: ["is_pinned"])

            // 2. FTS5 VIRTUAL TABLE (content-synced to note.rowid)
            try db.execute(sql: """
            CREATE VIRTUAL TABLE note_fts USING fts5(
                title,
                content,
                content='note',
                content_rowid='rowid',
                tokenize='porter unicode61'
            );
            """)

            try db.execute(sql: """
            CREATE TRIGGER note_ai AFTER INSERT ON note BEGIN
                INSERT INTO note_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END;
            CREATE TRIGGER note_ad AFTER DELETE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
            END;
            CREATE TRIGGER note_au AFTER UPDATE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
                INSERT INTO note_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END;
            """)

            // 3. TAGS TABLE (nested hierarchy)
            try db.create(table: "tag") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("parent_id", .text).references("tag", onDelete: .cascade)
                t.uniqueKey(["path"])
            }
            try db.create(index: "idx_tag_parent_id", on: "tag", columns: ["parent_id"])

            // 4. NOTE ↔ TAG (many-to-many)
            try db.create(table: "note_tag") { t in
                t.column("note_id", .text).notNull().references("note", onDelete: .cascade, columns: ["id"])
                t.column("tag_id", .text).notNull().references("tag", onDelete: .cascade)
                t.primaryKey(["note_id", "tag_id"])
            }
            try db.create(index: "idx_note_tag_tag_id", on: "note_tag", columns: ["tag_id"])

            // 5. BI-DIRECTIONAL LINK GRAPH
            try db.create(table: "note_link") { t in
                t.column("id", .text).primaryKey()
                t.column("source_id", .text).notNull().references("note", onDelete: .cascade, columns: ["id"])
                t.column("target_title", .text).notNull()
                t.column("target_id", .text).references("note", onDelete: .setNull, columns: ["id"])
                t.uniqueKey(["source_id", "target_title"])
            }
            try db.create(index: "idx_note_link_source", on: "note_link", columns: ["source_id"])
            try db.create(index: "idx_note_link_target", on: "note_link", columns: ["target_id"])
            try db.create(index: "idx_note_link_target_title", on: "note_link", columns: ["target_title"])
        }

        return migrator
    }
}
```

> **Note:** `references(..., columns: ["id"])` requires GRDB 6+. If targeting an older GRDB version, enforce UUID FKs via application logic or raw SQL `REFERENCES note(id)`.

---

## 7. SQL Query Recipes

Dynamic SQLite queries via GRDB to drive the folderless UI.

### 7.1 Nested tag sidebar hierarchy

Recursive CTE generating all parent-child paths sorted alphabetically.

```sql
WITH RECURSIVE tag_tree(id, name, path, parent_id, level) AS (
    SELECT id, name, path, parent_id, 0 AS level
    FROM tag
    WHERE parent_id IS NULL

    UNION ALL

    SELECT t.id, t.name, t.path, t.parent_id, tt.level + 1
    FROM tag t
    JOIN tag_tree tt ON t.parent_id = tt.id
)
SELECT id, name, path, parent_id, level
FROM tag_tree
ORDER BY path ASC;
```

### 7.2 Bidirectional backlinks

Surfaces the referencing-notes panel at the bottom of the active note canvas. Parentheses ensure `is_deleted` applies to all matches.

```sql
SELECT n.id, n.title, n.content, n.updated_at
FROM note n
JOIN note_link nl ON nl.source_id = n.id
WHERE (nl.target_id = :active_note_id OR nl.target_title = :active_note_title)
  AND n.is_deleted = 0
ORDER BY n.is_pinned DESC, n.updated_at DESC;
```

### 7.3 Full-text search (FTS5 rank ordering)

Fast index scan with relevance ranking and snippet highlighting. Join on integer `rowid`.

```sql
SELECT
    n.id,
    n.title,
    n.updated_at,
    snippet(note_fts, 1, '==', '==', '...', 10) AS match_snippet
FROM note n
JOIN note_fts f ON f.rowid = n.rowid
WHERE note_fts MATCH :search_query
  AND n.is_deleted = 0
ORDER BY rank;
```

---

## 8. Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | — | Initial HLD draft |
| 0.2 | 2026-07-02 | Standardized MDE naming; fixed heading hierarchy; corrected FTS5 integer rowid schema; fixed backlinks SQL precedence; cross-linked spec.md and README; removed CanvasMD alias |
