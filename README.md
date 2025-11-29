# Zig Model Generator

A production-ready, standalone tool that generates type-safe Zig database models from JSON schema definitions. Built on top of `pg.zig`.

## 🚀 Features

- **Zero Boilerplate**: No manual model registration or build configuration required.
- **Type Safety**: Generates strictly typed Zig structs, including optional handling.
- **Self-Contained**: Bundles `base.zig` (BaseModel) with generated code, making models portable.
- **Advanced Schema**: Supports relationships, indexes, soft deletes, and custom input modes.
- **Full CRUD**: Auto-generates `insert`, `update`, `upsert`, `softDelete`, `hardDelete`, and more.
- **Query Builder**: Includes a fluent query builder for complex queries.
- **Runtime Validation**: Validates schemas for types, missing fields, and invalid structures before generation.

## 📦 Installation

### Option 1: Standalone Binary (CLI)

```bash
# Clone and install
git clone https://github.com/your/zig-model-gen
cd zig-model-gen
bash install.sh
```

### Option 2: Zig Package (build.zig.zon)

```zig
.dependencies = .{
    .model_gen = .{
        .url = "https://github.com/your/zig-model-gen/archive/<COMMIT_HASH>.tar.gz",
        .hash = "<PACKAGE_HASH>",
    },
    // Required for generated models
    .pg = .{
        .url = "https://github.com/karlseguin/pg.zig/archive/<COMMIT_HASH>.tar.gz",
        .hash = "...",
    },
},
```

## � Schema Reference

Create `.json` files in your schemas directory.

### Supported Types

| JSON Type   | Zig Type     | PostgreSQL Type | Note                   |
| ----------- | ------------ | --------------- | ---------------------- |
| `uuid`      | `[]const u8` | `uuid`          |                        |
| `text`      | `[]const u8` | `text`          |                        |
| `boolean`   | `bool`       | `boolean`       |                        |
| `i16`       | `i16`        | `smallint`      |                        |
| `i32`       | `i32`        | `integer`       |                        |
| `i64`       | `i64`        | `bigint`        |                        |
| `timestamp` | `i64`        | `timestamptz`   | Stored as milliseconds |
| `json`      | `[]const u8` | `jsonb`         | Raw JSON string        |

### Field Properties

| Property      | Type   | Default      | Description                             |
| ------------- | ------ | ------------ | --------------------------------------- |
| `name`        | string | **Required** | Column name                             |
| `type`        | string | **Required** | See Supported Types                     |
| `nullable`    | bool   | `false`      | If true, Zig type is optional (`?T`)    |
| `primary_key` | bool   | `false`      | Adds `PRIMARY KEY` constraint           |
| `unique`      | bool   | `false`      | Adds `UNIQUE` constraint                |
| `default`     | string | `null`       | SQL default value (e.g., `"now()"`)     |
| `input_mode`  | enum   | `"excluded"` | See Input Modes                         |
| `redacted`    | bool   | `false`      | Flags field for sensitive data handling |

### Input Modes

Controls how fields appear in `CreateInput` and `UpdateInput` structs.

- `required`: Must be provided in `CreateInput`.
- `optional`: Optional in `CreateInput` (defaults to null/default).
- `auto_generated`: Excluded from inputs (e.g., `id`, `created_at`).

### Relationships

Define foreign key relationships in the `relationships` array.

```json
"relationships": [
  {
    "name": "user",
    "column": "user_id",
    "references": {
      "table": "users",
      "column": "id"
    },
    "type": "many_to_one",
    "on_delete": "CASCADE",
    "on_update": "NO ACTION"
  }
]
```

- **Types**: `many_to_one` (default), `one_to_many`, `one_to_one`, `many_to_many`.
- **Actions**: `CASCADE`, `SET NULL`, `SET DEFAULT`, `RESTRICT`, `NO ACTION`.

### Indexes

Define database indexes in the `indexes` array.

```json
"indexes": [
  {
    "name": "users_email_idx",
    "columns": ["email"],
    "unique": true
  }
]
```

## 💻 Generated API Reference

Each generated model (e.g., `User`) includes the following static methods.

### Core CRUD

```zig
// Find by ID
const user = try User.findById(&pool, allocator, "uuid-string");

// Find All (supports soft delete filtering)
const users = try User.findAll(&pool, allocator, false); // false = hide deleted

// Insert
const id = try User.insert(&pool, allocator, .{
    .email = "test@example.com",
    .name = "Test User",
});

// Insert and Return Full Object
const user = try User.insertAndReturn(&pool, allocator, .{ ... });

// Update
try User.update(&pool, "uuid-string", .{
    .name = "Updated Name", // Optional fields
});

// Update and Return
const updated = try User.updateAndReturn(&pool, allocator, "uuid", .{ ... });

// Upsert (Insert or Update on conflict)
const id = try User.upsert(&pool, allocator, .{ ... });
```

### Deletion

```zig
// Soft Delete (requires 'deleted_at' field in schema)
try User.softDelete(&pool, "uuid-string");

// Hard Delete (permanent)
try User.hardDelete(&pool, "uuid-string");
```

### Query Builder

Fluent API for complex queries.

```zig
// Returns []UpdateInput (fields marked for update)
const results = try User.query()
    .where(.{
        .field = .age,
        .operator = .gt,
        .value = "$1",
    })
    .orderBy(.{
        .field = .created_at,
        .direction = .desc,
    })
    .limit(10)
    .fetch(&pool, allocator, .{18});
```

### DDL Operations

```zig
try User.createTable(&pool);
try User.createIndexes(&pool);
try User.dropTable(&pool);
try User.truncate(&pool);
const exists = try User.tableExists(&pool);
```

## 🔌 Integration

### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependency
    const model_gen = b.dependency("model_gen", .{});

    // Generation Step
    const gen_cmd = b.addRunArtifact(model_gen.artifact("zig-model-gen"));
    gen_cmd.addArg("schemas");      // Input
    gen_cmd.addArg("src/models");   // Output

    // Executable
    const exe = b.addExecutable(.{ ... });

    // Add pg dependency
    const pg = b.dependency("pg", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("pg", pg.module("pg"));

    // Ensure generation runs before build
    exe.step.dependOn(&gen_cmd.step);
}
```

## 📄 Example Schema

`schemas/user.json`:

```json
{
  "table_name": "users",
  "struct_name": "User",
  "fields": [
    {
      "name": "id",
      "type": "uuid",
      "nullable": false,
      "default": "gen_random_uuid()",
      "input_mode": "auto_generated",
      "primary_key": true
    },
    {
      "name": "email",
      "type": "text",
      "nullable": false,
      "input_mode": "required",
      "unique": true
    },
    {
      "name": "deleted_at",
      "type": "timestamp",
      "nullable": true,
      "input_mode": "auto_generated"
    }
  ]
}
```

## 📄 License

MIT
