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

pub fn generateCreateTableSQL(allocator: std.mem.Allocator, table: TableSchema) ![]u8 {
    var sql = std.ArrayList(u8){};
    errdefer sql.deinit(allocator);

    try sql.print(allocator, "-- Table: {s}\n", .{table.name});
    try sql.print(allocator, "CREATE TABLE IF NOT EXISTS {s} (\n", .{table.name});

    // Add fields
    for (table.fields.items, 0..) |field, i| {
        try generateFieldSQL(allocator, &sql, field, false);

        if (i < table.fields.items.len - 1 or table.relationships.items.len > 0) {
            try sql.appendSlice(allocator, ",\n");
        } else {
            try sql.appendSlice(allocator, "\n");
        }
    }

    // Add foreign keys
    for (table.relationships.items, 0..) |rel, i| {
        try sql.print(allocator, "  CONSTRAINT fk_{s}_{s} FOREIGN KEY ({s}) REFERENCES {s}({s})", .{
            table.name,
            rel.name,
            rel.column,
            rel.references_table,
            rel.references_column,
        });

        try sql.print(allocator, " ON DELETE {s}", .{rel.on_delete.toSQL()});
        try sql.print(allocator, " ON UPDATE {s}", .{rel.on_update.toSQL()});

        if (i < table.relationships.items.len - 1) {
            try sql.appendSlice(allocator, ",\n");
        } else {
            try sql.appendSlice(allocator, "\n");
        }
    }

    try sql.appendSlice(allocator, ");\n\n");

    // Add indexes
    for (table.indexes.items) |idx| {
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

        try sql.appendSlice(allocator, ");\n");
    }

    // Add drop index
    for (table.drop_indexes.items) |idx| {
        try sql.print(allocator, "DROP INDEX IF EXISTS {s};\n", .{idx});
    }

    // Add alter table
    for (table.alters.items) |alter| {
        try sql.print(allocator, "ALTER TABLE {s} ", .{table.name});
        try generateFieldSQL(allocator, &sql, alter, true);
        try sql.appendSlice(allocator, ";\n");
    }

    return sql.toOwnedSlice(allocator);
}

pub fn writeSchemaToFile(allocator: std.mem.Allocator, table: TableSchema, output_dir: []const u8) !void {
    const sql = try generateCreateTableSQL(allocator, table);
    defer allocator.free(sql);

    const filename = try std.fmt.allocPrint(allocator, "{s}/{s}.sql", .{ output_dir, table.name });
    defer allocator.free(filename);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    try file.writeAll(sql);
}
