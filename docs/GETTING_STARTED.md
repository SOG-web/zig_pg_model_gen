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
zig fetch --save git+https://github.com/SOG-web/fluentorm#main
```

This updates `build.zig.zon`:

```zig
.dependencies = .{
    .fluentorm = .{
        .url = "git+https://github.com/SOG-web/fluentorm#<hash>",
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

    // Migration directory option (customizable)
    const migrations_dir = b.option([]const u8, "migrations-dir", "Directory containing migration files") orelse "migrations";

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
    gen_cmd.addArgs(&.{ "schemas", "src/models/generated", migrations_dir });
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

    // Migration steps
    const migrate_exe = fluentorm_dep.artifact("fluent-migrate");

    // migrate-up: Run pending migrations
    const migrate_up_cmd = b.addRunArtifact(migrate_exe);
    migrate_up_cmd.addArgs(&.{ "--migrations-dir", migrations_dir, "up" });
    const migrate_up_step = b.step("migrate-up", "Run pending database migrations");
    migrate_up_step.dependOn(&migrate_up_cmd.step);

    // migrate-status: Show migration status
    const migrate_status_cmd = b.addRunArtifact(migrate_exe);
    migrate_status_cmd.addArgs(&.{ "--migrations-dir", migrations_dir, "status" });
    const migrate_status_step = b.step("migrate-status", "Show database migration status");
    migrate_status_step.dependOn(&migrate_status_cmd.step);

    // migrate-down: Rollback last migration
    const migrate_down_cmd = b.addRunArtifact(migrate_exe);
    migrate_down_cmd.addArgs(&.{ "--migrations-dir", migrations_dir, "down" });
    const migrate_down_step = b.step("migrate-down", "Rollback last database migration");
    migrate_down_step.dependOn(&migrate_down_cmd.step);

    // Default migrate step (alias)
    const migrate_step = b.step("migrate", "Run database migrations");
    migrate_step.dependOn(&migrate_up_cmd.step);

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

    // User fields
    t.string(.{ .name = "email", .unique = true });
    t.string(.{ .name = "name" });
    t.string(.{ .name = "password_hash", .redacted = true });

    // Timestamps (adds created_at and updated_at)
    t.timestamps();

    // Soft deletes (adds deleted_at)
    t.softDelete();
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

## Step 6: Set Up Database and Run Migrations

Create your database and set environment variables:

```bash
createdb my_app_db

export FLUENT_DB_HOST=localhost
export FLUENT_DB_PORT=5432
export FLUENT_DB_NAME=my_app_db
export FLUENT_DB_USER=postgres
export FLUENT_DB_PASSWORD=your_password
```

Run the migrations using the built-in migration system:

```bash
# Run all pending migrations
zig build migrate

# Check migration status
zig build migrate-status

# Rollback if needed
zig build migrate-down
```

The migration system will:

- Create the necessary database tables
- Track applied migrations in a `_fluent_migrations` table
- Verify migration checksums for safety
- Run migrations in transactions

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

    // Insert a user
    const user_id = try models.Users.insert(&pool, allocator, .{
        .email = "alice@example.com",
        .name = "Alice",
        .password_hash = "hashed_password_here",
    });
    defer allocator.free(user_id);
    std.debug.print("Created user with ID: {s}\n", .{user_id});

    // Find the user by ID
    if (try models.Users.findById(&pool, allocator, user_id)) |user| {
        std.debug.print("Found user: {s} ({s})\n", .{ user.name, user.email });
    }

    // Query users
    var query = models.Users.query();
    defer query.deinit();

    const users = try query
        .where(.{ .field = .email, .operator = .eq, .value = "$1" })
        .fetch(&pool, allocator, .{"alice@example.com"});
    defer allocator.free(users);

    std.debug.print("Found {d} user(s)\n", .{users.len});

    // Update the user
    try models.Users.update(&pool, user_id, .{
        .name = "Alice Smith",
    });
    std.debug.print("User updated!\n", .{});

    // Delete the user (soft delete)
    try models.Users.softDelete(&pool, user_id);
    std.debug.print("User soft deleted!\n", .{});
}
```

## Step 8: Run Your Application

```bash
zig build run
```

Expected output:

```
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
pub const table_name = "posts";
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

    // Timestamps (adds created_at and updated_at)
    t.timestamps();

    // Relationship: post belongs to user
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

And update `schemas/01_users.zig` to add hasMany:

```zig
const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

pub const table_name = "users";

pub fn build(t: *TableSchema) void {
    // ... existing fields ...

    // One-to-many: User has many posts
    t.hasMany(.{
        .name = "user_posts",
        .foreign_table = "posts",
        .foreign_column = "user_id",
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
// Using hasMany on Users
const user = (try models.Users.findById(&pool, allocator, user_id)).?;
defer allocator.free(user);

// Fetch all posts by this user
const posts = try user.fetchPosts(&pool, allocator);
defer allocator.free(posts);

for (posts) |p| {
    std.debug.print("Post: {s}\n", .{p.title});
}

// Using belongsTo on Posts
const post = (try models.Posts.findById(&pool, allocator, post_id)).?;
defer allocator.free(post);

// Fetch the author
if (try post.fetchPostAuthor(&pool, allocator)) |author| {
    defer allocator.free(author);
    std.debug.print("Post by: {s}\n", .{author.name});
}
```

### Explore Advanced Features

- **Complex Queries**: [QUERY.md](QUERY.md)
- **Transactions**: [TRANSACTION.md](TRANSACTION.md)
- **Relationships**: [RELATIONSHIPS.md](RELATIONSHIPS.md)
- **Field Types**: [SCHEMA.md](SCHEMA.md)
- **Migrations**: [MIGRATIONS.md](MIGRATIONS.md)

## Common Issues

## Common Issues

### Error: `gen_random_uuid()` not found

**Solution**: The migration system automatically creates the UUID extension. If it fails, ensure your database user has the necessary permissions.

### Error: Cannot connect to database

**Solution**: Ensure PostgreSQL is running and environment variables are set correctly:

```bash
# Test connection
psql -U $FLUENT_DB_USER -d $FLUENT_DB_NAME -h $FLUENT_DB_HOST -p $FLUENT_DB_PORT
```

### Error: Migration checksum mismatch

**Solution**: Never modify migration files after they've been applied. If you need to change something, create a new migration.

### Error: Table already exists

**Solution**: Check migration status and only run pending migrations:

```bash
zig build migrate-status
zig build migrate
```

### Error: Foreign key constraint fails

**Solution**: Ensure schema files are numbered correctly for dependency order (e.g., `01_users.zig` before `02_posts.zig`).

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
├── migrations/           # Migration files
│   ├── 1764673549_create_users.sql
│   ├── 1764673549_create_users_down.sql
│   └── ...
└── zig-out/
    └── bin/
        └── fluent-migrate  # Migration runner
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
