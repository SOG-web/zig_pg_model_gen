// Auto-generated file - do not edit manually
// Run 'zig build generate-registry' to regenerate

const std = @import("std");
const TableSchema = @import("fluentorm").TableSchema;
const SchemaBuilder = @import("fluentorm").SchemaBuilder;

const ner_schema = @import("ner.zig");
const posts_schema = @import("posts.zig");
const users_schema = @import("users.zig");
pub const schemas = [_]SchemaBuilder{
    .{ .name = "ner", .builder_fn = ner_schema.build },
    .{ .name = "posts", .builder_fn = posts_schema.build },
    .{ .name = "users", .builder_fn = users_schema.build },
};

pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
    var result = std.ArrayList(TableSchema){};
    errdefer {
        for (result.items) |*schema| {
            schema.deinit(allocator);
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
