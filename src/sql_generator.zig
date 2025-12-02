const std = @import("std");

const Field = @import("schema.zig").Field;
const TableSchema = @import("table.zig");

fn generateFieldSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), field: Field, is_alter: bool) !void {
    if (is_alter) {
        try sql.print(allocator, "ALTER COLUMN {s} TYPE {s}", .{ field.name, field.type.toPgType() });
    } else {
        try sql.print(allocator, "  {s} {s}", .{ field.name, field.type.toPgType() });
    }

    if (field.primary_key) {
        try sql.appendSlice(allocator, " PRIMARY KEY");
    }
    if (field.unique and !field.primary_key) {
        try sql.appendSlice(allocator, " UNIQUE");
    }
    if (field.not_null and !field.primary_key) {
        try sql.appendSlice(allocator, " NOT NULL");
    }
    if (field.auto_generated and field.auto_generate_type == .increments) {
        try sql.appendSlice(allocator, " GENERATED ALWAYS AS IDENTITY");
    } else if (field.default_value) |default| {
        try sql.print(allocator, " DEFAULT {s}", .{default});
    } else if (field.auto_generated and field.auto_generate_type == .uuid) {
        try sql.appendSlice(allocator, " DEFAULT gen_random_uuid()");
    } else if (field.auto_generated and field.auto_generate_type == .timestamp) {
        try sql.appendSlice(allocator, " DEFAULT CURRENT_TIMESTAMP");
    }
}

/// Generate CREATE TABLE SQL without foreign key constraints
pub fn generateCreateTableSQL(allocator: std.mem.Allocator, table: TableSchema) ![]u8 {
    var sql = std.ArrayList(u8){};
    errdefer sql.deinit(allocator);

    try sql.print(allocator, "-- Table: {s}\n", .{table.name});
    try sql.print(allocator, "CREATE TABLE IF NOT EXISTS {s} (\n", .{table.name});

    // Add fields only (no foreign keys in CREATE TABLE)
    for (table.fields.items, 0..) |field, i| {
        try generateFieldSQL(allocator, &sql, field, false);

        if (i < table.fields.items.len - 1) {
            try sql.appendSlice(allocator, ",\n");
        } else {
            try sql.appendSlice(allocator, "\n");
        }
    }

    try sql.appendSlice(allocator, ");\n");

    // Add indexes
    for (table.indexes.items) |idx| {
        try sql.appendSlice(allocator, "\n");
        if (idx.unique) {
            try sql.print(allocator, "CREATE UNIQUE INDEX IF NOT EXISTS {s} ON {s} (", .{ idx.name, table.name });
        } else {
            try sql.print(allocator, "CREATE INDEX IF NOT EXISTS {s} ON {s} (", .{ idx.name, table.name });
        }

        for (idx.columns, 0..) |col, i| {
            try sql.appendSlice(allocator, col);
            if (i < idx.columns.len - 1) {
                try sql.appendSlice(allocator, ", ");
            }
        }

        try sql.appendSlice(allocator, ");");
    }

    // Add drop index
    for (table.drop_indexes.items) |idx| {
        try sql.appendSlice(allocator, "\n");
        try sql.print(allocator, "DROP INDEX IF EXISTS {s};", .{idx});
    }

    // Add alter table
    for (table.alters.items) |alter| {
        try sql.appendSlice(allocator, "\n");
        try sql.print(allocator, "ALTER TABLE {s} ", .{table.name});
        try generateFieldSQL(allocator, &sql, alter, true);
        try sql.appendSlice(allocator, ";");
    }

    return sql.toOwnedSlice(allocator);
}

/// Generate ALTER TABLE statements for foreign key constraints
pub fn generateConstraintsSQL(allocator: std.mem.Allocator, table: TableSchema) !?[]u8 {
    // Only generate if there are relationships that need FK constraints
    // (many_to_one and one_to_one create FK constraints, one_to_many does not)
    var fk_count: usize = 0;
    for (table.relationships.items) |rel| {
        if (rel.relationship_type == .many_to_one or rel.relationship_type == .one_to_one) {
            fk_count += 1;
        }
    }

    if (fk_count == 0) {
        return null;
    }

    var sql = std.ArrayList(u8){};
    errdefer sql.deinit(allocator);

    try sql.print(allocator, "-- Foreign Key Constraints for: {s}\n", .{table.name});

    var first = true;
    for (table.relationships.items) |rel| {
        // Only many_to_one and one_to_one relationships create FK constraints
        if (rel.relationship_type != .many_to_one and rel.relationship_type != .one_to_one) {
            continue;
        }

        if (!first) {
            try sql.appendSlice(allocator, "\n");
        }
        first = false;

        try sql.print(allocator, "ALTER TABLE {s} ADD CONSTRAINT fk_{s}_{s}\n", .{
            table.name,
            table.name,
            rel.name,
        });
        try sql.print(allocator, "  FOREIGN KEY ({s}) REFERENCES {s}({s})\n", .{
            rel.column,
            rel.references_table,
            rel.references_column,
        });
        try sql.print(allocator, "  ON DELETE {s} ON UPDATE {s};", .{
            rel.on_delete.toSQL(),
            rel.on_update.toSQL(),
        });
    }

    const result = try sql.toOwnedSlice(allocator);
    return result;
}

/// Write table creation SQL to tables/ subdirectory
pub fn writeTableToFile(allocator: std.mem.Allocator, table: TableSchema, output_dir: []const u8, file_prefix: []const u8) !void {
    const sql = try generateCreateTableSQL(allocator, table);
    defer allocator.free(sql);

    // Create tables subdirectory
    const tables_dir = try std.fmt.allocPrint(allocator, "{s}/tables", .{output_dir});
    defer allocator.free(tables_dir);

    std.fs.cwd().makePath(tables_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const filename = try std.fmt.allocPrint(allocator, "{s}/{s}_{s}.sql", .{ tables_dir, file_prefix, table.name });
    defer allocator.free(filename);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    try file.writeAll(sql);
}

/// Write foreign key constraints SQL to constraints/ subdirectory
pub fn writeConstraintsToFile(allocator: std.mem.Allocator, table: TableSchema, output_dir: []const u8, file_prefix: []const u8) !void {
    const sql = try generateConstraintsSQL(allocator, table) orelse return;
    defer allocator.free(sql);

    // Create constraints subdirectory
    const constraints_dir = try std.fmt.allocPrint(allocator, "{s}/constraints", .{output_dir});
    defer allocator.free(constraints_dir);

    std.fs.cwd().makePath(constraints_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const filename = try std.fmt.allocPrint(allocator, "{s}/{s}_{s}_fk.sql", .{ constraints_dir, file_prefix, table.name });
    defer allocator.free(filename);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    try file.writeAll(sql);
}

/// Write both table and constraints SQL files
pub fn writeSchemaToFile(allocator: std.mem.Allocator, table: TableSchema, output_dir: []const u8, file_prefix: []const u8) !void {
    try writeTableToFile(allocator, table, output_dir, file_prefix);
    try writeConstraintsToFile(allocator, table, output_dir, file_prefix);
}
