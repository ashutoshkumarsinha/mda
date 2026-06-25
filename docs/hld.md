
Here is the complete High-Level Design (HLD) for MDE, combining the native Swift architecture with a minimalist, Caliu-inspired SwiftUI GUI specification.

---
https://caliuapp.com/


## MDE: High-Level Design & GUI Specification

## 1. System Architecture Overview

MDE uses a native, local-first architecture built on the Apple ecosystem. The client manages all text parsing, graphing, and indexing on-device. The cloud layer acts purely as a secure, end-to-end encrypted synchronization relay.

```unset
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

## 2.1 UI & Layout Layer (SwiftUI + TextKit 2)

- App Structure: Single-window multi-column layout on macOS; split-view collapsing layout on iOS/iPadOS.
- Text View Representable: A custom wrapper wrapping `NSTextView` / `UITextView` to hook into TextKit 2. This bypasses SwiftUI's generic limitations to provide high-performance text manipulations.
- Hybrid Token Rendering: A custom `NSTextStorage` subclass tracks the current cursor position (`NSRange`). When the cursor enters a Markdown block, formatting tokens (e.g., `**`, `#`, `[[`) are visible. When the cursor leaves, the tokens are programmatically hidden using font attributes with zero alpha or collapsed formatting metrics, leaving clean rich text.

## 2.2 Core Processing Engine (Swift)

- AST Parser: Employs Apple's open-source `swift-markdown` library. As text streams from the user, typing events are debounced by 300ms.
- Background Worker (Actor): A dedicated Swift Actor processes the updated string to construct an Abstract Syntax Tree (AST), ensuring zero lag on the main UI thread.
- Link & Tag Extractor: Scans the AST nodes for inline tags (`#work/active`) and WikiLinks (`[[Project Alpha]]`). It converts these nodes into relationship entities.

## 2.3 Storage & Indexing Engine (GRDB + SQLite)

- Local Database: Powered by `GRDB.swift` running an embedded SQLite instance.
- Search Engine: Uses SQLite’s FTS5 extension. Note text updates synchronously rewrite the full-text search index, allowing sub-millisecond keyword matches.
- Graph Engine: Stores structural link paths in an edge table `(source_note_id, target_note_id)`. Complex nested tags are fetched recursively using Common Table Expressions (CTEs).

## 2.4 Sync & Security Pipeline (CloudKit + CryptoKit)

- Data Unit: Notes are broken down into metadata records and text delta records using State-based CRDTs.
- Zero-Knowledge Encryption: The client generates a unique symmetric key stored securely in the local Apple Keychain. Text content is encrypted using `CryptoKit.AES.GCM` before transmission. CloudKit only manages raw encrypted data blocks; Apple cannot read the note text.

---

## 3. GUI Design Specification

CanvasMD uses a strict minimalist aesthetic: 0.5pt rules, generous margins, deep monotone variations, and color accents reserved exclusively for actionable states (like links and active tags).

## 3.1 Layout Schematics

## macOS Architecture (3-Column Layout)

```unset
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

## iOS Architecture (Collapsible View Layer Stack)

```unset
[ View 1: Sidebar ]        [ View 2: Note List ]       [ View 3: Full Editor ]
+-------------------+      +-------------------+      +-------------------+

|  Tags         (X) |      | Back      Notes   |      | Back              |
|  # All            | ---> | Q Search...       | ---> | # Project Overview|
|  # inbox          |      |                   |      |                   |
|  ▼ work           |      | Project Overview  |      | This is a hybrid  |
|    active         |      | Weekly Retro      |      | markdown engine...|
+-------------------+      +-------------------+      +-------------------+
```

## 3.2 Key UI Components

## 1. The Tag Tree Navigation Sidebar (Left Column)

- Behavior: Displays a nested hierarchy generated dynamically from the SQLite tag path matrix.
- Interaction: Clicking a parent tag (e.g., `#work`) reveals a dropdown containing sub-tags (`active`, `archive`). Selecting any tag updates the adjacent Note List query predicate immediately.
- Visual Styling: Chromeless design using system font weights. Inactive states match primary text secondary color opacity (60%). Active selections use subtle capsule backgrounds.

## 2. The Dynamic Note Card List (Middle Column)

- Header: Integrated native search bar tapping directly into FTS5.
- Cards: Each item lists a relative timestamp, a clean text title, and an unformatted raw text snippet snippet.
- Context Actions: Right-clicking or long-pressing a card opens a context menu with options to Pin to Top, Merge Notes, or Delete.

## 3. The Hybrid Canvas Surface (Main Workspace Column)

- Typography: Proportional tracking, system monospaced text for block elements, and high-readability layout configurations.
- Inline Transformations:
    
    - Headers: `# Title` scales up and turns bold dynamically. The `#` indicator opacity drops to 15% unless focused.
    - Links: `[[Link Name]]` removes brackets automatically when the cursor steps away, rendering as an underlined colored token.
    - Lists & Checkboxes: `- [ ]` generates a native, clickable SwiftUI checkbox directly inline over the text storage layout layer.
    

---

## 4. Key Data Flows

## The Real-Time Render Pipeline

```unset
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
             [Clean HTML-like View Rendered to User]
```

## The Background Sync Architecture

```unset
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

- Frontend Layout: SwiftUI (macOS 14+ / iOS 17+ Native).
- Text Processor: TextKit 2 coupled with `swift-markdown`.
- Database Engine: GRDB.swift interacting with SQLite (FTS5 enabled).
- Concurrency Model: Swift Actors and Modern Task Pipelines (`async/await`).
- Cloud Network: Native CloudKit Framework.
- Crypto Layer: Apple CryptoKit (AES-GCM-256 validation profiles).

Here is the complete production-grade database schema utilizing GRDB.swift and SQLite.

This schema includes standard full-text search (FTS5), an adjacency list edge-table for the bi-directional note graph, a self-referencing hierarchy for nested tags, and sync tracking fields for a State-based CRDT pipeline.

## 1. Database Schema Definitions (Swift Migration)

This file defines the structural schema using a native GRDB `DatabaseMigrator`. Copy and paste this directly into your Swift project database initialization pipeline.

```swift
import Foundation
import GRDB

struct DatabaseSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        #if DEBUG
        // Speed up unit tests and local development previews
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        
        migrator.registerMigration("v1_initial_schema") { db in
            
            // =========================================================================
            // 1. NOTES TABLE
            // =========================================================================
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey() // UUID String
                t.column("title", .text).notNull().defaults(to: "")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("is_deleted", .boolean).notNull().defaults(to: false)
                
                // CRDT / Sync Metadata Fields
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("client_updated_at", .datetime).notNull()
                t.column("checksum", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_note_updated_at", on: "note", columns: ["updated_at"])
            try db.create(index: "idx_note_is_pinned", on: "note", columns: ["is_pinned"])
            
            // =========================================================================
            // 2. NOTES FULL-TEXT SEARCH (FTS5) VIRTUAL TABLE
            // =========================================================================
            // FTS5 content-indexed table for lightning-fast character searching
            try db.execute(sql: """
            CREATE VIRTUAL TABLE note_fts USING fts5(
                title, 
                content, 
                content='note', 
                content_rowid='id',
                tokenize='porter unicode61'
            );
            """)
            
            // Triggers to keep the note_fts virtual table automatically synchronized
            try db.execute(sql: """
            CREATE TRIGGER note_ai AFTER INSERT ON note BEGIN
                INSERT INTO note_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
            END;
            CREATE TRIGGER note_ad AFTER DELETE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content) VALUES('delete', old.id, old.title, old.content);
            END;
            CREATE TRIGGER note_au AFTER UPDATE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content) VALUES('delete', old.id, old.title, old.content);
                INSERT INTO note_fts(rowid, title, content) VALUES (new.id, new.title, new.content);
            END;
            """)
            
            // =========================================================================
            // 3. TAGS TABLE (Nested Hierarchy Pattern)
            // =========================================================================
            try db.create(table: "tag") { t in
                t.column("id", .text).primaryKey() // Unique Tag ID hash
                t.column("name", .text).notNull()   // Single node segment text (e.g., "active")
                t.column("path", .text).notNull()   // Full resolved context text (e.g., "work/project/active")
                
                // Self-referencing link configuration for tree nesting mechanics
                t.column("parent_id", .text)
                    .references("tag", onDelete: .cascade)
                
                t.uniqueKey(["path"]) // Enforce uniqueness on the unique structural paths
            }
            try db.create(index: "idx_tag_parent_id", on: "tag", columns: ["parent_id"])
            
            // =========================================================================
            // 4. NOTE TO TAG RELATION JOIN TABLE (Many-to-Many Bridge)
            // =========================================================================
            try db.create(table: "note_tag") { t in
                t.column("note_id", .text).notNull().references("note", onDelete: .cascade)
                t.column("tag_id", .text).notNull().references("tag", onDelete: .cascade)
                t.primaryKey(["note_id", "tag_id"])
            }
            try db.create(index: "idx_note_tag_tag_id", on: "note_tag", columns: ["tag_id"])
            
            // =========================================================================
            // 5. BI-DIRECTIONAL LINK GRAPH TABLE (Adjacency List Structure)
            // =========================================================================
            try db.create(table: "note_link") { t in
                t.column("id", .text).primaryKey() // Unique edge instance string
                t.column("source_id", .text).notNull().references("note", onDelete: .cascade)
                t.column("target_title", .text).notNull() // Tracked by Title text until target file resolves
                t.column("target_id", .text).references("note", onDelete: .setNull)
                
                t.uniqueKey(["source_id", "target_title", "target_id"])
            }
            try db.create(index: "idx_note_link_source", on: "note_link", columns: ["source_id"])
            try db.create(index: "idx_note_link_target", on: "note_link", columns: ["target_id"])
            try db.create(index: "idx_note_link_target_title", on: "note_link", columns: ["target_title"])
        }
        
        return migrator
    }
}
```

---

## 2. High-Utility Advanced SQL Query Recipes

To drive a folderless UI cleanly, use these dynamic SQLite queries via GRDB.

## A. Generating the Full Nested Tag Sidebar Hierarchy

This recursive CTE generates all parent-child nesting paths sorted alphabetically. It ensures that clicking a root folder easily maps out sub-nodes.

```sql
WITH RECURSIVE tag_tree(id, name, path, parent_id, level) AS (
    -- Anchor member: Get all top-level root tags
    SELECT id, name, path, parent_id, 0 AS level
    FROM tag
    WHERE parent_id IS NULL
    
    UNION ALL
    
    -- Recursive member: Bind children to parents sequentially
    SELECT t.id, t.name, t.path, t.parent_id, tt.level + 1
    FROM tag t
    JOIN tag_tree tt ON t.parent_id = tt.id
)
SELECT id, name, path, parent_id, level 
FROM tag_tree 
ORDER BY path ASC;
```

## B. Querying Bi-Directional Backlinks

Use this query to surface the exact referencing notes panel located at the bottom of the active note view canvas layer.

```sql
-- Find every note targeting Note X by tracking standard explicitly bound references
SELECT n.id, n.title, n.content, n.updated_at
FROM note n
JOIN note_link nl ON nl.source_id = n.id
WHERE nl.target_id = :active_note_id 
   OR nl.target_title = :active_note_title
   AND n.is_deleted = 0
ORDER BY n.is_pinned DESC, n.updated_at DESC;
```

## C. Instant Full-Text Keyword Search (FTS5 Rank Ordering)

Runs a fast index-scan returning matching instances ordered by relevance scores calculated directly inside the virtual framework. [1]

```sql
SELECT n.id, n.title, n.updated_at, snippet(note_fts, 1, '==', '==', '...', 10) AS match_snippet
FROM note n
JOIN note_fts f ON f.rowid = n.id
WHERE note_fts MATCH :search_query AND n.is_deleted = 0
ORDER BY rank;
```



  


