const std = @import("std");
const registry = @import("registry.zig");
const fluentorm = @import("fluentorm");
const sql_generator = fluentorm.sql_generator;
const model_generator = fluentorm.model_generator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const schemas = try registry.getAllSchemas(allocator);
    defer {
        for (schemas) |*s| s.deinit();
        allocator.free(schemas);
    }

    const output_dir = "src/models/generated";

    for (schemas) |schema| {
        // Use schema name as the source file name for comments
        const schema_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{schema.name});
        defer allocator.free(schema_file);

        try sql_generator.writeSchemaToFile(allocator, schema, output_dir);
        try model_generator.generateModel(allocator, schema, schema_file, output_dir);
    }
}
