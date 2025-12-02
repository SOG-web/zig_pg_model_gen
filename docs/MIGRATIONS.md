# Database Migration Guide

This guide explains how to manage database schema changes and migrations using FluentORM.

## Overview

FluentORM includes a built-in migration system that automatically generates SQL migration files based on your TableSchema definitions and provides a command-line tool to execute them safely.

> **⚠️ Note**: The migration system is currently under development and has not been fully tested in production environments. Use with caution and always backup your database before running migrations.

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

This creates SQL migration files in the `migrations/` directory with timestamps:

```
migrations/
├── 1764673549_create_users.sql
├── 1764673549_create_users_down.sql
├── 1764673550_create_posts.sql
├── 1764673550_create_posts_down.sql
└── ...
```

Each table gets both an "up" migration (creates the table) and a "down" migration (drops the table).

### 3. Configure Database Connection

Set environment variables for database connection:

```bash
export FLUENT_DB_HOST=localhost
export FLUENT_DB_PORT=5432
export FLUENT_DB_NAME=my_database
export FLUENT_DB_USER=my_user
export FLUENT_DB_PASSWORD=my_password
```

### 4. Run Migrations

Use the built-in migration runner:

```bash
# Run all pending migrations
zig build migrate

# Or run specific commands
zig build migrate-up      # Run pending migrations
zig build migrate-status  # Show migration status
zig build migrate-down    # Rollback last migration
```

#### Custom Migrations Directory

By default, migrations are stored in `./migrations/`. To use a different directory:

```bash
# Via build option
zig build -Dmigrations-dir=./db/migrations migrate

# Via command line
zig build migrate -- --migrations-dir ./db/migrations
```

### 5. Migration Commands

The migration runner supports several commands:

#### `migrate` / `up`

Runs all pending migrations in timestamp order.

```bash
zig build migrate
```

#### `status`

Shows the current migration status:

```bash
zig build migrate-status
```

Output:

```
Applied migrations:
  ✓ 1764673549_create_users
  ✓ 1764673550_create_posts

Pending migrations:
  ○ 1764673551_add_comments
```

#### `down` / `rollback`

Rolls back the last applied migration.

```bash
zig build migrate-down
```

#### Help

Get detailed help:

```bash
zig build run fluent-migrate -- --help
```

## Migration File Format

Migrations use timestamp-based naming for proper ordering:

```
{timestamp}_{description}.sql          # Up migration
{timestamp}_{description}_down.sql     # Down migration
```

Example:

```
1764673549_create_users.sql
1764673549_create_users_down.sql
1764673550_create_posts.sql
1764673550_create_posts_down.sql
```

The timestamp ensures migrations run in the correct order, and the description makes it clear what each migration does.

## Generated SQL Structure

### Up Migrations

Each up migration includes table creation and constraints:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP
);

-- Create indexes
CREATE UNIQUE INDEX idx_users_email ON users(email);
```

### Down Migrations

Down migrations reverse the changes:

```sql
-- Drop table (cascade removes constraints)
DROP TABLE IF EXISTS users CASCADE;
```

## Schema Changes

FluentORM follows a **schema-first approach**. When you need to modify your database structure, you should **always update your schema files** and regenerate models. Never manually edit SQL files or run ad-hoc ALTER statements.

### The Schema-First Workflow

1. **Modify your schema file** (`schemas/XX_tablename.zig`)
2. **Regenerate models**: `zig build generate && zig build generate-models`
3. **Apply the regenerated migrations** using the migration runner

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

Regenerate and migrate:

```bash
zig build generate
zig build generate-models
zig build migrate
```

### Modifying an Existing Field with `alterField()`

Use the `alterField()` method to modify properties of an existing field:

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

Remove the field definition from your schema file, then regenerate and migrate.

### Important: Keep Schema and Database in Sync

⚠️ **Never manually edit the generated SQL files**. These are regenerated each time you run `zig build generate-models`.

⚠️ **Never run ad-hoc SQL statements** against your database. All schema changes should go through the TableSchema builder.

✅ **Always modify your schema files first**, then regenerate models and apply migrations.

## Migration Safety Features

The migration system includes several safety features:

### Checksum Verification

Each migration file is hashed, and the hash is stored in the database. If a migration file changes after being applied, the system will detect the mismatch and refuse to run.

### Transactional Migrations

Each migration runs in a database transaction. If it fails, all changes are rolled back.

### Dependency Ordering

Migrations run in timestamp order, ensuring tables are created before their foreign keys.

### Rollback Support

You can rollback the last migration if something goes wrong.

## Migration Best Practices

### 1. Version Control

Commit your schema files to version control. The generated migration files can be regenerated:

```bash
git add schemas/
git commit -m "Add phone field to users schema"
```

### 2. Schema-First Always

Never bypass the schema. All database structure should be defined in your `schemas/` directory.

### 3. Backup Before Migrations

Always backup your database before applying schema changes:

```bash
pg_dump -U postgres mydb > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 4. Test in Development First

Never run untested migrations directly in production:

1. Test locally
2. Test in staging environment
3. Deploy to production

### 5. Use Descriptive Names

Use clear descriptions in your schema filenames:

```
01_users.zig           # ✅ Clear
01_u.zig              # ❌ Unclear
01_user_table.zig     # ❌ Redundant
```

### 6. Use `alterField()` for Modifications

When changing field properties, use `alterField()` instead of modifying the original field definition:

```zig
// Original
t.string(.{ .name = "bio" });

// Later modification - clear intent
t.alterField(.{ .name = "bio", .not_null = false, .redacted = true });
```

## Troubleshooting

### Migration Fails: Connection Error

**Problem**: Cannot connect to PostgreSQL.

**Solution**: Check environment variables and ensure PostgreSQL is running:

```bash
# Test connection
psql -U $FLUENT_DB_USER -d $FLUENT_DB_NAME -h $FLUENT_DB_HOST -p $FLUENT_DB_PORT
```

### Migration Fails: Checksum Mismatch

**Problem**: Migration file was modified after being applied.

**Solution**: Never modify migration files after they've been applied. If you need to change something, create a new migration.

### Migration Fails: Foreign Key Constraint

**Problem**: Foreign key references a table that doesn't exist yet.

**Solution**: Ensure schema files are numbered correctly for dependency order.

### UUID Extension Error

**Problem**: `gen_random_uuid()` function not found.

**Solution**: The migration system automatically creates the UUID extension. If it fails, ensure your database user has the necessary permissions.

### Migration Table Not Found

**Problem**: `_fluent_migrations` table doesn't exist.

**Solution**: The migration runner creates this table automatically on first run. Ensure your database user has table creation permissions.

## Migration System Status

> **⚠️ Development Status**: The migration system is currently under active development and has not been fully tested in production environments. While it includes safety features like checksum verification and transactional execution, it should be used with caution.
>
> **Known Limitations**:
>
> - Complex schema changes (renaming fields, changing types) may require manual intervention
> - No support for data migrations (changing existing data during schema changes)
> - Rollback only supports the last migration
>
> **Roadmap**:
>
> - Multi-step rollbacks
> - Data migration support
> - Schema diffing and automatic migration generation
> - Migration testing framework

## Next Steps

- See [GETTING_STARTED.md](GETTING_STARTED.md) for complete setup instructions
- See [SCHEMA.md](SCHEMA.md) for defining table schemas
- See [BASE_MODEL.md](BASE_MODEL.md) for using generated models
- See [RELATIONSHIPS.md](RELATIONSHIPS.md) for managing foreign keys

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
