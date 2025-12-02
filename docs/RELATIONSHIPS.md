# Relationships

This guide details how to define and use relationships between tables using FluentORM's TableSchema API.

## Overview

Relationships define how tables reference each other using foreign keys. FluentORM generates helper methods for navigating between related models, making it easy to fetch associated data.

## Defining Relationships

FluentORM provides **convenience methods** for common relationship types, plus the generic `t.foreign()` method for advanced use cases.

### Quick Reference

| Relationship | Method           | Description                                              |
| ------------ | ---------------- | -------------------------------------------------------- |
| Many-to-One  | `t.belongsTo()`  | This table has a FK to another table (e.g., post → user) |
| One-to-One   | `t.hasOne()`     | This table has a unique FK to another table              |
| One-to-Many  | `t.hasMany()`    | Another table has FKs pointing to this table             |
| Many-to-Many | `t.manyToMany()` | Junction table relationship                              |
| Generic      | `t.foreign()`    | Low-level method with full control                       |

### Using Convenience Methods

```zig
pub fn build(t: *TableSchema) void {
    // ... other fields ...

    t.uuid(.{ .name = "user_id" }); // Foreign key column

    // Define the relationship using convenience method
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
```

### Using the Generic Foreign Method

```zig
pub fn build(t: *TableSchema) void {
    // ... other fields ...

    t.uuid(.{ .name = "user_id" }); // Foreign key column

    // Define the relationship using generic method
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

| Property            | Type   | Required | Description                                                       |
| ------------------- | ------ | -------- | ----------------------------------------------------------------- |
| `name`              | string | **Yes**  | Unique name for the relationship (used in generated method names) |
| `column`            | string | **Yes**  | Column in the current table that holds the foreign key            |
| `references_table`  | string | **Yes**  | Name of the target table                                          |
| `references_column` | string | **Yes**  | Column in the target table (usually `"id"`)                       |
| `relationship_type` | enum   | **Yes**  | Type of relationship (see below)                                  |
| `on_delete`         | enum   | No       | Action when referenced record is deleted (default: `.no_action`)  |
| `on_update`         | enum   | No       | Action when referenced record is updated (default: `.no_action`)  |

## Relationship Types

### Many-to-One (belongsTo)

The current table has a foreign key pointing to another table. This is the most common relationship type.

**Example**: Many posts belong to one user.

```zig
// In schemas/02_posts.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "title" });
    t.uuid(.{ .name = "user_id" }); // Foreign key

    // Using convenience method (recommended)
    t.belongsTo(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });

    // Or using generic foreign() method
    // t.foreign(.{
    //     .name = "post_author",
    //     .column = "user_id",
    //     .references_table = "users",
    //     .references_column = "id",
    //     .relationship_type = .many_to_one,
    //     .on_delete = .cascade,
    // });
}
```

**belongsTo Options**:

| Option              | Type   | Default      | Description                              |
| ------------------- | ------ | ------------ | ---------------------------------------- |
| `name`              | string | **required** | Relationship name (used in method names) |
| `column`            | string | **required** | FK column in this table                  |
| `references_table`  | string | **required** | Target table name                        |
| `references_column` | string | `"id"`       | Target column (usually PK)               |
| `on_delete`         | enum   | `.no_action` | Action on parent delete                  |
| `on_update`         | enum   | `.no_action` | Action on parent update                  |

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

### One-to-Many (hasMany)

One record in the current table can be referenced by multiple records in another table. Use the `hasMany()` method to define this relationship.

**Example**: One user has many posts.

```zig
// In schemas/01_users.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.string(.{ .name = "name" });

    // Define one-to-many relationship using hasMany()
    // Note: The FK constraint is in the posts table, not here
    // This is metadata for generating fetch methods
    t.hasMany(.{
        .name = "user_posts",
        .foreign_table = "posts",
        .foreign_column = "user_id",
    });

    // You can define multiple hasMany relationships
    t.hasMany(.{
        .name = "user_comments",
        .foreign_table = "comments",
        .foreign_column = "user_id",
    });
}
```

**Generated Methods**:

```zig
// Fetch all posts by this user
const posts = try user.fetchPosts(&pool, allocator);
defer allocator.free(posts);

// Fetch all comments by this user
const comments = try user.fetchComments(&pool, allocator);
defer allocator.free(comments);
```

**hasMany Options**:

| Option           | Type   | Description                                        |
| ---------------- | ------ | -------------------------------------------------- |
| `name`           | string | Relationship name (used to generate method suffix) |
| `foreign_table`  | string | The child table that has the FK                    |
| `foreign_column` | string | The FK column in the child table                   |

**Note**: `hasMany()` does not create a FK constraint. The FK constraint should be defined in the child table using `belongsTo()` or `foreign()`.

#### Define Multiple hasMany at Once

```zig
t.hasManyList(&.{
    .{ .name = "user_posts", .foreign_table = "posts", .foreign_column = "user_id" },
    .{ .name = "user_comments", .foreign_table = "comments", .foreign_column = "user_id" },
});
```

### One-to-One (hasOne)

A strict one-to-one mapping between two tables.

**Example**: One user has one profile.

```zig
// In schemas/02_profiles.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "user_id", .unique = true }); // Unique constraint enforces 1:1
    t.string(.{ .name = "bio" });

    // Using convenience method (recommended)
    t.hasOne(.{
        .name = "profile_user",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });

    // Or using generic foreign() method
    // t.foreign(.{
    //     .name = "profile_user",
    //     .column = "user_id",
    //     .references_table = "users",
    //     .references_column = "id",
    //     .relationship_type = .one_to_one,
    //     .on_delete = .cascade,
    // });
}
```

**Generated Method**:

```zig
// Returns a single user or null
const user = try profile.fetchProfileUser(&pool, allocator);
defer if (user) |u| allocator.free(u);
```

**hasOne Options**:

| Option              | Type   | Default      | Description             |
| ------------------- | ------ | ------------ | ----------------------- |
| `name`              | string | **required** | Relationship name       |
| `column`            | string | **required** | FK column in this table |
| `references_table`  | string | **required** | Target table name       |
| `references_column` | string | `"id"`       | Target column           |
| `on_delete`         | enum   | `.no_action` | Action on parent delete |
| `on_update`         | enum   | `.no_action` | Action on parent update |

### Many-to-Many (manyToMany)

Many-to-many relationships require a junction (join) table. Use `manyToMany()` to define the relationship on the junction table, or use `belongsTo()` for each side.

**Example**: Posts can have multiple categories, and categories can have multiple posts.

```zig
// Junction table: schemas/05_post_categories.zig
pub fn build(t: *TableSchema) void {
    t.uuid(.{ .name = "id", .primary_key = true });
    t.uuid(.{ .name = "post_id" });
    t.uuid(.{ .name = "category_id" });

    // Using manyToMany convenience method
    t.manyToMany(.{
        .name = "post_category_post",
        .column = "post_id",
        .references_table = "posts",
        .references_column = "id",
    });

    t.manyToMany(.{
        .name = "post_category_category",
        .column = "category_id",
        .references_table = "categories",
        .references_column = "id",
    });

    // Or using belongsTo (equivalent)
    // t.belongsTo(.{
    //     .name = "post_category_post",
    //     .column = "post_id",
    //     .references_table = "posts",
    //     .on_delete = .cascade,
    // });
}
```

**manyToMany Options**:

| Option              | Type   | Default      | Description                 |
| ------------------- | ------ | ------------ | --------------------------- |
| `name`              | string | **required** | Relationship name           |
| `column`            | string | **required** | FK column in junction table |
| `references_table`  | string | **required** | Target table name           |
| `references_column` | string | **required** | Target column               |
| `on_delete`         | enum   | `.cascade`   | Action on parent delete     |
| `on_update`         | enum   | `.no_action` | Action on parent update     |

To query many-to-many relationships, you'll need to join through the junction table using the query builder.

```zig
// Get all categories for a post
var query = PostCategory.query();
defer query.deinit();

const post_cats = try query
    .where(.{ .field = .post_id, .operator = .eq, .value = "$1" })
    .fetch(&pool, allocator, .{post_id});
defer allocator.free(post_cats);

for (post_cats) |pc| {
    if (try pc.fetchPostCategoryCategory(&pool, allocator)) |cat| {
        defer allocator.free(cat);
        std.debug.print("Category: {s}\n", .{cat.name});
    }
}
```

## Referential Actions

Control what happens when a referenced record is deleted or updated:

| Action         | Description                                            |
| -------------- | ------------------------------------------------------ |
| `.cascade`     | Delete/update dependent rows automatically             |
| `.set_null`    | Set the foreign key to NULL                            |
| `.set_default` | Set the foreign key to its default value               |
| `.restrict`    | Prevent the change if there are dependent rows         |
| `.no_action`   | Similar to RESTRICT, but checks are deferred (default) |

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

When you define a relationship, FluentORM generates `fetch*` methods on your model.

### Method Naming

| Definition                                      | Generated Method      | Return Type    |
| ----------------------------------------------- | --------------------- | -------------- |
| `belongsTo(.{ .name = "post_author", ... })`    | `fetchPostAuthor()`   | `!?Users`      |
| `hasOne(.{ .name = "profile_user", ... })`      | `fetchProfileUser()`  | `!?Users`      |
| `hasMany(.{ .name = "user_posts", ... })`       | `fetchPosts()`        | `![]Posts`     |
| `manyToMany(.{ .name = "post_category", ... })` | `fetchPostCategory()` | `!?Categories` |

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
    const post = (try models.Posts.findById(&pool, allocator, post_id)).?;
    defer allocator.free(post);

    // Fetch the author using belongsTo relationship
    if (try post.fetchUser(&pool, allocator)) |author| {
        defer allocator.free(author);
        std.debug.print("Post authored by: {s}\n", .{author.name});
    }

    // Fetch a user
    const user = (try models.Users.findById(&pool, allocator, user_id)).?;
    defer allocator.free(user);

    // Fetch all posts by this user using hasMany relationship
    const user_posts = try user.fetchPosts(&pool, allocator);
    defer allocator.free(user_posts);

    for (user_posts) |p| {
        std.debug.print("Post: {s}\n", .{p.title});
    }

    // Fetch all comments by this user
    const user_comments = try user.fetchComments(&pool, allocator);
    defer allocator.free(user_comments);
}
```

## Naming Conventions

The generated method name depends on the relationship type:

### For belongsTo, hasOne, manyToMany

- **Pattern**: `fetch{PascalCaseRelationshipName}`
- **Example**: `name = "post_author"` → `fetchPostAuthor()`

### For hasMany

- **Pattern**: `fetch{PascalCaseForeignTable}` (derived from relationship name)
- **Example**: `name = "user_posts"` → `fetchPosts()`

Choose descriptive relationship names that reflect the domain relationship:

```zig
// Good names for belongsTo/hasOne
.name = "post_author"      // fetchPostAuthor() -> returns ?Users
.name = "order_customer"   // fetchOrderCustomer() -> returns ?Customers

// Good names for hasMany
.name = "user_posts"       // fetchPosts() -> returns []Posts
.name = "category_products" // fetchProducts() -> returns []Products

// Avoid generic names
.name = "relation1"        // fetchRelation1() (unclear)
```

### Model Naming

Generated model struct names use **PascalCase plural** form:

| Table Name        | Struct Name      | Import                           |
| ----------------- | ---------------- | -------------------------------- |
| `users`           | `Users`          | `@import("users.zig")`           |
| `posts`           | `Posts`          | `@import("posts.zig")`           |
| `post_categories` | `PostCategories` | `@import("post_categories.zig")` |

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
