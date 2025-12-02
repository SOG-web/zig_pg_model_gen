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
    const sql_output_dir = "migrations";

    try std.fs.cwd().makePath(output_dir);
    try std.fs.cwd().makePath(sql_output_dir);

    // Get file prefixes from registry
    const prefixes = registry.getFilePrefixes();

    for (schemas, 0..) |schema, i| {
        // Use schema name as the source file name for comments
        const schema_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{schema.name});
        defer allocator.free(schema_file);

        // Get the file prefix (e.g., "01", "02") for ordering migrations
        const file_prefix = prefixes[i];

        try sql_generator.writeSchemaToFile(allocator, schema, sql_output_dir, file_prefix);
        try model_generator.generateModel(allocator, schema, schema_file, output_dir);
    }

    try model_generator.generateBarrelFile(allocator, schemas, output_dir);
}
