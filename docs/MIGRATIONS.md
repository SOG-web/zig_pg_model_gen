# Database Migration Guide

This guide explains how to manage database schema changes and migrations using FluentORM.

## Overview

FluentORM automatically generates SQL migration files based on your TableSchema definitions. These migration files must be executed manually using `psql` or integrated into your deployment process.

> **Note**: FluentORM does not currently include a built-in migration runner. You must execute migrations manually or create your own runner script.

## Migration Workflow

### 1. Define Your Schema

Create schema files in the `schemas/` directory using the `XX_tablename.zig` naming convention:

```
schemas/
├── 01_users.zig
├── 02_posts.zig
└── 03_comments.zig
```

The number prefix determines the execution order, ensuring tables are created in dependency order (e.g., users before posts if posts references users).

### 2. Generate Migrations

Run the two-step generation process:

```bash
# Step 1: Generate registry and runner
zig build generate

# Step 2: Generate model files and SQL migrations
zig build generate-models
```

This creates SQL migration files in the `migrations/` directory with a specific structure:

```
migrations/
├── tables/
│   ├── 01_users.sql
│   ├── 02_posts.sql
│   └── 03_comments.sql
└── constraints/
    ├── 02_posts_fk.sql
    └── 03_comments_fk.sql
```

- **tables/**: CREATE TABLE statements (run first)
- **constraints/**: Foreign key constraints (run after all tables exist)

### 3. Execute Migrations

Use `psql` or your favorite PostgreSQL client to run migrations in order:

```bash
# First: Create all tables
psql -U postgres -d mydb -f migrations/tables/01_users.sql
psql -U postgres -d mydb -f migrations/tables/02_posts.sql
psql -U postgres -d mydb -f migrations/tables/03_comments.sql

# Then: Add foreign key constraints
psql -U postgres -d mydb -f migrations/constraints/02_posts_fk.sql
psql -U postgres -d mydb -f migrations/constraints/03_comments_fk.sql
```

Or run all migrations with a shell script:

```bash
#!/bin/bash
DB_NAME="mydb"
DB_USER="postgres"

# Run table migrations in order
for f in migrations/tables/*.sql; do
    echo "Running $f..."
    psql -U $DB_USER -d $DB_NAME -f "$f"
done

# Run constraint migrations in order
for f in migrations/constraints/*.sql; do
    echo "Running $f..."
    psql -U $DB_USER -d $DB_NAME -f "$f"
done

echo "Migrations complete!"
```

## Generated SQL Structure

### Table Migrations (migrations/tables/)

Each table migration includes:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP
);
```

### Constraint Migrations (migrations/constraints/)

Foreign key constraints are generated separately:

```sql
ALTER TABLE posts
ADD CONSTRAINT fk_posts_user_id
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE CASCADE;
```

This separation ensures tables exist before constraints reference them.

## Schema Changes

FluentORM follows a **schema-first approach**. When you need to modify your database structure, you should **always update your schema files** and regenerate models. Never manually edit SQL files or run ad-hoc ALTER statements, as this will cause your generated models to be out of sync with your database.

### The Schema-First Workflow

1. **Modify your schema file** (`schemas/XX_tablename.zig`)
2. **Regenerate models**: `zig build generate && zig build generate-models`
3. **Apply the regenerated migrations** to your database

### Adding a New Field

Add the new field to your schema file:

```zig
// schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    // ... existing fields ...

    // Add a new field
    t.string(.{
        .name = "phone",
        .not_null = false,
        .create_input = .optional,
    });
}
```

Regenerate:

```bash
zig build generate
zig build generate-models
```

Then re-run the generated table migration to apply the changes.

### Modifying an Existing Field with `alterField()`

Use the `alterField()` method to modify properties of an existing field. This is useful when you want to change constraints, input modes, or other properties without redefining the entire field.

```zig
// schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    // Original field definition
    t.string(.{
        .name = "bio",
        .not_null = true,
    });

    // Later, alter it to be optional and redacted
    t.alterField(.{
        .name = "bio",
        .not_null = false,
        .create_input = .optional,
        .redacted = true,
    });
}
```

**`alterField()` Options**:

| Option               | Type                | Description                          |
| -------------------- | ------------------- | ------------------------------------ |
| `name`               | `[]const u8`        | **Required**: Name of field to alter |
| `type`               | `?FieldType`        | Change the field type                |
| `primary_key`        | `?bool`             | Change primary key status            |
| `unique`             | `?bool`             | Change unique constraint             |
| `not_null`           | `?bool`             | Change NOT NULL constraint           |
| `create_input`       | `?InputMode`        | Change create input mode             |
| `update_input`       | `?bool`             | Change update input inclusion        |
| `redacted`           | `?bool`             | Change JSON response redaction       |
| `default_value`      | `?[]const u8`       | Change SQL default value             |
| `auto_generated`     | `?bool`             | Change auto-generation status        |
| `auto_generate_type` | `?AutoGenerateType` | Change auto-generation type          |

Only specify the properties you want to change; others retain their original values.

### Altering Multiple Fields

Use `alterFields()` to modify multiple fields at once:

```zig
t.alterFields(&.{
    .{ .name = "email", .unique = true },
    .{ .name = "bio", .not_null = false, .redacted = true },
    .{ .name = "password_hash", .redacted = true },
});
```

### Removing a Field

Remove the field definition from your schema file, then regenerate:

```zig
// schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    // Remove the field you no longer need by deleting its definition
    // t.string(.{ .name = "phone" }); // <-- Delete this line
}
```

Then regenerate and re-run the migrations.

### Renaming a Field

> **Coming Soon**: Field renaming via `t.renameField()` is planned for a future release.

Currently, FluentORM does not support direct field renaming. This feature is on the roadmap.

### Important: Keep Schema and Database in Sync

⚠️ **Never manually edit the generated SQL files** in `migrations/tables/` or `migrations/constraints/`. These are regenerated each time you run `zig build generate-models`.

⚠️ **Never run ad-hoc SQL statements** against your database. All schema changes should go through the TableSchema builder.

✅ **Always modify your schema files first**, then regenerate models and apply migrations.

## Migration Best Practices

### 1. Version Control

Commit your schema files to version control. The generated migration files can be regenerated:

```bash
git add schemas/
git commit -m "Add phone field to users schema"
```

### 2. Schema-First Always

Never bypass the schema. All database structure should be defined in your `schemas/` directory:

```
schemas/
├── 01_users.zig       # Users table definition
├── 02_posts.zig       # Posts table definition
├── 03_comments.zig    # Comments table definition
├── registry.zig       # Auto-generated
└── runner.zig         # Auto-generated
```

### 3. Dependency Order

Use numbered prefixes to ensure correct migration order:

- `01_users.zig` - No dependencies
- `02_posts.zig` - Depends on users (has `user_id` FK)
- `03_comments.zig` - Depends on users and posts

### 4. Backup Before Migrations

Always backup your database before applying schema changes:

```bash
pg_dump -U postgres mydb > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 5. Test in Development First

Never run untested migrations directly in production:

1. Test locally
2. Test in staging environment
3. Deploy to production

### 6. Use `alterField()` for Modifications

When changing field properties, use `alterField()` instead of modifying the original field definition. This makes changes explicit and trackable:

```zig
// Original
t.string(.{ .name = "bio" });

// Later modification - clear intent
t.alterField(.{ .name = "bio", .not_null = false, .redacted = true });
```

## Available DDL Operations

Generated models include these DDL methods from the BaseModel:

### Check Table Existence

```zig
const exists = try Users.tableExists(&pool);
if (exists) {
    std.debug.print("Table exists\n", .{});
}
```

Returns `true` if the table exists in the database.

### Truncate Table

```zig
try Users.truncate(&pool);
```

Removes all rows but keeps the table structure.

**Warning**: This permanently deletes all data in the table.

> **Note**: `createTable()`, `dropTable()`, and `createIndexes()` methods are not currently available. Use the generated SQL files or `psql` commands instead.

## Troubleshooting

### Migration Fails: Constraint Violation

**Problem**: Foreign key or unique constraint fails.

**Solution**: Ensure tables are created in dependency order. Check the number prefix in schema filenames.

### Migration Fails: Column Already Exists

**Problem**: Trying to add a column that already exists.

**Solution**: The generated migrations use `CREATE TABLE IF NOT EXISTS`. If you need to modify an existing table, update your schema and regenerate.

### UUID Extension Error

**Problem**: `gen_random_uuid()` function not found.

**Solution**: The generated migrations include `CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`. Ensure the migration file is executed properly.

### Connection Refused

**Problem**: Cannot connect to PostgreSQL.

**Solution**: Check connection settings, ensure PostgreSQL is running, and verify credentials.

## Next Steps

- See [SCHEMA.md](SCHEMA.md) for defining table schemas
- See [BASE_MODEL.md](BASE_MODEL.md) for using generated models
- See [RELATIONSHIPS.md](RELATIONSHIPS.md) for managing foreign keys
