const std = @import("std");

pub fn generateRegistry(schemas_dir: []const u8, output_file: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Find all .zig files in schemas directory
    var dir = try std.fs.cwd().openDir(schemas_dir, .{ .iterate = true });
    defer dir.close();

    var schemas = std.ArrayList([]const u8){};
    defer schemas.deinit(allocator);

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (std.mem.eql(u8, entry.name, "registry.zig")) continue;

        // TODO: consider naming - e.g 01_schema.zig, 02_schema.zig, etc.
        const name = try allocator.dupe(u8, entry.name[3 .. entry.name.len - 4]);
        try schemas.append(
            allocator,
            name,
        );
    }

    // TODO: sort by number - e.g 01_schema.zig, 02_schema.zig, etc.
    std.mem.sort([]const u8, schemas.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    var registry = std.ArrayList(u8){};
    errdefer registry.deinit(allocator);

    // Generate registry file
    const file = try std.fs.cwd().createFile(output_file, .{});
    defer file.close();

    try registry.appendSlice(allocator, "// Auto-generated file - do not edit manually\n");
    try registry.appendSlice(allocator, "// Run 'zig build generate-registry' to regenerate\n\n");
    try registry.appendSlice(allocator, "const std = @import(\"std\");\n");
    try registry.appendSlice(allocator, "const TableSchema = @import(\"fluentorm\").TableSchema;\n");
    try registry.appendSlice(allocator, "const SchemaBuilder = @import(\"fluentorm\").SchemaBuilder;\n\n");

    // Import all schema files
    for (schemas.items) |schema_name| {
        try registry.writer(allocator).print("const {s}_schema = @import(\"{s}.zig\");\n", .{ schema_name, schema_name });
    }

    try registry.appendSlice(allocator, "pub const schemas = [_]SchemaBuilder{\n");
    for (schemas.items) |schema_name| {
        try registry.writer(allocator).print("    .{{ .name = \"{s}\", .builder_fn = {s}_schema.build }},\n", .{ schema_name, schema_name });
    }
    try registry.appendSlice(allocator, "};\n\n");

    try registry.appendSlice(allocator,
        \\pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
        \\    var result = std.ArrayList(TableSchema){};
        \\    errdefer {
        \\        for (result.items) |*schema| {
        \\            schema.deinit(allocator);
        \\        }
        \\        result.deinit(allocator);
        \\    }
        \\
        \\    for (schemas) |schema_builder| {
        \\        const table = try TableSchema.create(
        \\            schema_builder.name,
        \\            allocator,
        \\            schema_builder.builder_fn,
        \\        );
        \\        try result.append(allocator, table);
        \\    }
        \\
        \\    return result.toOwnedSlice(allocator);
        \\}
        \\
    );

    const final = try registry.toOwnedSlice(allocator);
    defer allocator.free(final);

    try file.writeAll(final);

    std.debug.print("Generated registry with {d} schemas at {s}\n", .{ schemas.items.len, output_file });
    for (schemas.items) |name| {
        allocator.free(name);
    }
}
