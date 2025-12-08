# FluentORM

A schema-first, type-safe ORM for Zig with PostgreSQL support. Define your database schema using Zig's TableSchema builder API, automatically generate SQL migrations, and get type-safe model code with a fluent query builder.

## Features

- ✅ **Schema-First Design**: Define database schemas using Zig's type-safe TableSchema API
- ✅ **Automatic Code Generation**: Generate Zig models with full CRUD operations
- ✅ **SQL Migration Generation**: Auto-generate PostgreSQL CREATE TABLE statements
- 🚧 **Database Migrations**: Built-in migration runner with checksum verification and transactional execution (implemented but not fully tested)
- ✅ **Type-Safe Query Builder**: Fluent API for building SQL queries with compile-time field validation
- ✅ **Relationship Support**: Define and query relationships (one-to-many, many-to-one, one-to-one)
- ✅ **Transaction Support**: Built-in transaction handling with rollback on error
- ✅ **Soft Deletes**: Optional soft-delete functionality with `deleted_at` timestamps
- ✅ **JSON Response Helpers**: Auto-generate JSON-safe response types with UUID conversion

## Quick Links

📖 **[Getting Started Guide](docs/GETTING_STARTED.md)** - Complete tutorial for new users  
📚 **[Documentation](#documentation)** - In-depth guides for all features  
💡 **[Examples](test_proj/)** - Code examples and patterns

## Installation

### 1. Add FluentORM to your project

```bash
zig fetch --save git+https://github.com/SOG-web/fluentorm.zig#main
```

This adds FluentORM to your `build.zig.zon`:

```zig
.dependencies = .{
    .fluentorm = .{
        .url = "git+https://github.com/SOG-web/fluentorm.zig#main",
        .hash = "<hash>",
    },
},
```

### 2. Update your `build.zig`

Add the FluentORM dependency and build steps:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the fluentorm dependency
    const fluentorm_dep = b.dependency("fluentorm", .{
        .target = target,
        .optimize = optimize,
    });
    const fluentorm = fluentorm_dep.module("fluentorm");

    // Your main executable
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluentorm", .module = fluentorm },
            },
        }),
    });
    b.installArtifact(exe);

    // Step 1: Generate registry and runner from schemas
    const gen_step = b.step("generate", "Generate registry and runner from schemas");
    const gen_exe = fluentorm_dep.artifact("fluentzig-gen");
    const gen_cmd = b.addRunArtifact(gen_exe);
    gen_cmd.addArgs(&.{ "schemas", "src/models/generated" });
    gen_step.dependOn(&gen_cmd.step);

    // Step 2: Run the generated runner to create model files
    const runner_exe = b.addExecutable(.{
        .name = "model-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("schemas/runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluentorm", .module = fluentorm },
            },
        }),
    });
    const gen_models_step = b.step("generate-models", "Generate model files from schemas");
    gen_models_step.dependOn(&b.addRunArtifact(runner_exe).step);
}
```

## Quick Start

### 1. Create Schema Definitions

Create a `schemas/` directory and define your tables using the naming convention `XX_tablename.zig` (e.g., `01_users.zig`, `02_posts.zig`). The number prefix determines migration order.

**schemas/01_users.zig:**

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub fn build(t: *TableSchema) void {
    // Primary key - UUID auto-generated
    t.uuid(.{
        .name = "id",
        .primary_key = true,
        .unique = true,
        .create_input = .excluded,
        .update_input = false,
    });

    // User fields
    t.string(.{ .name = "email", .unique = true });
    t.string(.{ .name = "name" });
    t.string(.{ .name = "password_hash", .redacted = true });

    // Timestamps (adds created_at and updated_at)
    t.timestamps();

    // Soft delete support (adds deleted_at)
    t.softDelete();
}
```

**schemas/02_posts.zig:**

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub fn build(t: *TableSchema) void {
    t.uuid(.{
        .name = "id",
        .primary_key = true,
        .unique = true,
        .create_input = .excluded,
        .update_input = false,
    });

    t.string(.{ .name = "title" });
    t.string(.{ .name = "content" });
    t.uuid(.{ .name = "user_id" }); // Foreign key

    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // Define relationship using convenience method
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

### 2. Generate Models

Run the two-step generation process:

```bash
# Step 1: Generate registry and runner
zig build generate

# Step 2: Generate model files
zig build generate-models
```

This creates:

- `schemas/registry.zig` - Auto-imports all your schema files
- `schemas/runner.zig` - Runner that generates models
- `src/models/generated/users.zig` - User model with CRUD operations
- `src/models/generated/posts.zig` - Post model with CRUD operations
- `src/models/generated/base.zig` - Base model utilities
- `src/models/generated/query.zig` - Query builder
- `src/models/generated/transaction.zig` - Transaction support
- `src/models/generated/root.zig` - Barrel export file

### 3. Use Generated Models

```zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

const Users = models.Users;
const Posts = models.Posts;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup database connection
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = "localhost",
            .port = 5432,
        },
        .auth = .{
            .username = "postgres",
            .password = "password",
            .database = "mydb",
        },
    });
    defer pool.deinit();

    // Create a user
    const user_id = try Users.insert(&pool, allocator, .{
        .email = "alice@example.com",
        .name = "Alice",
        .password_hash = "hashed_password",
    });
    defer allocator.free(user_id);

    // Query users
    var query = Users.query();
    defer query.deinit();

    const users = try query
        .where(.{ .field = .email, .operator = .eq, .value = "$1" })
        .fetch(&pool, allocator, .{"alice@example.com"});
    defer allocator.free(users);

    // Get user with hasMany relationship
    if (try Users.findById(&pool, allocator, user_id)) |user| {
        defer allocator.free(user);

        // Fetch related posts using hasMany
        const posts = try user.fetchPosts(&pool, allocator);
        defer allocator.free(posts);
    }
}
```

## Documentation

- [📘 Getting Started](docs/GETTING_STARTED.md) - Complete tutorial for new users
- [📋 Schema Definition Guide](docs/SCHEMA.md) - Field types, constraints, and schema options
- [🔧 Base Model API](docs/BASE_MODEL.md) - CRUD operations and DDL methods
- [🔍 Query Builder](docs/QUERY.md) - Fluent query API documentation
- [🔗 Relationships](docs/RELATIONSHIPS.md) - Defining and querying relationships
- [💾 Transactions](docs/TRANSACTION.md) - Transaction support and usage
- [🚀 Migration Guide](docs/MIGRATIONS.md) - Database migration workflow

## Field Types

FluentORM supports these PostgreSQL field types:

| Method       | PostgreSQL Type | Zig Type     | Optional Variant     |
| ------------ | --------------- | ------------ | -------------------- |
| `uuid()`     | UUID            | `[]const u8` | `uuid_optional`      |
| `string()`   | TEXT            | `[]const u8` | `text_optional`      |
| `boolean()`  | BOOLEAN         | `bool`       | `bool_optional`      |
| `integer()`  | INT             | `i32`        | `i32_optional`       |
| `bigInt()`   | BIGINT          | `i64`        | `i64_optional`       |
| `float()`    | float4          | `f32`        | `f32_optional`       |
| `numeric()`  | numeric         | `f64`        | `f64_optional`       |
| `dateTime()` | TIMESTAMP       | `i64`        | `timestamp_optional` |
| `json()`     | JSON            | `[]const u8` | `json_optional`      |
| `jsonb()`    | JSONB           | `[]const u8` | `jsonb_optional`     |
| `binary()`   | bytea           | `[]const u8` | `binary_optional`    |

## Field Options

Common options for all field types:

```zig
.{
    .name = "field_name",              // Required: field name
    .primary_key = false,              // Is this a primary key?
    .unique = false,                   // Add unique constraint?
    .not_null = true,                  // Field is NOT NULL?
    .create_input = .required,         // .required, .optional, or .excluded
    .update_input = true,              // Include in UpdateInput?
    .redacted = false,                 // Exclude from JSON responses?
    .default_value = null,             // SQL default value
    .auto_generated = false,           // Auto-generated by database?
}
```

## Relationship Types

FluentORM provides convenience methods for defining relationships:

| Method           | Relationship | Description                                  |
| ---------------- | ------------ | -------------------------------------------- |
| `t.belongsTo()`  | Many-to-One  | This table has a FK to another table         |
| `t.hasOne()`     | One-to-One   | This table has a unique FK to another table  |
| `t.hasMany()`    | One-to-Many  | Another table has FKs pointing to this table |
| `t.manyToMany()` | Many-to-Many | Junction table relationship                  |
| `t.foreign()`    | Any          | Generic method with full control             |

```zig
// Post belongs to User
t.belongsTo(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .on_delete = .cascade,
});

// User has many Posts
t.hasMany(.{
    .name = "user_posts",
    .foreign_table = "posts",
    .foreign_column = "user_id",
});
```

## Requirements

- **Zig**: 0.15.1 or later
- **pg.zig**: Automatically included as a transitive dependency

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT

## Acknowledgments

- Built with [pg.zig](https://github.com/karlseguin/pg.zig) for PostgreSQL connectivity
