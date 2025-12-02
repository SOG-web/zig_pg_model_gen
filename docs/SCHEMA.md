# Schema Definition Guide

This guide explains how to define database schemas using FluentORM's TableSchema builder API.

## Overview

FluentORM uses a schema-first approach where you define your database structure using Zig's type-safe TableSchema API. The ORM then generates:

- SQL migration files
- Type-safe Zig model structs
- CRUD operations
- Query builders
- Relationship helpers

## File Structure and Naming

Schema files must be placed in a `schemas/` directory and follow the naming convention `XX_tablename.zig`:

```
schemas/
├── 01_users.zig       # Migration order 01, table name "users"
├── 02_posts.zig       # Migration order 02, table name "posts"
├── 03_comments.zig    # Migration order 03, table name "comments"
├── registry.zig       # Auto-generated: imports all schemas
└── runner.zig         # Auto-generated: runs model generator
```

The number prefix (`01_`, `02_`, etc.) determines the order of SQL migrations, ensuring tables are created in dependency order.

## Basic Schema Structure

Every schema file must export:

1. **`table_name`**: A constant string defining the database table name (used for schema merging)
2. **`build()`**: A function that accepts a `*TableSchema` and defines fields, constraints, and relationships

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Table name for schema merging - multiple schemas with same table_name will be merged
pub const table_name = "users";

/// Build function called by the registry generator
pub fn build(t: *TableSchema) void {
    // Define fields, constraints, and relationships here
}
```

### Schema Merging

Multiple schema files can define the same `table_name`. When this happens, FluentORM merges them into a single table definition. This is useful for:

- Organizing large tables across multiple files
- Adding relationships in separate files
- Extending base schemas with additional fields

```zig
// schemas/01_users.zig
pub const table_name = "users";
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "email" });
}

// schemas/02_users_relationships.zig
pub const table_name = "users";  // Same table_name - will be merged
pub fn build(t: *TableSchema) void {
    t.hasMany(.{
        .name = "user_posts",
        .foreign_table = "posts",
        .foreign_column = "user_id",
    });
}
```

## Field Types

FluentORM supports all major PostgreSQL data types:

### UUID Fields

```zig
t.uuid(.{
    .name = "id",
    .primary_key = true,
    .unique = true,
    .create_input = .excluded,
    .update_input = false,
});
```

**PostgreSQL**: `UUID`  
**Zig Type**: `[]const u8`  
**Default**: `gen_random_uuid()` for primary keys

### String Fields

```zig
t.string(.{
    .name = "email",
    .unique = true,
});
```

**PostgreSQL**: `TEXT`  
**Zig Type**: `[]const u8`

### Integer Fields

```zig
t.integer(.{
    .name = "age",
    .not_null = true,
});
```

**PostgreSQL**: `INT`  
**Zig Type**: `i32`

### Big Integer Fields

```zig
t.bigInt(.{
    .name = "view_count",
    .default_value = "0",
});
```

**PostgreSQL**: `BIGINT`  
**Zig Type**: `i64`

### Float Fields

```zig
t.float(.{
    .name = "rating",
});
```

**PostgreSQL**: `float4`  
**Zig Type**: `f32`

### Numeric Fields

```zig
t.numeric(.{
    .name = "price",
    .not_null = true,
});
```

**PostgreSQL**: `numeric`  
**Zig Type**: `f64`

### Boolean Fields

```zig
t.boolean(.{
    .name = "is_active",
    .default_value = "true",
});
```

**PostgreSQL**: `BOOLEAN`  
**Zig Type**: `bool`

### DateTime Fields

```zig
t.dateTime(.{
    .name = "created_at",
    .create_input = .excluded,
    .update_input = false,
    .default_value = "CURRENT_TIMESTAMP",
    .auto_generated = true,
});
```

**PostgreSQL**: `TIMESTAMP`  
**Zig Type**: `i64` (Unix timestamp)

### JSON Fields

```zig
t.json(.{
    .name = "metadata",
    .not_null = false,
});
```

**PostgreSQL**: `JSON`  
**Zig Type**: `[]const u8`

### JSONB Fields

```zig
t.jsonb(.{
    .name = "settings",
    .not_null = false,
});
```

**PostgreSQL**: `JSONB` (binary JSON, indexed)  
**Zig Type**: `[]const u8`

### Binary Fields

```zig
t.binary(.{
    .name = "file_data",
});
```

**PostgreSQL**: `bytea`  
**Zig Type**: `[]const u8`

## Field Options

All field types accept these common options:

```zig
.{
    .name = "field_name",              // Required: column name in database
    .primary_key = false,              // Mark as primary key
    .unique = false,                   // Add UNIQUE constraint
    .not_null = true,                  // NOT NULL constraint (default: true)
    .create_input = .required,         // Include in CreateInput (.required, .optional, .excluded)
    .update_input = true,              // Include in UpdateInput (true/false)
    .redacted = false,                 // Exclude from JSON responses (e.g., passwords)
    .default_value = null,             // SQL default value (e.g., "CURRENT_TIMESTAMP")
    .auto_generated = false,           // Auto-generated by database (e.g., timestamps)
}
```

### Create Input Control

The `.create_input` field controls whether a field appears in the generated `CreateInput` struct:

- `.required` - Must be provided when inserting (default for most fields)
- `.optional` - Can be provided, wrapped in Zig optional (`?T`)
- `.excluded` - Not allowed in insert (for auto-generated fields)

```zig
// Example: Auto-generated ID
t.uuid(.{
    .name = "id",
    .primary_key = true,
    .create_input = .excluded,  // User can't provide ID
});

// Example: Optional bio
t.string(.{
    .name = "bio",
    .not_null = false,
    .create_input = .optional,  // User may or may not provide bio
});

// Example: Required email
t.string(.{
    .name = "email",
    .create_input = .required,  // User must provide email
});
```

### Update Input Control

The `.update_input` field controls whether a field can be updated:

```zig
// Example: Timestamp that shouldn't be manually updated
t.dateTime(.{
    .name = "created_at",
    .update_input = false,  // Can't be changed after creation
});

// Example: Updatable name
t.string(.{
    .name = "name",
    .update_input = true,  // Can be updated
});
```

### Redacted Fields

Fields marked with `.redacted = true` are excluded from JSON response types:

```zig
t.string(.{
    .name = "password_hash",
    .redacted = true,  // Never sent in API responses
});
```

## Common Patterns

### Primary Key (UUID)

```zig
t.uuid(.{
    .name = "id",
    .primary_key = true,
    .unique = true,
    .create_input = .excluded,
    .update_input = false,
});
```

### Timestamps

```zig
// Created at - never updated
t.dateTime(.{
    .name = "created_at",
    .create_input = .excluded,
    .update_input = false,
    .default_value = "CURRENT_TIMESTAMP",
    .auto_generated = true,
});

// Updated at - automatically updated
t.dateTime(.{
    .name = "updated_at",
    .create_input = .excluded,
    .default_value = "CURRENT_TIMESTAMP",
    .auto_generated = true,
});
```

### Soft Deletes

```zig
t.dateTime(.{
    .name = "deleted_at",
    .not_null = false,
    .create_input = .excluded,
    .update_input = false,
});
```

### Foreign Keys and Relationships

See [RELATIONSHIPS.md](RELATIONSHIPS.md) for detailed relationship documentation.

FluentORM provides convenience methods for common relationship patterns:

```zig
// Many-to-One: This table has FK pointing to another table
t.uuid(.{ .name = "user_id" });
t.belongsTo(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .on_delete = .cascade,
});

// One-to-One: Unique FK relationship
t.uuid(.{ .name = "profile_id", .unique = true });
t.hasOne(.{
    .name = "user_profile",
    .column = "profile_id",
    .references_table = "profiles",
});

// One-to-Many: Other table has FKs to this table (metadata only)
t.hasMany(.{
    .name = "user_posts",
    .foreign_table = "posts",
    .foreign_column = "user_id",
});

// Many-to-Many: Junction table relationships
t.manyToMany(.{
    .name = "post_category",
    .column = "post_id",
    .references_table = "posts",
    .references_column = "id",
});
```

Or use the generic `foreign()` method for full control:

```zig
t.foreign(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .references_column = "id",
    .relationship_type = .many_to_one,
    .on_delete = .cascade,
});
```

## Adding Indexes with `addIndexes()`

Use `addIndexes()` to add database indexes for query performance optimization:

```zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "user_id" });
    t.dateTime(.{ .name = "created_at" });

    // Add indexes for common query patterns
    t.addIndexes(&.{
        .{
            .name = "idx_posts_user_created",
            .columns = &.{ "user_id", "created_at" },
            .unique = false,
        },
        .{
            .name = "idx_posts_user_id",
            .columns = &.{"user_id"},
            .unique = false,
        },
    });
}
```

### Index Options

| Option    | Type           | Description                              |
| --------- | -------------- | ---------------------------------------- |
| `name`    | `[]const u8`   | **Required**: Index name in database     |
| `columns` | `[][]const u8` | **Required**: Columns to include         |
| `unique`  | `bool`         | Create a UNIQUE index (default: `false`) |

### Generated SQL

```sql
CREATE INDEX idx_posts_user_created ON posts (user_id, created_at);
CREATE UNIQUE INDEX idx_posts_unique_email ON users (email);
```

### When to Add Indexes

- **Foreign key columns**: Speed up JOIN queries
- **Frequently filtered columns**: WHERE clauses benefit from indexes
- **Columns used in ORDER BY**: Improves sorting performance
- **Composite indexes**: For queries filtering on multiple columns together
- **Unique constraints**: Use `unique = true` to enforce uniqueness

> **Note**: Adding too many indexes can slow down INSERT/UPDATE operations. Only index columns that are frequently queried.

## Modifying Fields with `alterField()`

Use `alterField()` to modify properties of an existing field after it's been defined. This is useful for changing constraints, input modes, or other properties without redefining the entire field.

### Basic Usage

```zig
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

### `alterField()` Options

Only specify the properties you want to change; others retain their original values:

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

### When to Use `alterField()`

- **Changing constraints**: Make a field nullable, add unique constraint
- **Changing input modes**: Switch from `.required` to `.optional`
- **Adding redaction**: Mark a field as sensitive after the fact
- **Modifying defaults**: Change the SQL default value

> **Note**: `alterField()` modifies the field for code generation purposes. If your database already has data, you may need to run corresponding `ALTER TABLE` statements to sync the database schema.

## Complete Example

Here's a complete schema for a `users` table:

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Table name for schema merging
pub const table_name = "users";

pub fn build(t: *TableSchema) void {
    // Primary key
    t.uuid(.{
        .name = "id",
        .primary_key = true,
        .unique = true,
        .create_input = .excluded,
        .update_input = false,
    });

    // Required fields
    t.string(.{ .name = "email", .unique = true });
    t.string(.{ .name = "name" });
    t.string(.{ .name = "password_hash", .redacted = true });

    // Optional fields
    t.string(.{
        .name = "bio",
        .not_null = false,
        .create_input = .optional,
    });

    // Boolean with default
    t.boolean(.{
        .name = "is_active",
        .default_value = "true",
    });

    // Integer field
    t.integer(.{
        .name = "login_count",
        .default_value = "0",
    });

    // Timestamps
    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    t.dateTime(.{
        .name = "updated_at",
        .create_input = .excluded,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // Soft delete support
    t.dateTime(.{
        .name = "deleted_at",
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
    });
}
```

## Generated Code

From the schema above, FluentORM generates:

### SQL Migration

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    bio TEXT,
    is_active BOOLEAN DEFAULT true NOT NULL,
    login_count INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP
);
```

### Zig Model

```zig
pub const Users = struct {
    id: []const u8,
    email: []const u8,
    name: []const u8,
    password_hash: []const u8,
    bio: ?[]const u8,
    is_active: bool,
    login_count: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,

    // CRUD methods: insert, findById, findAll, update, softDelete, hardDelete, etc.
    // Query builder: query()
    // DDL methods: truncate, tableExists
    // JSON helpers: toJsonResponse, toJsonResponseSafe
};
```

### CreateInput Struct

```zig
pub const CreateInput = struct {
    email: []const u8,
    name: []const u8,
    password_hash: []const u8,
    bio: ?[]const u8,  // Optional
    // id, created_at, updated_at, deleted_at excluded
};
```

### UpdateInput Struct

```zig
pub const UpdateInput = struct {
    email: ?[]const u8,
    name: ?[]const u8,
    password_hash: ?[]const u8,
    bio: ?[]const u8,
    is_active: ?bool,
    login_count: ?i32,
    updated_at: ?i64,
    // id, created_at excluded
};
```

## Type Mapping

| TableSchema Method | PostgreSQL | Zig Type     | Zig Optional  |
| ------------------ | ---------- | ------------ | ------------- |
| `uuid()`           | UUID       | `[]const u8` | `?[]const u8` |
| `string()`         | TEXT       | `[]const u8` | `?[]const u8` |
| `integer()`        | INT        | `i32`        | `?i32`        |
| `bigInt()`         | BIGINT     | `i64`        | `?i64`        |
| `float()`          | float4     | `f32`        | `?f32`        |
| `numeric()`        | numeric    | `f64`        | `?f64`        |
| `boolean()`        | BOOLEAN    | `bool`       | `?bool`       |
| `dateTime()`       | TIMESTAMP  | `i64`        | `?i64`        |
| `json()`           | JSON       | `[]const u8` | `?[]const u8` |
| `jsonb()`          | JSONB      | `[]const u8` | `?[]const u8` |
| `binary()`         | bytea      | `[]const u8` | `?[]const u8` |

## Best Practices

1. **Use descriptive field names**: `email` not `e`, `created_at` not `ca`
2. **Follow naming conventions**: Use the `XX_tablename.zig` pattern
3. **Always include timestamps**: `created_at`, `updated_at` for audit trails
4. **Use soft deletes**: Add `deleted_at` for data recovery options
5. **Mark sensitive fields as redacted**: Passwords, tokens, etc.
6. **Set appropriate defaults**: Use `default_value` for boolean flags, counters
7. **Define relationships**: Use `t.foreign()` to create foreign key constraints
8. **Order schemas by dependency**: Create referenced tables first (01*, 02*, etc.)

## Next Steps

- See [RELATIONSHIPS.md](RELATIONSHIPS.md) for defining table relationships
- See [BASE_MODEL.md](BASE_MODEL.md) for using generated CRUD operations
- See [QUERY.md](QUERY.md) for building complex queries
- See [TRANSACTION.md](TRANSACTION.md) for transaction support
