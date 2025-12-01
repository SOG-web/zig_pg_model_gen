# Base Model

The base model provides common CRUD (Create, Read, Update, Delete) and DDL operations for all generated models.

## Overview

Every generated model automatically includes methods from the base model, providing a consistent interface for database operations. Models are generated from your schema definitions using the TableSchema builder API.

## Generated Structure

When you run `zig build generate-models`, FluentORM generates:

- **Model files** (e.g., `users.zig`, `posts.zig`) with CRUD operations
- **base.zig** - Common utilities and CRUD implementations
- **query.zig** - Query builder for type-safe filtering
- **transaction.zig** - Transaction support
- **root.zig** - Barrel export for easy imports

## CRUD Operations

### Create (Insert)

Insert a new record and get back the primary key:

```zig
const user_id = try User.insert(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);
```

**Note**: Fields marked with `.create_input = .excluded` (like auto-generated UUIDs and timestamps) are automatically excluded from the insert input struct.

#### Insert and Return Full Object

```zig
const user = try User.insertAndReturn(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user);
```

### Read (Query)

#### Find by ID

```zig
if (try User.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);
    std.debug.print("Found user: {s}\n", .{user.name});
}
```

Returns `null` if not found or if the record is soft-deleted.

#### Query with conditions

```zig
var query = User.query();
defer query.deinit();

const users = try query
    .where(.{ .field = .email, .operator = .eq, .value = "$1" })
    .fetch(&pool, allocator, .{"alice@example.com"});
defer allocator.free(users);
```

#### Fetch all records

```zig
const all_users = try User.findAll(&pool, allocator, false);
defer allocator.free(all_users);
```

To include soft-deleted records, pass `true`:

```zig
const all_including_deleted = try User.findAll(&pool, allocator, true);
defer allocator.free(all_including_deleted);
```

### Update

Update specific fields for a record:

```zig
try User.update(&pool, user_id, .{
    .name = "Alice Smith",
    .email = "alice.smith@example.com",
});
```

**Note**: Fields marked with `.update_input = false` (like `created_at`, auto-generated IDs) are excluded from the update input struct.

#### Update and Return

```zig
const updated_user = try User.updateAndReturn(&pool, allocator, user_id, .{
    .name = "Alice Smith",
});
defer allocator.free(updated_user);
```

### Upsert

Insert a record, or update if a unique constraint violation occurs:

```zig
const user_id = try User.upsert(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);
```

**Requirement**: Your schema must have at least one unique constraint (besides the primary key).

#### Upsert and Return

```zig
const user = try User.upsertAndReturn(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user);
```

### Delete

#### Soft Delete

If your schema includes a `deleted_at` field, you can use soft deletes:

```zig
try User.softDelete(&pool, user_id);
```

Soft-deleted records are automatically excluded from queries by default. Use `.withDeleted()` on queries to include them.

#### Hard Delete

Permanently removes the record:

```zig
try User.hardDelete(&pool, user_id);
```

**Warning**: This is irreversible and bypasses any soft-delete logic.

## DDL Operations

Base models provide Data Definition Language (DDL) operations for schema management.

### Create Table

Execute the generated `CREATE TABLE` SQL statement:

```zig
try User.createTable(&pool);
```

This creates the table with all fields, constraints, and indexes defined in your schema.

### Create Indexes

Create all indexes defined in the schema:

```zig
try User.createIndexes(&pool);
```

### Drop Table

Remove the table from the database:

```zig
try User.dropTable(&pool);
```

**Warning**: This is a destructive operation and will delete all data.

### Truncate Table

Remove all data but keep the table structure:

```zig
try User.truncate(&pool);
```

### Check Table Existence

```zig
const exists = try User.tableExists(&pool);
if (exists) {
    std.debug.print("Table exists\n", .{});
}
```

## Utility Operations

### Count Records

```zig
const total_users = try User.count(&pool, false);
std.debug.print("Total users: {d}\n", .{total_users});

// Include soft-deleted
const total_including_deleted = try User.count(&pool, true);
```

### Convert Row to Model

Helper to convert a `pg.zig` row result into a model instance:

```zig
const user = try User.fromRow(row, allocator);
```

### Get Table Name

```zig
const table_name = User.tableName();
std.debug.print("Table: {s}\n", .{table_name});
```

## JSON Response Helpers

Generated models include JSON-safe response types that convert UUIDs from byte arrays to strings:

```zig
const user = try User.findById(&pool, allocator, user_id);
defer allocator.free(user);

const json_response = try user.?.toResponse(allocator);
defer json_response.deinit(allocator);

// Serialize to JSON
try std.json.stringify(json_response, .{}, writer);
```

Fields marked with `.redacted = true` (like `password_hash`) are automatically excluded from JSON responses.

## Field Access

All model fields are accessible as struct members with proper Zig types:

```zig
std.debug.print("User: {s} ({s})\n", .{ user.name, user.email });
std.debug.print("Created at: {d}\n", .{user.created_at});
std.debug.print("Active: {}\n", .{user.is_active});
```

## Relationship Methods

If you've defined relationships in your schema using `t.foreign()`, the generator creates typed methods for fetching related records:

```zig
// One-to-many relationship (user has many posts)
const user_posts = try user.fetchPostAuthor(&pool, allocator);
defer allocator.free(user_posts);

// Many-to-one relationship (post belongs to user)
if (try post.fetchPostAuthor(&pool, allocator)) |author| {
    defer allocator.free(author);
    std.debug.print("Author: {s}\n", .{author.name});
}
```

See [RELATIONSHIPS.md](RELATIONSHIPS.md) for more details on defining and querying relationships.

## Type Safety

FluentORM generates compile-time type-safe code:

- Field names are enum values (autocompletion support)
- PostgreSQL types map to appropriate Zig types
- Optional fields use Zig optionals (`?T`)
- Input structs only include allowed fields based on schema configuration

## Error Handling

All database operations return errors that should be handled:

```zig
const user = User.findById(&pool, allocator, user_id) catch |err| {
    std.debug.print("Database error: {}\n", .{err});
    return err;
};
```

Common errors include:
- `error.QueryFailed` - SQL execution failed
- `error.OutOfMemory` - Allocation failed
- `error.ConnectionFailed` - Database connection issue
