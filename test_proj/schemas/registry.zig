// Auto-generated file - do not edit manually
// Run 'zig build generate-registry' to regenerate

const std = @import("std");
const TableSchema = @import("fluentorm").TableSchema;
const SchemaBuilder = @import("fluentorm").SchemaBuilder;

const users_schema = @import("01_users.zig");
const posts_schema = @import("02_posts.zig");
const profiles_schema = @import("03_profiles.zig");
const categories_schema = @import("04_categories.zig");
const post_categories_schema = @import("05_post_categories.zig");
const comments_schema = @import("06_comments.zig");

pub const schemas = [_]SchemaBuilder{
    .{ .name = "users", .builder_fn = users_schema.build },
    .{ .name = "posts", .builder_fn = posts_schema.build },
    .{ .name = "profiles", .builder_fn = profiles_schema.build },
    .{ .name = "categories", .builder_fn = categories_schema.build },
    .{ .name = "post_categories", .builder_fn = post_categories_schema.build },
    .{ .name = "comments", .builder_fn = comments_schema.build },
};

/// File prefixes for SQL migration ordering (e.g., "01", "02")
pub const file_prefixes = [_][]const u8{
    "01",
    "02",
    "03",
    "04",
    "05",
    "06",
};

/// Get file prefixes for SQL migration ordering
pub fn getFilePrefixes() []const []const u8 {
    return &file_prefixes;
}

pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
    var result = std.ArrayList(TableSchema){};
    errdefer {
        for (result.items) |*schema| {
            schema.deinit();
        }
        result.deinit(allocator);
    }

    for (schemas) |schema_builder| {
        const table = try TableSchema.create(
            schema_builder.name,
            allocator,
            schema_builder.builder_fn,
        );
        try result.append(allocator, table);
    }

    return result.toOwnedSlice(allocator);
}
