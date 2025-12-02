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
const user_id = try Users.insert(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);
```

**Note**: Fields marked with `.create_input = .excluded` (like auto-generated UUIDs and timestamps) are automatically excluded from the insert input struct.

#### Insert and Return Full Object

```zig
const user = try Users.insertAndReturn(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user);
```

### Read (Query)

#### Find by ID

```zig
if (try Users.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);
    std.debug.print("Found user: {s}\n", .{user.name});
}
```

Returns `null` if not found or if the record is soft-deleted.

#### Query with conditions

```zig
var query = Users.query();
defer query.deinit();

const users = try query
    .where(.{ .field = .email, .operator = .eq, .value = "$1" })
    .fetch(&pool, allocator, .{"alice@example.com"});
defer allocator.free(users);
```

#### Fetch all records

```zig
const all_users = try Users.findAll(&pool, allocator, false);
defer allocator.free(all_users);
```

To include soft-deleted records, pass `true`:

```zig
const all_including_deleted = try Users.findAll(&pool, allocator, true);
defer allocator.free(all_including_deleted);
```

### Update

Update specific fields for a record:

```zig
try Users.update(&pool, user_id, .{
    .name = "Alice Smith",
    .email = "alice.smith@example.com",
});
```

**Note**: Fields marked with `.update_input = false` (like `created_at`, auto-generated IDs) are excluded from the update input struct.

#### Update and Return

```zig
const updated_user = try Users.updateAndReturn(&pool, allocator, user_id, .{
    .name = "Alice Smith",
});
defer allocator.free(updated_user);
```

### Upsert

Insert a record, or update if a unique constraint violation occurs:

```zig
const user_id = try Users.upsert(&pool, allocator, .{
    .email = "alice@example.com",
    .name = "Alice",
    .password_hash = "hashed_password",
});
defer allocator.free(user_id);
```

**Requirement**: Your schema must have at least one unique constraint (besides the primary key).

#### Upsert and Return

```zig
const user = try Users.upsertAndReturn(&pool, allocator, .{
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
try Users.softDelete(&pool, user_id);
```

Soft-deleted records are automatically excluded from queries by default. Use `.withDeleted()` on queries to include them.

#### Hard Delete

Permanently removes the record:

```zig
try Users.hardDelete(&pool, user_id);
```

**Warning**: This is irreversible and bypasses any soft-delete logic.

## DDL Operations

Base models provide limited Data Definition Language (DDL) operations.

### Truncate Table

Remove all data but keep the table structure:

```zig
try Users.truncate(&pool);
```

**Warning**: This permanently deletes all data in the table.

### Check Table Existence

```zig
const exists = try Users.tableExists(&pool);
if (exists) {
    std.debug.print("Table exists\n", .{});
}
```

> **Note**: `createTable()`, `dropTable()`, and `createIndexes()` methods are not currently available. Use the generated SQL migration files to create/drop tables. See [MIGRATIONS.md](MIGRATIONS.md) for details.

## Utility Operations

### Count Records

```zig
const total_users = try Users.count(&pool, false);
std.debug.print("Total users: {d}\n", .{total_users});

// Include soft-deleted
const total_including_deleted = try Users.count(&pool, true);
```

### Convert Row to Model

Helper to convert a `pg.zig` row result into a model instance:

```zig
const user = try Users.fromRow(row, allocator);
```

### Get Table Name

```zig
const table_name = Users.tableName();
std.debug.print("Table: {s}\n", .{table_name});
```

## JSON Response Helpers

Generated models include JSON-safe response types that convert UUIDs from byte arrays to hex strings:

### JsonResponse

Includes all fields:

```zig
if (try Users.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);

    const json_response = try user.toJsonResponse();
    // json_response.id is now a [36]u8 hex string like "550e8400-e29b-41d4-a716-446655440000"
}
```

### JsonResponseSafe

Excludes fields marked with `.redacted = true` (like `password_hash`):

```zig
if (try Users.findById(&pool, allocator, user_id)) |user| {
    defer allocator.free(user);

    const safe_response = try user.toJsonResponseSafe();
    // password_hash is NOT included in this response
}
```

## Field Access

All model fields are accessible as struct members with proper Zig types:

```zig
std.debug.print("User: {s} ({s})\n", .{ user.name, user.email });
std.debug.print("Created at: {d}\n", .{user.created_at});
std.debug.print("Active: {}\n", .{user.is_active});
```

## Relationship Methods

If you've defined relationships in your schema, the generator creates typed methods for fetching related records.

### BelongsTo / HasOne (Many-to-One, One-to-One)

```zig
// Post belongs to User
if (try post.fetchPostAuthor(&pool, allocator)) |author| {
    defer allocator.free(author);
    std.debug.print("Author: {s}\n", .{author.name});
}

// Profile has one User
if (try profile.fetchProfileUser(&pool, allocator)) |user| {
    defer allocator.free(user);
    std.debug.print("User: {s}\n", .{user.name});
}
```

### HasMany (One-to-Many)

```zig
// User has many Posts (defined with t.hasMany())
const user_posts = try user.fetchPosts(&pool, allocator);
defer allocator.free(user_posts);

for (user_posts) |p| {
    std.debug.print("Post: {s}\n", .{p.title});
}

// User has many Comments
const user_comments = try user.fetchComments(&pool, allocator);
defer allocator.free(user_comments);
```

### Self-Referential Relationships

```zig
// Comment has parent comment (self-reference)
if (try comment.fetchParent(&pool, allocator)) |parent| {
    defer allocator.free(parent);
    std.debug.print("Reply to: {s}\n", .{parent.content});
}

// Comment has many replies (self-referential hasMany)
const replies = try comment.fetchReplies(&pool, allocator);
defer allocator.free(replies);
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
