// Test schema merging functionality
const std = @import("std");
const registry = @import("registry.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing schema merging...\n\n", .{});

    // Get merged schemas
    const schemas = try registry.getAllSchemas(allocator);
    defer {
        for (schemas) |*s| {
            var schema = s;
            schema.deinit();
        }
        allocator.free(schemas);
    }

    std.debug.print("Total unique tables: {d}\n\n", .{schemas.len});

    // Find users table and print its fields
    for (schemas) |schema| {
        std.debug.print("Table: {s}\n", .{schema.name});
        std.debug.print("  Fields ({d}):\n", .{schema.fields.items.len});
        for (schema.fields.items) |field| {
            std.debug.print("    - {s}\n", .{field.name});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("Schema merging test completed!\n", .{});
}
