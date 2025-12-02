const std = @import("std");

const SchemaFileInfo = struct {
    table_name: []const u8, // Table name from pub const table_name (e.g., "users")
    filename: []const u8, // Original filename without .zig (e.g., "01_users")
    order: u32, // Numeric order from prefix (e.g., 1 from "01_users")
};

const TableGroup = struct {
    table_name: []const u8,
    files: std.ArrayList(SchemaFileInfo),
};

/// Extract table_name constant from a schema file
fn extractTableName(allocator: std.mem.Allocator, schemas_dir: []const u8, filename: []const u8) !?[]const u8 {
    const path = try std.fs.path.join(allocator, &.{ schemas_dir, filename });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(content);

    // Look for: pub const table_name = "...";
    const pattern = "pub const table_name";
    if (std.mem.indexOf(u8, content, pattern)) |start| {
        // Find the opening quote
        const after_pattern = content[start + pattern.len ..];
        if (std.mem.indexOf(u8, after_pattern, "\"")) |quote_start| {
            const after_quote = after_pattern[quote_start + 1 ..];
            // Find the closing quote
            if (std.mem.indexOf(u8, after_quote, "\"")) |quote_end| {
                return try allocator.dupe(u8, after_quote[0..quote_end]);
            }
        }
    }

    return null;
}

/// Extract numeric order from filename prefix (e.g., "01_users" -> 1)
fn extractOrder(filename: []const u8) u32 {
    if (filename.len < 2) return 0;
    return std.fmt.parseInt(u32, filename[0..2], 10) catch 0;
}

pub fn generateRegistry(schemas_dir: []const u8, output_file: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Find all .zig files in schemas directory
    var dir = try std.fs.cwd().openDir(schemas_dir, .{ .iterate = true });
    defer dir.close();

    var schema_files = std.ArrayList(SchemaFileInfo){};
    defer {
        for (schema_files.items) |item| {
            allocator.free(item.table_name);
            allocator.free(item.filename);
        }
        schema_files.deinit(allocator);
    }

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
        if (std.mem.eql(u8, entry.name, "registry.zig")) continue;
        if (std.mem.eql(u8, entry.name, "runner.zig")) continue;
        if (std.mem.startsWith(u8, entry.name, "test_")) continue; // Skip test files

        // Filename without .zig extension (e.g., "01_users")
        const filename = try allocator.dupe(u8, entry.name[0 .. entry.name.len - 4]);

        // Try to extract table_name from the file
        const table_name = try extractTableName(allocator, schemas_dir, entry.name);
        if (table_name == null) {
            // Fallback: use filename without prefix (e.g., "01_users" -> "users")
            const fallback_name = if (filename.len > 3 and filename[2] == '_')
                try allocator.dupe(u8, filename[3..])
            else
                try allocator.dupe(u8, filename);

            try schema_files.append(allocator, .{
                .table_name = fallback_name,
                .filename = filename,
                .order = extractOrder(filename),
            });
        } else {
            try schema_files.append(allocator, .{
                .table_name = table_name.?,
                .filename = filename,
                .order = extractOrder(filename),
            });
        }
    }

    // Sort by order (numeric prefix)
    std.mem.sort(SchemaFileInfo, schema_files.items, {}, struct {
        fn lessThan(_: void, a: SchemaFileInfo, b: SchemaFileInfo) bool {
            return a.order < b.order;
        }
    }.lessThan);

    // Group by table_name
    var table_groups = std.StringHashMap(std.ArrayList(SchemaFileInfo)).init(allocator);
    defer {
        var it = table_groups.valueIterator();
        while (it.next()) |list| {
            list.deinit(allocator);
        }
        table_groups.deinit();
    }

    for (schema_files.items) |schema| {
        const gop = try table_groups.getOrPut(schema.table_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(SchemaFileInfo){};
        }
        try gop.value_ptr.append(allocator, schema);
    }

    // Collect unique table names and sort by first file's order
    var unique_tables = std.ArrayList(struct { name: []const u8, first_order: u32 }){};
    defer unique_tables.deinit(allocator);

    var key_it = table_groups.iterator();
    while (key_it.next()) |entry| {
        const files = entry.value_ptr.items;
        if (files.len > 0) {
            try unique_tables.append(allocator, .{
                .name = entry.key_ptr.*,
                .first_order = files[0].order,
            });
        }
    }

    std.mem.sort(@TypeOf(unique_tables.items[0]), unique_tables.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(unique_tables.items[0]), b: @TypeOf(unique_tables.items[0])) bool {
            return a.first_order < b.first_order;
        }
    }.lessThan);

    var registry = std.ArrayList(u8){};
    errdefer registry.deinit(allocator);

    // Generate registry file
    const file = try std.fs.cwd().createFile(output_file, .{});
    defer file.close();

    try registry.appendSlice(allocator, "// Auto-generated file - do not edit manually\n");
    try registry.appendSlice(allocator, "// Run 'zig build generate' to regenerate\n\n");
    try registry.appendSlice(allocator, "const std = @import(\"std\");\n");
    try registry.appendSlice(allocator, "const TableSchema = @import(\"fluentorm\").TableSchema;\n");
    try registry.appendSlice(allocator, "const SchemaBuilder = @import(\"fluentorm\").SchemaBuilder;\n\n");

    // Import all schema files
    for (schema_files.items) |schema| {
        // Use filename as import identifier (replacing hyphens/dots with underscores)
        var import_name = std.ArrayList(u8){};
        defer import_name.deinit(allocator);
        for (schema.filename) |c| {
            if (c == '-' or c == '.') {
                try import_name.append(allocator, '_');
            } else {
                try import_name.append(allocator, c);
            }
        }
        const import_id = try import_name.toOwnedSlice(allocator);
        defer allocator.free(import_id);

        try registry.writer(allocator).print("const @\"{s}_schema\" = @import(\"{s}.zig\");\n", .{ import_id, schema.filename });
    }

    // Generate TableInfo struct for grouped schemas
    try registry.appendSlice(allocator, "\n/// Information about a table and its schema files\n");
    try registry.appendSlice(allocator, "pub const TableInfo = struct {\n");
    try registry.appendSlice(allocator, "    name: []const u8,\n");
    try registry.appendSlice(allocator, "    builders: []const SchemaBuilder,\n");
    try registry.appendSlice(allocator, "};\n\n");

    // Generate grouped table info
    try registry.appendSlice(allocator, "/// Tables grouped by table_name with their schema builders\n");
    try registry.appendSlice(allocator, "pub const tables = [_]TableInfo{\n");

    for (unique_tables.items) |table| {
        const files = table_groups.get(table.name).?;
        try registry.writer(allocator).print("    .{{ .name = \"{s}\", .builders = &[_]SchemaBuilder{{\n", .{table.name});
        for (files.items) |schema| {
            var import_name = std.ArrayList(u8){};
            defer import_name.deinit(allocator);
            for (schema.filename) |c| {
                if (c == '-' or c == '.') {
                    try import_name.append(allocator, '_');
                } else {
                    try import_name.append(allocator, c);
                }
            }
            const import_id = try import_name.toOwnedSlice(allocator);
            defer allocator.free(import_id);

            try registry.writer(allocator).print("        .{{ .name = \"{s}\", .builder_fn = @\"{s}_schema\".build }},\n", .{ table.name, import_id });
        }
        try registry.appendSlice(allocator, "    }},\n");
    }
    try registry.appendSlice(allocator, "};\n\n");

    // Function: get all schemas with merging
    try registry.appendSlice(allocator,
        \\/// Get all schemas, merging multiple files that share the same table_name.
        \\/// Multiple schema files with the same `pub const table_name` will be combined
        \\/// into a single TableSchema by calling all their build() functions sequentially.
        \\pub fn getAllSchemas(allocator: std.mem.Allocator) ![]TableSchema {
        \\    var result = std.ArrayList(TableSchema){};
        \\    errdefer {
        \\        for (result.items) |*schema| {
        \\            schema.deinit();
        \\        }
        \\        result.deinit(allocator);
        \\    }
        \\
        \\    for (tables) |table_info| {
        \\        // Create ONE TableSchema per unique table_name
        \\        var table = try TableSchema.createEmpty(table_info.name, allocator);
        \\        errdefer table.deinit();
        \\
        \\        // Call all builder functions for this table (merging fields, indexes, etc.)
        \\        for (table_info.builders) |builder| {
        \\            builder.builder_fn(&table);
        \\        }
        \\
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

    std.debug.print("Generated registry with {d} tables ({d} schema files) at {s}\n", .{ unique_tables.items.len, schema_files.items.len, output_file });
}
