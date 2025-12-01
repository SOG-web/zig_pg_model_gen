# Getting Started with FluentORM

A quick tutorial to get you up and running with FluentORM in minutes.

## Prerequisites

- Zig 0.15.1 or later
- PostgreSQL 12+ running locally or remotely
- Basic understanding of SQL and Zig

## Step 1: Create a New Project

```bash
mkdir my-app
cd my-app
zig init
```

## Step 2: Install FluentORM

Add FluentORM to your project:

```bash
zig fetch --save git+https://github.com/your-username/fluentorm#main
```

This updates `build.zig.zon`:

```zig
.dependencies = .{
    .fluentorm = .{
        .url = "git+https://github.com/your-username/fluentorm#<hash>",
        .hash = "<hash>",
    },
},
```

## Step 3: Configure build.zig

Replace the contents of `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get FluentORM dependency
    const fluentorm_dep = b.dependency("fluentorm", .{
        .target = target,
        .optimize = optimize,
    });
    const fluentorm = fluentorm_dep.module("fluentorm");

    // Main executable
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

    // Step 1: Generate registry and runner
    const gen_step = b.step("generate", "Generate registry and runner");
    const gen_exe = fluentorm_dep.artifact("fluentzig-gen");
    const gen_cmd = b.addRunArtifact(gen_exe);
    gen_cmd.addArgs(&.{ "schemas", "src/models/generated" });
    gen_step.dependOn(&gen_cmd.step);

    // Step 2: Generate models
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
    const gen_models_step = b.step("generate-models", "Generate models");
    gen_models_step.dependOn(&b.addRunArtifact(runner_exe).step);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

## Step 4: Create Your First Schema

Create `schemas/01_users.zig`:

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub fn build(t: *TableSchema) void {
    // Primary key
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

    // Soft deletes
    t.dateTime(.{
        .name = "deleted_at",
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
    });
}
```

## Step 5: Generate Models

Run the generation commands:

```bash
# Generate registry and runner
zig build generate

# Generate model files
zig build generate-models
```

This creates:

- `schemas/registry.zig` - Auto-imports your schemas
- `schemas/runner.zig` - Code generator runner
- `src/models/generated/users.zig` - User model
- `src/models/generated/base.zig` - Base CRUD operations
- `src/models/generated/query.zig` - Query builder
- `src/models/generated/transaction.zig` - Transaction support
- `src/models/generated/root.zig` - Barrel exports
- `migrations/users.sql` - SQL migration file

## Step 6: Set Up PostgreSQL

Create your database:

```bash
createdb my_app_db
```

Run the generated migration:

```bash
psql -U postgres -d my_app_db -f migrations/users.sql
```

Or use the programmatic approach (see step 7).

## Step 7: Write Your First Application

Update `src/main.zig`:

```zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Connect to PostgreSQL
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{
            .host = "localhost",
            .port = 5432,
        },
        .auth = .{
            .username = "postgres",
            .password = "your_password",
            .database = "my_app_db",
        },
    });
    defer pool.deinit();

    // Create the table (first time only)
    try models.User.createTable(&pool);
    std.debug.print("Table created successfully!\n", .{});

    // Insert a user
    const user_id = try models.User.insert(&pool, allocator, .{
        .email = "alice@example.com",
        .name = "Alice",
        .password_hash = "hashed_password_here",
    });
    defer allocator.free(user_id);
    std.debug.print("Created user with ID: {s}\n", .{user_id});

    // Find the user by ID
    if (try models.User.findById(&pool, allocator, user_id)) |user| {
        defer allocator.free(user);
        std.debug.print("Found user: {s} ({s})\n", .{ user.name, user.email });
    }

    // Query users
    var query = models.User.query();
    defer query.deinit();

    const users = try query
        .where(.{ .field = .email, .operator = .eq, .value = "$1" })
        .fetch(&pool, allocator, .{"alice@example.com"});
    defer allocator.free(users);

    std.debug.print("Found {d} user(s)\n", .{users.len});

    // Update the user
    try models.User.update(&pool, user_id, .{
        .name = "Alice Smith",
    });
    std.debug.print("User updated!\n", .{});

    // Delete the user (soft delete)
    try models.User.softDelete(&pool, user_id);
    std.debug.print("User soft deleted!\n", .{});
}
```

## Step 8: Run Your Application

```bash
zig build run
```

Expected output:

```
Table created successfully!
Created user with ID: 550e8400-e29b-41d4-a716-446655440000
Found user: Alice (alice@example.com)
Found 1 user(s)
User updated!
User soft deleted!
```

## What's Next?

### Add More Tables

Create `schemas/02_posts.zig`:

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
    t.uuid(.{ .name = "user_id" });

    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // Relationship: post belongs to user
    t.foreign(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .references_column = "id",
        .relationship_type = .many_to_one,
        .on_delete = .cascade,
    });
}
```

Regenerate:

```bash
zig build generate
zig build generate-models
```

Use the relationship:

```zig
const post = (try models.Post.findById(&pool, allocator, post_id)).?;
defer allocator.free(post);

// Fetch the author
if (try post.fetchPostAuthor(&pool, allocator)) |author| {
    defer allocator.free(author);
    std.debug.print("Post by: {s}\n", .{author.name});
}
```

### Explore Advanced Features

- **Complex Queries**: [QUERY.md](docs/QUERY.md)
- **Transactions**: [TRANSACTION.md](docs/TRANSACTION.md)
- **Relationships**: [RELATIONSHIPS.md](docs/RELATIONSHIPS.md)
- **Field Types**: [SCHEMA.md](docs/SCHEMA.md)
- **Migrations**: [MIGRATIONS.md](docs/MIGRATIONS.md)

## Common Issues

### Error: `gen_random_uuid()` not found

**Solution**: The migration should create the UUID extension automatically. If not, run:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Error: Cannot connect to database

**Solution**: Ensure PostgreSQL is running and credentials are correct:

```bash
psql -U postgres -d my_app_db
```

### Error: Table already exists

**Solution**: The ORM uses `CREATE TABLE IF NOT EXISTS`, but if you need to recreate:

```sql
DROP TABLE users CASCADE;
```

Then regenerate and run migrations again.

## Project Structure

After setup, your project should look like:

```
my-app/
├── build.zig
├── build.zig.zon
├── schemas/
│   ├── 01_users.zig
│   ├── 02_posts.zig
│   ├── registry.zig      # Auto-generated
│   └── runner.zig        # Auto-generated
├── src/
│   ├── main.zig
│   └── models/
│       └── generated/
│           ├── base.zig
│           ├── query.zig
│           ├── transaction.zig
│           ├── users.zig
│           ├── posts.zig
│           └── root.zig
└── migrations/
    ├── users.sql
    └── posts.sql
```

## Summary

You've now:

1. ✅ Installed FluentORM
2. ✅ Configured your build system
3. ✅ Created a schema with the TableSchema builder
4. ✅ Generated type-safe models
5. ✅ Connected to PostgreSQL
6. ✅ Performed CRUD operations

Happy coding with FluentORM! 🚀
