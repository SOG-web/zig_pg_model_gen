# FluentORM Migration System - Implementation Plan

## Overview

This document outlines the plan for implementing a comprehensive migration system for FluentORM that supports:

1. **Incremental migrations** - Track and apply only new changes
2. **Schema merging** - Multiple schema files can contribute to the same table
3. **Automatic migration runner** - Single command to apply all pending migrations

## Implementation Progress

| Phase                     | Status      | Description                                                         |
| ------------------------- | ----------- | ------------------------------------------------------------------- |
| Phase 1: Schema Merging   | ✅ COMPLETE | Multiple schema files can contribute to same table via `table_name` |
| Phase 2: Snapshot System  | ✅ COMPLETE | `src/snapshot.zig` - saves/loads schema state to JSON               |
| Phase 3: Diff Engine      | ✅ COMPLETE | `src/diff.zig` - detects changes between snapshots                  |
| Phase 4: Migration Files  | ✅ COMPLETE | `src/sql_generator.zig` - generates one file per change             |
| Phase 5: Migration Runner | ✅ COMPLETE | `src/migration_runner.zig` - executes migrations via pg.zig         |
| Phase 6: Update & Docs    | 🔲 TODO     | Update documentation                                                |

### Completed Components

- **`src/snapshot.zig`** - Schema snapshot generation and loading

  - `createDatabaseSnapshot()` - Creates snapshot from TableSchema array
  - `saveSnapshot()` - Saves snapshot to JSON file
  - `loadSnapshot()` - Loads snapshot from JSON file
  - Tracks: tables, fields, indexes, relationships, has_many

- **`src/diff.zig`** - Diff engine for detecting changes

  - `diffSnapshots()` - Compares two snapshots
  - Detects: new/removed/modified tables, fields, indexes, relationships
  - Returns `SchemaDiff` with all changes

- **`src/sql_generator.zig`** - Incremental migration file generator

  - `writeIncrementalMigrationFiles()` - Generates one file per change
  - Supports: CREATE TABLE, ADD COLUMN, DROP COLUMN, ALTER COLUMN
  - Supports: ADD INDEX, DROP INDEX, ADD FK, DROP FK
  - Generates both up and down migrations

- **`src/registry_generator.zig`** - Groups schemas by `table_name`

  - Extracts `pub const table_name` from schema files
  - Groups multiple files contributing to same table
  - Generates `registry.zig` with `getAllSchemas()`

- **`src/generate_model.zig`** - CLI that generates runner.zig

  - Updated to use snapshot/diff/incremental approach
  - Configurable paths (schemas_dir, output_dir, sql_output_dir)

- **`src/migration_runner.zig`** - Migration runner using pg.zig
  - Connects to PostgreSQL using environment variables
  - Creates `_fluent_migrations` tracking table
  - Scans migrations directory for pending migrations
  - Executes migrations in transaction with checksum verification
  - Supports: `up` (apply), `status` (show pending), `down` (rollback)

### Migration File Naming

Files are named with Unix timestamps for ordering:

```
migrations/
├── 1764673549_create_users.sql
├── 1764673549_create_users_down.sql
├── 1764673550_create_posts.sql
├── 1764673550_create_posts_down.sql
├── 1764673551_posts_add_index_idx_posts_user_created.sql
├── 1764673551_posts_add_index_idx_posts_user_created_down.sql
├── 1764673552_posts_add_fk_user_id.sql
├── 1764673552_posts_add_fk_user_id_down.sql
└── ...
```

---

## Current Problems

### Problem 1: No Incremental Migrations

Currently:

- `01_users.zig` → always generates `migrations/tables/01_users.sql`
- If you modify `01_users.zig`, it **overwrites** the same SQL file
- `CREATE TABLE IF NOT EXISTS` does nothing if the table already exists
- **New fields are never added to existing tables!**

### Problem 2: One File Per Table

Currently:

- Each schema file creates one table
- No way to organize large tables across multiple files
- No way to have team members work on different parts of a table

### Problem 3: Manual Migration Execution

Currently:

- Users must manually run `psql` commands
- No tracking of which migrations have been applied
- Easy to forget or run migrations out of order

---

## Solution Design

### Part 1: Schema File Structure

Add a `table_name` constant to identify which table a schema file belongs to:

```zig
// schemas/01_users.zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub const table_name = "users";  // Required: identifies the table

pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true, ... });
    t.string(.{ .name = "email", .unique = true });
    t.string(.{ .name = "name" });
    // ... base fields
}
```

```zig
// schemas/02_users_auth.zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub const table_name = "users";  // Same table - will be merged!

pub fn build(t: *TableSchema) void {
    t.string(.{ .name = "password_hash", .redacted = true });
    t.boolean(.{ .name = "is_active", .default_value = "true" });
}
```

```zig
// schemas/03_posts.zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub const table_name = "posts";  // Different table

pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true, ... });
    t.string(.{ .name = "title" });
    t.belongsTo(.{ .name = "author", .column = "user_id", .references_table = "users" });
}
```

### Part 2: Schema Snapshot System

Store the last known state of all schemas in a snapshot file:

```
schemas/
├── 01_users.zig
├── 02_users_auth.zig
├── 03_posts.zig
├── registry.zig           # Auto-generated
├── runner.zig             # Auto-generated
└── .fluent_snapshot.json  # Schema state snapshot
```

**Snapshot file structure:**

```json
{
  "version": 1,
  "generated_at": "2024-12-02T10:00:00Z",
  "tables": {
    "users": {
      "fields": [
        { "name": "id", "type": "uuid", "primary_key": true, "unique": true, "not_null": true },
        { "name": "email", "type": "text", "unique": true, "not_null": true },
        { "name": "name", "type": "text", "not_null": true },
        { "name": "password_hash", "type": "text", "not_null": true, "redacted": true },
        { "name": "is_active", "type": "boolean", "default_value": "true" }
      ],
      "relationships": [...],
      "indexes": [...],
      "source_files": ["01_users.zig", "02_users_auth.zig"]
    },
    "posts": {
      "fields": [...],
      "relationships": [...],
      "source_files": ["03_posts.zig"]
    }
  }
}
```

### Part 3: Diff Engine

When running `zig build generate-models`, the system:

1. **Loads current schemas** - Parse all `schemas/*.zig` files
2. **Groups by `table_name`** - Merge schemas with same table name
3. **Loads snapshot** - Read `.fluent_snapshot.json` (if exists)
4. **Computes diff** - Compare current vs snapshot
5. **Generates incremental migrations** - Only for changes detected

**Diff detection:**

| Change Type      | Detection                               | Generated SQL                    |
| ---------------- | --------------------------------------- | -------------------------------- |
| New table        | Table in current, not in snapshot       | `CREATE TABLE ...`               |
| New field        | Field in current, not in snapshot table | `ALTER TABLE ADD COLUMN ...`     |
| Modified field   | Field properties changed                | `ALTER TABLE ALTER COLUMN ...`   |
| Removed field    | Field in snapshot, not in current       | `ALTER TABLE DROP COLUMN ...`    |
| New relationship | FK in current, not in snapshot          | `ALTER TABLE ADD CONSTRAINT ...` |
| New index        | Index in current, not in snapshot       | `CREATE INDEX ...`               |

> **Note**: Field removal automatically generates `DROP COLUMN` statements. Ensure you have backups before running migrations that remove fields.

### Part 4: Migration File Structure

Migrations are named with **timestamps** for clear ordering and conflict avoidance:

```
migrations/
├── 20241202100000_create_users.sql
├── 20241202100001_create_posts.sql
├── 20241202100002_posts_add_fk_user_id.sql
├── 20241202103000_users_add_column_phone.sql
├── 20241202103001_users_alter_column_bio.sql
├── 20241202110000_create_comments.sql
└── 20241202110001_comments_add_fk_user_id.sql
```

**Timestamp format:** `YYYYMMDDHHMMSS` (year, month, day, hour, minute, second)

**Migration file format:**

```sql
-- Migration: 20241202103000_users_add_column_phone.sql
-- Generated: 2024-12-02T10:30:00Z
-- Table: users
-- Type: add_column

ALTER TABLE users ADD COLUMN phone TEXT;
```

### Part 5: Migration Tracking Table

The migration runner creates a tracking table in the database:

```sql
CREATE TABLE IF NOT EXISTS _fluent_migrations (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    checksum TEXT NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
```

- `name`: Migration filename (e.g., `004_users_add_column_phone.sql`)
- `checksum`: Hash of the SQL content (detect tampering)
- `applied_at`: When the migration was applied

### Part 6: Migration Runner

A new Zig module: `src/migration_runner.zig`

**Features:**

- Connects to database using environment variables or config
- Creates `_fluent_migrations` table if not exists
- Reads all files from `migrations/` directory
- Compares against `_fluent_migrations` to find pending
- Executes pending migrations in order
- Records successful migrations with checksum

**Usage:**

```bash
# Apply all pending migrations
zig build migrate

# Check migration status (dry run)
zig build migrate -- --status

# Rollback last migration (future feature)
zig build migrate -- --rollback
```

**Environment variables:**

```bash
export FLUENT_DB_HOST=localhost
export FLUENT_DB_PORT=5432
export FLUENT_DB_NAME=mydb
export FLUENT_DB_USER=postgres
export FLUENT_DB_PASSWORD=password
```

---

## Implementation Steps

### Phase 1: Schema Merging

1. **Update schema file convention**

   - Add `pub const table_name = "...";` requirement
   - Update documentation

2. **Modify registry generator** (`src/registry_generator.zig`)

   - Scan for `table_name` constant in each schema file
   - Group schema files by `table_name`
   - Pass grouped info to runner

3. **Modify runner generator** (`schemas/runner.zig`)
   - For each unique table, create ONE `TableSchema`
   - Call all related `build()` functions in order
   - Generate ONE model per table

### Phase 2: Snapshot System

1. **Create snapshot generator** (`src/snapshot.zig`)

   - After schema parsing, serialize state to JSON
   - Include: tables, fields, types, constraints, relationships
   - Save to `schemas/.fluent_snapshot.json`

2. **Create snapshot loader**
   - Parse existing snapshot file
   - Return structured data for comparison

### Phase 3: Diff Engine

1. **Create diff engine** (`src/diff_engine.zig`)

   - Compare current schema state vs snapshot
   - Detect: new tables, new fields, modified fields, removed fields
   - Detect: new relationships, new indexes

2. **Generate appropriate SQL**
   - `CREATE TABLE` for new tables
   - `ALTER TABLE ADD COLUMN` for new fields
   - `ALTER TABLE ALTER COLUMN` for modifications
   - `ALTER TABLE DROP COLUMN` for removals
   - `ALTER TABLE ADD CONSTRAINT` for new FKs

### Phase 4: Sequential Migration Files

1. **Create migration file generator** (`src/migration_generator.zig`)

   - Find highest existing migration number
   - Generate new files with next sequential number
   - Include metadata comments in SQL files

2. **Update SQL generator** (`src/sql_generator.zig`)
   - Support `ALTER TABLE` statements
   - Support incremental constraint additions

### Phase 5: Migration Runner

1. **Create migration runner** (`src/migration_runner.zig`)

   - Database connection using pg.zig
   - Create `_fluent_migrations` table
   - Read migration files from directory
   - Compare against applied migrations
   - Execute pending in order
   - Record with checksum

2. **Add build step** (`build.zig`)
   - Add `migrate` step
   - Pass environment variables or config file path

### Phase 6: Update Existing Schemas

1. **Update test_proj schemas**

   - Add `table_name` to all existing schema files

2. **Update documentation**
   - MIGRATIONS.md - new workflow
   - SCHEMA.md - table_name requirement
   - GETTING_STARTED.md - new commands

---

## File Changes Summary

### New Files

| File                          | Purpose                                  |
| ----------------------------- | ---------------------------------------- |
| `src/snapshot.zig`            | Schema snapshot generation and loading   |
| `src/diff_engine.zig`         | Compare schemas, detect changes          |
| `src/migration_generator.zig` | Generate incremental migration SQL files |
| `src/migration_runner.zig`    | Execute migrations against database      |

### Modified Files

| File                         | Changes                          |
| ---------------------------- | -------------------------------- |
| `src/registry_generator.zig` | Group schemas by `table_name`    |
| `src/sql_generator.zig`      | Support `ALTER TABLE` statements |
| `src/model_generator.zig`    | Handle merged schemas            |
| `build.zig`                  | Add `migrate` build step         |
| `schemas/*.zig`              | Add `table_name` constant        |

---

## User Workflow (After Implementation)

### Initial Setup

```bash
# 1. Define schemas with table_name
# schemas/01_users.zig
pub const table_name = "users";
pub fn build(t: *TableSchema) void { ... }

# 2. Generate models and initial migrations
zig build generate
zig build generate-models

# 3. Run migrations
zig build migrate
```

### Adding a New Field

```bash
# 1. Edit schema file - add new field
# schemas/01_users.zig
t.string(.{ .name = "phone", .not_null = false });

# 2. Regenerate (creates incremental migration)
zig build generate-models
# Creates: migrations/20241202103000_users_add_column_phone.sql

# 3. Apply migration
zig build migrate
# Applies only the new migration
```

### Adding Fields in Separate File

```bash
# 1. Create new schema file for same table
# schemas/02_users_profile.zig
pub const table_name = "users";
pub fn build(t: *TableSchema) void {
    t.string(.{ .name = "bio", .not_null = false });
    t.string(.{ .name = "avatar_url", .not_null = false });
}

# 2. Regenerate
zig build generate-models
# Creates: migrations/20241202110000_users_add_column_bio.sql
# Creates: migrations/20241202110001_users_add_column_avatar_url.sql
# Model users.zig now includes bio and avatar_url

# 3. Apply migrations
zig build migrate
```

### Checking Migration Status

```bash
zig build migrate -- --status

# Output:
# Applied migrations:
#   ✓ 20241202100000_create_users.sql (2024-12-02 10:00:00)
#   ✓ 20241202100001_create_posts.sql (2024-12-02 10:00:01)
#   ✓ 20241202100002_posts_add_fk_user_id.sql (2024-12-02 10:00:02)
#
# Pending migrations:
#   ○ 20241202103000_users_add_column_phone.sql
```

---

## Future Enhancements

- [ ] `t.renameField()` - Rename columns with data preservation
- [ ] `zig build migrate -- --rollback` - Rollback migrations
- [ ] `zig build migrate -- --to=005` - Migrate to specific version
- [ ] Migration locking for concurrent deployments
- [ ] Seed data support
- [ ] Multiple database support (MySQL, SQLite)

---

## Design Decisions

The following decisions have been made for this implementation:

| Question            | Decision                                                       |
| ------------------- | -------------------------------------------------------------- |
| Snapshot location   | Save in the schema folder (wherever user points their schemas) |
| Migration naming    | Use timestamps (`YYYYMMDDHHMMSS_description.sql`)              |
| Destructive changes | No confirmation required - just execute                        |
| Field removal       | Automatically generate `DROP COLUMN`                           |
| Configuration       | Environment variables only (no config file)                    |

---

## Timeline Estimate

| Phase                     | Effort    | Dependencies |
| ------------------------- | --------- | ------------ |
| Phase 1: Schema Merging   | 2-3 hours | None         |
| Phase 2: Snapshot System  | 2-3 hours | Phase 1      |
| Phase 3: Diff Engine      | 3-4 hours | Phase 2      |
| Phase 4: Migration Files  | 2-3 hours | Phase 3      |
| Phase 5: Migration Runner | 3-4 hours | Phase 4      |
| Phase 6: Update & Docs    | 2-3 hours | Phase 5      |

**Total: ~15-20 hours**
