const std = @import("std");

const SchemaInfo = struct {
    name: []const u8, // Table name (e.g., "users")
    filename: []const u8, // Original filename without .zig (e.g., "01_users")
};

pub fn generateRegistry(schemas_dir: []const u8, output_file: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Find all .zig files in schemas directory
    var dir = try std.fs.cwd().openDir(schemas_dir, .{ .iterate = true });
    defer dir.close();

    var schemas = std.ArrayList(SchemaInfo){};
    defer schemas.deinit(allocator);

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (std.mem.eql(u8, entry.name, "registry.zig")) continue;
        if (std.mem.eql(u8, entry.name, "runner.zig")) continue;

        // Filename without .zig extension (e.g., "01_users")
        const filename = try allocator.dupe(u8, entry.name[0 .. entry.name.len - 4]);
        // Table name: strip XX_ prefix (e.g., "01_users" -> "users")
        const name = try allocator.dupe(u8, entry.name[3 .. entry.name.len - 4]);

        try schemas.append(allocator, .{
            .name = name,
            .filename = filename,
        });
    }

    // Sort by filename to maintain order (01_, 02_, etc.)
    std.mem.sort(SchemaInfo, schemas.items, {}, struct {
        fn lessThan(_: void, a: SchemaInfo, b: SchemaInfo) bool {
            return std.mem.order(u8, a.filename, b.filename) == .lt;
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
    for (schemas.items) |schema| {
        try registry.writer(allocator).print("const {s}_schema = @import(\"{s}.zig\");\n", .{ schema.name, schema.filename });
    }

    try registry.appendSlice(allocator, "\npub const schemas = [_]SchemaBuilder{\n");
    for (schemas.items) |schema| {
        try registry.writer(allocator).print("    .{{ .name = \"{s}\", .builder_fn = {s}_schema.build }},\n", .{ schema.name, schema.name });
    }
    try registry.appendSlice(allocator, "};\n\n");

    // Generate file prefixes array for SQL migration ordering
    try registry.appendSlice(allocator, "/// File prefixes for SQL migration ordering (e.g., \"01\", \"02\")\n");
    try registry.appendSlice(allocator, "pub const file_prefixes = [_][]const u8{\n");
    for (schemas.items) |schema| {
        // Extract the prefix (e.g., "01" from "01_users")
        const prefix = schema.filename[0..2];
        try registry.writer(allocator).print("    \"{s}\",\n", .{prefix});
    }
    try registry.appendSlice(allocator, "};\n\n");

    try registry.appendSlice(allocator, "/// Get file prefixes for SQL migration ordering\n");
    try registry.appendSlice(allocator, "pub fn getFilePrefixes() []const []const u8 {\n");
    try registry.appendSlice(allocator, "    return &file_prefixes;\n");
    try registry.appendSlice(allocator, "}\n\n");

    try registry.appendSlice(allocator,
        \\pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
        \\    var result = std.ArrayList(TableSchema){};
        \\    errdefer {
        \\        for (result.items) |*schema| {
        \\            schema.deinit();
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
    for (schemas.items) |schema| {
        allocator.free(schema.name);
        allocator.free(schema.filename);
    }
}
