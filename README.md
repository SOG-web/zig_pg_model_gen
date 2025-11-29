# Zig Model Generator

A production-ready, standalone tool that generates type-safe Zig database models from JSON schema definitions. Built on top of `pg.zig`.

> [!WARNING] > **Active Development**: This project is currently under active development.
> The **Query Builder** and **Transaction** features are currently **untested**. Please use them with caution and report any issues you encounter.

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

```bash
zig fetch --save "git+https://github.com/SOG-web/zig_pg_model_gen"
```

```zig
.dependencies = .{
    .model_gen = .{
        .url = "git+https://github.com/SOG-web/zig_pg_model_gen",
        .hash = "...", // TODO: Add hash
    },
    // Required for generated models
    .pg = .{
        .url = "git+https://github.com/karlseguin/pg.zig",
        .hash = "...", // TODO: Add hash
    },
},
```

## 📚 Documentation

Detailed documentation for generated components:

- **[Base Model API](docs/BASE_MODEL.md)**: CRUD, DDL, and utility methods.
- **[Query Builder](docs/QUERY.md)**: Fluent API for complex queries.
- **[Transactions](docs/TRANSACTION.md)**: Transaction support and usage.
- **[Relationships](docs/RELATIONSHIPS.md)**: Defining schema relationships.

## 📂 Examples

Check out the `examples/` directory for complete schema definitions:

- **[Auth User](examples/schemas/auth_user.json)**: A comprehensive user model with auth fields.
- **[Profile](examples/schemas/profile.json)**: One-to-one relationship with User.
- **[Post](examples/schemas/post.json)**: Many-to-one relationship (User -> Posts).
- **[Comment](examples/schemas/comment.json)**: Nested relationships (User -> Comment -> Post).
- **[Organization](examples/schemas/org.json)**: Organization model with one-to-many relationships.
- **[Organization User](examples/schemas/org_user.json)**: Junction model with foreign keys.

## 📖 Schema Reference

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

## 🔌 Integration

### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependency
    const model_gen = b.dependency("zig_pg_model_gen", .{});

    // Executable
    const exe = b.addExecutable(.{ ... });

    // Generation Step
    const gen_cmd = b.addRunArtifact(model_gen.artifact("zig-model-gen"));
    gen_cmd.addArg("schemas"); // Input
    gen_cmd.addArg("src/db/models/generated"); // Output

    const gen_step = b.step("gen", "Generate models");
    gen_step.dependOn(&gen_cmd.step);

    // Add pg dependency
    const pg = b.dependency("pg", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("pg", pg.module("pg"));

    // Ensure generation runs before build
    exe.step.dependOn(&gen_cmd.step);
}
```

### Usage

```bash
zig build gen
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

## 🤝 Contributing

Contributions are welcome! This project is under active development, and we appreciate any help in improving it.

- **Bug Reports**: Please open an issue if you encounter any problems, especially with the experimental Query Builder and Transaction features.
- **Pull Requests**: Feel free to submit PRs for bug fixes, new features, or documentation improvements.

## 📄 License

MIT
