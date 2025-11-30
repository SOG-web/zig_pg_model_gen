# FluentORM - re-write in-progress

# Usage

```zig
// ===== File: tools/sql_generator_template.zig (in your codebase) =====

const std = @import("std");
const fluentorm = @import("fluentorm");
const sql_generator = fluentorm.sql_generator;

// Import the auto-generated registry
const registry = @import("your generate registry file");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const output_dir = if (args.len > 1) args[1] else "migrations";

    std.fs.cwd().makePath(output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const schemas = try registry.getAllSchemas(allocator);
    defer {
        for (schemas) |*schema| {
            schema.deinit();
        }
        allocator.free(schemas);
    }

    for (schemas) |*schema| {
        try sql_generator.writeSchemaToFile(allocator, schema, output_dir);
        std.debug.print("Generated: {s}/{s}.sql\n", .{ output_dir, schema.name });
    }

    std.debug.print("SQL generation complete!\n", .{});
}
```
