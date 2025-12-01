# Database Migration Guide

This guide explains how to manage database schema changes and migrations using FluentORM.

## Overview

FluentORM automatically generates SQL migration files based on your TableSchema definitions. These migration files can be executed manually or integrated into your deployment process.

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

This creates SQL migration files in the `migrations/` directory:

```
migrations/
├── users.sql
├── posts.sql
└── comments.sql
```

### 3. Execute Migrations

You have several options for executing migrations:

#### Option A: Manual Execution

Use `psql` or your favorite PostgreSQL client:

```bash
psql -U postgres -d mydb -f migrations/users.sql
psql -U postgres -d mydb -f migrations/posts.sql
psql -U postgres -d mydb -f migrations/comments.sql
```

#### Option B: Programmatic Execution

Use the generated model's `createTable()` method:

```zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{ .host = "localhost", .port = 5432 },
        .auth = .{ .username = "postgres", .password = "password", .database = "mydb" },
    });
    defer pool.deinit();

    // Run migrations in order
    try models.User.createTable(&pool);
    try models.Post.createTable(&pool);
    try models.Comment.createTable(&pool);
}
```

#### Option C: Migration Runner Script

Create a dedicated migration script:

```zig
// src/migrate.zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read connection info from environment
    const db_url = std.process.getEnvVarOwned(
        allocator,
        "DATABASE_URL",
    ) catch "postgresql://postgres:password@localhost:5432/mydb";
    defer allocator.free(db_url);

    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{ .host = "localhost", .port = 5432 },
        .auth = .{ .username = "postgres", .password = "password", .database = "mydb" },
    });
    defer pool.deinit();

    std.debug.print("Running migrations...\n", .{});

    // Execute in dependency order
    inline for (.{
        models.User,
        models.Post,
        models.Comment,
    }) |Model| {
        const table_name = Model.tableName();
        std.debug.print("Creating table: {s}\n", .{table_name});
        try Model.createTable(&pool);
    }

    std.debug.print("Migrations complete!\n", .{});
}
```

Add to `build.zig`:

```zig
const migrate = b.addExecutable(.{
    .name = "migrate",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/migrate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "fluentorm", .module = fluentorm },
            .{ .name = "pg", .module = pg },
        },
    }),
});
b.installArtifact(migrate);

const migrate_step = b.step("migrate", "Run database migrations");
migrate_step.dependOn(&b.addRunArtifact(migrate).step);
```

Execute:

```bash
zig build migrate
```

## Generated SQL Structure

Each generated SQL file includes:

### 1. UUID Extension

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

Enables `gen_random_uuid()` for UUID generation.

### 2. Table Creation

```sql
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP
);
```

Includes all fields with proper types, constraints, and defaults.

### 3. Foreign Key Constraints

```sql
ALTER TABLE posts
ADD CONSTRAINT fk_post_author
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE CASCADE;
```

Enforces referential integrity between tables.

### 4. Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
```

## Schema Changes

When you modify a schema, FluentORM regenerates the SQL files. However, **existing migrations are not automatically altered**. You must handle schema changes manually.

### Adding a Field

1. Update your schema file:

```zig
// schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    // ... existing fields ...

    // New field
    t.string(.{
        .name = "phone",
        .not_null = false,
    });
}
```

2. Regenerate:

```bash
zig build generate
zig build generate-models
```

3. Create an ALTER TABLE migration:

```sql
-- migrations/001_add_phone_to_users.sql
ALTER TABLE users ADD COLUMN phone TEXT;
```

4. Execute:

```bash
psql -U postgres -d mydb -f migrations/001_add_phone_to_users.sql
```

### Renaming a Field

1. Update your schema with the new field name
2. Regenerate models
3. Create a migration:

```sql
-- migrations/002_rename_name_to_full_name.sql
ALTER TABLE users RENAME COLUMN name TO full_name;
```

### Removing a Field

1. Remove from schema
2. Regenerate models
3. Create a migration:

```sql
-- migrations/003_remove_phone_from_users.sql
ALTER TABLE users DROP COLUMN phone;
```

**Warning**: Dropping columns is destructive and cannot be undone.

## Migration Best Practices

### 1. Version Control

Commit all migration files to version control:

```bash
git add migrations/
git commit -m "Add users and posts migrations"
```

### 2. Sequential Numbering

Use a consistent numbering scheme for manual migrations:

```
migrations/
├── users.sql                  # Generated
├── posts.sql                  # Generated
├── 001_add_phone.sql         # Manual
├── 002_add_indexes.sql       # Manual
└── 003_alter_constraints.sql # Manual
```

### 3. Idempotent Migrations

Always use `IF NOT EXISTS` and `IF EXISTS` clauses:

```sql
CREATE TABLE IF NOT EXISTS users (...);
DROP TABLE IF EXISTS old_table;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
```

### 4. Backup Before Migrations

Always backup your database before running migrations:

```bash
pg_dump -U postgres mydb > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 5. Test in Development First

Never run untested migrations directly in production:

1. Test locally
2. Test in staging environment
3. Deploy to production

### 6. Rollback Plan

Create rollback migrations for destructive changes:

```sql
-- migrations/004_add_status.sql
ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active';

-- migrations/004_rollback_add_status.sql
ALTER TABLE users DROP COLUMN status;
```

## DDL Operations

FluentORM provides these DDL methods on all generated models:

### Create Table

```zig
try User.createTable(&pool);
```

Executes `CREATE TABLE IF NOT EXISTS ...`

### Create Indexes

```zig
try User.createIndexes(&pool);
```

Creates all indexes defined in the schema.

### Check Table Existence

```zig
const exists = try User.tableExists(&pool);
```

Returns `true` if the table exists.

### Drop Table

```zig
try User.dropTable(&pool);
```

Executes `DROP TABLE IF EXISTS users CASCADE`.

**Warning**: This permanently deletes all data.

### Truncate Table

```zig
try User.truncate(&pool);
```

Removes all rows but keeps the table structure.

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Database Migrations

on:
  push:
    branches: [main]

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup PostgreSQL
        uses: harmon758/postgresql-action@v1
        with:
          postgresql version: "14"
          postgresql db: "testdb"
          postgresql user: "postgres"
          postgresql password: "postgres"

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1

      - name: Run migrations
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/testdb
        run: |
          zig build migrate
```

## Troubleshooting

### Migration Fails: Constraint Violation

**Problem**: Foreign key or unique constraint fails.

**Solution**: Ensure tables are created in dependency order. Check the number prefix in schema filenames.

### Migration Fails: Column Already Exists

**Problem**: Trying to add a column that already exists.

**Solution**: Use `ADD COLUMN IF NOT EXISTS` in manual migrations.

### UUID Extension Error

**Problem**: `gen_random_uuid()` function not found.

**Solution**: Ensure the UUID extension is installed:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Connection Refused

**Problem**: Cannot connect to PostgreSQL.

**Solution**: Check connection settings, ensure PostgreSQL is running, and verify credentials.

## Next Steps

- See [SCHEMA.md](SCHEMA.md) for defining table schemas
- See [BASE_MODEL.md](BASE_MODEL.md) for using generated models
- See [RELATIONSHIPS.md](RELATIONSHIPS.md) for managing foreign keys
