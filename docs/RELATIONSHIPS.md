# Relationships

This guide details how to define and use relationships between tables using FluentORM's TableSchema API.

## Overview

Relationships define how tables reference each other using foreign keys. FluentORM generates helper methods for navigating between related models, making it easy to fetch associated data.

## Defining Relationships

Use the `t.foreign()` method in your schema's `build()` function to define relationships:

```zig
pub fn build(t: *TableSchema) void {
    // ... other fields ...
    
    t.uuid(.{ .name = "user_id" }); // Foreign key column
    
    // Define the relationship
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

## Foreign Key Configuration

The `.foreign()` method accepts these options:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `name` | string | **Yes** | Unique name for the relationship (used in generated method names) |
| `column` | string | **Yes** | Column in the current table that holds the foreign key |
| `references_table` | string | **Yes** | Name of the target table |
| `references_column` | string | **Yes** | Column in the target table (usually `"id"`) |
| `relationship_type` | enum | **Yes** | Type of relationship (see below) |
| `on_delete` | enum | No | Action when referenced record is deleted (default: `.no_action`) |
| `on_update` | enum | No | Action when referenced record is updated (default: `.no_action`) |

## Relationship Types

### Many-to-One

The current table has a foreign key pointing to another table. This is the most common relationship type.

**Example**: Many posts belong to one user.

```zig
// In schemas/02_posts.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "title" });
    t.uuid(.{ .name = "user_id" }); // Foreign key
    
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

**Generated SQL**:
```sql
CONSTRAINT fk_post_author FOREIGN KEY (user_id)
REFERENCES users(id)
ON DELETE CASCADE
```

**Generated Method**:
```zig
// Fetch the user who authored this post
const author = try post.fetchPostAuthor(&pool, allocator);
defer allocator.free(author);
```

### One-to-Many

One record in the current table can be referenced by multiple records in another table. This is the inverse of many-to-one.

**Example**: One user has many posts.

```zig
// In schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "name" });
    
    // Note: The foreign key is in the posts table, not here
    // This is just metadata for code generation
    t.foreign(.{
        .name = "user_posts",
        .column = "id",
        .references_table = "posts",
        .references_column = "user_id",
        .relationship_type = .one_to_many,
    });
}
```

**Generated Method**:
```zig
// Fetch all posts by this user
const posts = try user.fetchUserPosts(&pool, allocator);
defer allocator.free(posts);
```

**Note**: For `one_to_many`, the `column` is your table's primary key, and `references_column` is the foreign key in the other table.

### One-to-One

A strict one-to-one mapping between two tables.

**Example**: One user has one profile.

```zig
// In schemas/02_profiles.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "user_id", .unique = true }); // Unique constraint enforces 1:1
    t.string(.{ .name = "bio" });
    
    t.foreign(.{
        .name = "profile_user",
        .column = "user_id",
        .references_table = "users",
        .references_column = "id",
        .relationship_type = .one_to_one,
        .on_delete = .cascade,
    });
}
```

**Generated Method**:
```zig
// Returns a single user or null
const user = try profile.fetchProfileUser(&pool, allocator);
defer if (user) |u| allocator.free(u);
```

### Many-to-Many

Many-to-many relationships require a junction (join) table. You must manually create the junction table and define two many-to-one relationships.

**Example**: Users can belong to multiple groups, and groups can have multiple users.

```zig
// Junction table: schemas/03_user_groups.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "user_id" });
    t.uuid(.{ .name = "group_id" });
    
    // First relationship: to users
    t.foreign(.{
        .name = "membership_user",
        .column = "user_id",
        .references_table = "users",
        .references_column = "id",
        .relationship_type = .many_to_one,
        .on_delete = .cascade,
    });
    
    // Second relationship: to groups
    t.foreign(.{
        .name = "membership_group",
        .column = "group_id",
        .references_table = "groups",
        .references_column = "id",
        .relationship_type = .many_to_one,
        .on_delete = .cascade,
    });
}
```

To query many-to-many relationships, you'll need to manually join through the junction table using the query builder.

## Referential Actions

Control what happens when a referenced record is deleted or updated:

| Action | Description |
|--------|-------------|
| `.cascade` | Delete/update dependent rows automatically |
| `.set_null` | Set the foreign key to NULL |
| `.set_default` | Set the foreign key to its default value |
| `.restrict` | Prevent the change if there are dependent rows |
| `.no_action` | Similar to RESTRICT, but checks are deferred (default) |

**Example with CASCADE**:
```zig
t.foreign(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .references_column = "id",
    .relationship_type = .many_to_one,
    .on_delete = .cascade, // Delete all posts when user is deleted
});
```

**Example with SET NULL**:
```zig
t.foreign(.{
    .name = "post_author",
    .column = "user_id",
    .references_table = "users",
    .references_column = "id",
    .relationship_type = .many_to_one,
    .on_delete = .set_null, // Set user_id to NULL when user is deleted
});

// Make sure the column is nullable!
t.uuid(.{ .name = "user_id", .not_null = false });
```

## Using Generated Relationship Methods

When you define a relationship, FluentORM generates a `fetch{RelationshipName}` method on your model.

### Example: Fetch Related Records

```zig
const std = @import("std");
const pg = @import("pg");
const models = @import("models/generated/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup database connection
    var pool = try pg.Pool.init(allocator, .{
        .size = 5,
        .connect = .{ .host = "localhost", .port = 5432 },
        .auth = .{ .username = "postgres", .password = "password", .database = "mydb" },
    });
    defer pool.deinit();

    // Fetch a post
    const post = (try models.Post.findById(&pool, allocator, post_id)).?;
    defer allocator.free(post);

    // Fetch the author using the generated relationship method
    if (try post.fetchPostAuthor(&pool, allocator)) |author| {
        defer allocator.free(author);
        std.debug.print("Post authored by: {s}\n", .{author.name});
    }

    // Fetch a user
    const user = (try models.User.findById(&pool, allocator, user_id)).?;
    defer allocator.free(user);

    // Fetch all posts by this user
    const user_posts = try user.fetchUserPosts(&pool, allocator);
    defer allocator.free(user_posts);
    
    for (user_posts) |p| {
        std.debug.print("Post: {s}\n", .{p.title});
    }
}
```

## Naming Conventions

The generated method name follows this pattern:

- **Pattern**: `fetch{RelationshipName}`
- **Example**: If `name = "post_author"`, the method is `fetchPostAuthor()`

Choose descriptive relationship names that reflect the domain relationship:

```zig
// Good names
.name = "post_author"      // fetchPostAuthor()
.name = "user_posts"       // fetchUserPosts()
.name = "order_customer"   // fetchOrderCustomer()

// Avoid generic names
.name = "relation1"        // fetchRelation1() (unclear)
```

## Complex Queries with Relationships

For more complex queries involving relationships, use the query builder:

```zig
// Find all posts by a specific user
var query = models.Post.query();
defer query.deinit();

const user_posts = try query
    .where(.{ .field = .user_id, .operator = .eq, .value = "$1" })
    .orderBy(.{ .field = .created_at, .direction = .desc })
    .fetch(&pool, allocator, .{user_id});
defer allocator.free(user_posts);
```

See [QUERY.md](QUERY.md) for more details on the query builder.

## Type Safety

All relationship methods are fully type-safe:

- Return types match the referenced model
- Relationship names are checked at compile time
- Foreign key types are validated

If you try to call a relationship method that doesn't exist, you'll get a compile-time error.
