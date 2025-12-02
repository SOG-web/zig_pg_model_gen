const std = @import("std");

const diff_mod = @import("diff.zig");
const snapshot_mod = @import("snapshot.zig");

const SchemaDiff = diff_mod.SchemaDiff;
const TableChange = diff_mod.TableChange;
const FieldChange = diff_mod.FieldChange;
const IndexChange = diff_mod.IndexChange;
const RelationshipChange = diff_mod.RelationshipChange;
const ChangeType = diff_mod.ChangeType;
const FieldSnapshot = snapshot_mod.FieldSnapshot;
const IndexSnapshot = snapshot_mod.IndexSnapshot;
const RelationshipSnapshot = snapshot_mod.RelationshipSnapshot;
const TableSnapshot = snapshot_mod.TableSnapshot;

fn fieldTypeToPgType(type_str: []const u8) []const u8 {
    // Match the actual FieldType enum tag names from schema.zig
    if (std.mem.eql(u8, type_str, "uuid")) return "UUID";
    if (std.mem.eql(u8, type_str, "uuid_optional")) return "UUID";
    if (std.mem.eql(u8, type_str, "text")) return "TEXT";
    if (std.mem.eql(u8, type_str, "text_optional")) return "TEXT";
    if (std.mem.eql(u8, type_str, "bool")) return "BOOLEAN";
    if (std.mem.eql(u8, type_str, "bool_optional")) return "BOOLEAN";
    if (std.mem.eql(u8, type_str, "i16")) return "SMALLINT";
    if (std.mem.eql(u8, type_str, "i16_optional")) return "SMALLINT";
    if (std.mem.eql(u8, type_str, "i32")) return "INT";
    if (std.mem.eql(u8, type_str, "i32_optional")) return "INT";
    if (std.mem.eql(u8, type_str, "i64")) return "BIGINT";
    if (std.mem.eql(u8, type_str, "i64_optional")) return "BIGINT";
    if (std.mem.eql(u8, type_str, "f32")) return "float4";
    if (std.mem.eql(u8, type_str, "f32_optional")) return "float4";
    if (std.mem.eql(u8, type_str, "f64")) return "numeric";
    if (std.mem.eql(u8, type_str, "f64_optional")) return "numeric";
    if (std.mem.eql(u8, type_str, "timestamp")) return "TIMESTAMP";
    if (std.mem.eql(u8, type_str, "timestamp_optional")) return "TIMESTAMP";
    if (std.mem.eql(u8, type_str, "json")) return "JSON";
    if (std.mem.eql(u8, type_str, "json_optional")) return "JSON";
    if (std.mem.eql(u8, type_str, "jsonb")) return "JSONB";
    if (std.mem.eql(u8, type_str, "jsonb_optional")) return "JSONB";
    if (std.mem.eql(u8, type_str, "binary")) return "bytea";
    if (std.mem.eql(u8, type_str, "binary_optional")) return "bytea";
    return "TEXT"; // fallback
}

fn generateFieldSnapshotSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), field: FieldSnapshot) !void {
    try sql.appendSlice(allocator, "  ");
    try sql.appendSlice(allocator, field.name);
    try sql.appendSlice(allocator, " ");
    try sql.appendSlice(allocator, fieldTypeToPgType(field.type));

    if (field.primary_key) {
        try sql.appendSlice(allocator, " PRIMARY KEY");
    }

    // NOT NULL comes before UNIQUE
    if (field.not_null and !field.primary_key) {
        try sql.appendSlice(allocator, " NOT NULL");
    }

    if (field.unique and !field.primary_key) {
        try sql.appendSlice(allocator, " UNIQUE");
    }

    // Handle auto-generation and defaults
    if (field.auto_generated) {
        if (std.mem.eql(u8, field.auto_generate_type, "increments")) {
            try sql.appendSlice(allocator, " GENERATED ALWAYS AS IDENTITY");
        } else if (std.mem.eql(u8, field.auto_generate_type, "uuid")) {
            try sql.appendSlice(allocator, " DEFAULT gen_random_uuid()");
        } else if (std.mem.eql(u8, field.auto_generate_type, "timestamp")) {
            try sql.appendSlice(allocator, " DEFAULT CURRENT_TIMESTAMP");
        }
    } else if (field.default_value) |default| {
        try sql.appendSlice(allocator, " DEFAULT ");
        try sql.appendSlice(allocator, default);
    }
}

/// Generate field change SQL (ADD, DROP, ALTER COLUMN)
fn generateFieldChangeSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, fc: FieldChange) !void {
    switch (fc.change_type) {
        .add => {
            if (fc.new_field) |field| {
                try sql.appendSlice(allocator, "ALTER TABLE ");
                try sql.appendSlice(allocator, table_name);
                try sql.appendSlice(allocator, " ADD COLUMN ");
                try sql.appendSlice(allocator, field.name);
                try sql.appendSlice(allocator, " ");
                try sql.appendSlice(allocator, fieldTypeToPgType(field.type));

                if (field.not_null) {
                    // For NOT NULL columns, we need a default or to allow null initially
                    if (field.default_value) |default| {
                        try sql.appendSlice(allocator, " NOT NULL DEFAULT ");
                        try sql.appendSlice(allocator, default);
                    } else if (field.auto_generated) {
                        if (std.mem.eql(u8, field.auto_generate_type, "uuid")) {
                            try sql.appendSlice(allocator, " NOT NULL DEFAULT gen_random_uuid()");
                        } else if (std.mem.eql(u8, field.auto_generate_type, "timestamp")) {
                            try sql.appendSlice(allocator, " NOT NULL DEFAULT CURRENT_TIMESTAMP");
                        } else {
                            try sql.appendSlice(allocator, " NOT NULL");
                        }
                    } else {
                        // Add as nullable first, user should handle data migration
                        try sql.appendSlice(allocator, " -- WARNING: NOT NULL requires default or data migration");
                    }
                }

                if (field.unique) {
                    try sql.appendSlice(allocator, " UNIQUE");
                }

                try sql.appendSlice(allocator, ";\n");
            }
        },
        .remove => {
            try sql.appendSlice(allocator, "ALTER TABLE ");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, " DROP COLUMN IF EXISTS ");
            try sql.appendSlice(allocator, fc.field_name);
            try sql.appendSlice(allocator, ";\n");
        },
        .modify => {
            if (fc.new_field) |new_field| {
                const old_field = fc.old_field orelse return;

                // Type change
                if (!std.mem.eql(u8, old_field.type, new_field.type)) {
                    try sql.appendSlice(allocator, "ALTER TABLE ");
                    try sql.appendSlice(allocator, table_name);
                    try sql.appendSlice(allocator, " ALTER COLUMN ");
                    try sql.appendSlice(allocator, new_field.name);
                    try sql.appendSlice(allocator, " TYPE ");
                    try sql.appendSlice(allocator, fieldTypeToPgType(new_field.type));
                    try sql.appendSlice(allocator, ";\n");
                }

                // NOT NULL change
                if (old_field.not_null != new_field.not_null) {
                    try sql.appendSlice(allocator, "ALTER TABLE ");
                    try sql.appendSlice(allocator, table_name);
                    try sql.appendSlice(allocator, " ALTER COLUMN ");
                    try sql.appendSlice(allocator, new_field.name);
                    if (new_field.not_null) {
                        try sql.appendSlice(allocator, " SET NOT NULL;\n");
                    } else {
                        try sql.appendSlice(allocator, " DROP NOT NULL;\n");
                    }
                }

                // UNIQUE change - need to add/drop constraint
                if (old_field.unique != new_field.unique) {
                    if (new_field.unique) {
                        try sql.appendSlice(allocator, "ALTER TABLE ");
                        try sql.appendSlice(allocator, table_name);
                        try sql.appendSlice(allocator, " ADD CONSTRAINT ");
                        try sql.appendSlice(allocator, table_name);
                        try sql.appendSlice(allocator, "_");
                        try sql.appendSlice(allocator, new_field.name);
                        try sql.appendSlice(allocator, "_key UNIQUE (");
                        try sql.appendSlice(allocator, new_field.name);
                        try sql.appendSlice(allocator, ");\n");
                    } else {
                        try sql.appendSlice(allocator, "ALTER TABLE ");
                        try sql.appendSlice(allocator, table_name);
                        try sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS ");
                        try sql.appendSlice(allocator, table_name);
                        try sql.appendSlice(allocator, "_");
                        try sql.appendSlice(allocator, new_field.name);
                        try sql.appendSlice(allocator, "_key;\n");
                    }
                }

                // Default value change
                const old_default = old_field.default_value;
                const new_default = new_field.default_value;
                const defaults_differ = blk: {
                    if (old_default) |od| {
                        if (new_default) |nd| {
                            break :blk !std.mem.eql(u8, od, nd);
                        }
                        break :blk true;
                    }
                    break :blk new_default != null;
                };

                if (defaults_differ) {
                    try sql.appendSlice(allocator, "ALTER TABLE ");
                    try sql.appendSlice(allocator, table_name);
                    try sql.appendSlice(allocator, " ALTER COLUMN ");
                    try sql.appendSlice(allocator, new_field.name);
                    if (new_default) |nd| {
                        try sql.appendSlice(allocator, " SET DEFAULT ");
                        try sql.appendSlice(allocator, nd);
                    } else {
                        try sql.appendSlice(allocator, " DROP DEFAULT");
                    }
                    try sql.appendSlice(allocator, ";\n");
                }
            }
        },
    }
}

/// Generate index SQL
fn generateIndexSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, idx: IndexSnapshot) !void {
    if (idx.unique) {
        try sql.appendSlice(allocator, "CREATE UNIQUE INDEX IF NOT EXISTS ");
    } else {
        try sql.appendSlice(allocator, "CREATE INDEX IF NOT EXISTS ");
    }
    try sql.appendSlice(allocator, idx.name);
    try sql.appendSlice(allocator, " ON ");
    try sql.appendSlice(allocator, table_name);
    try sql.appendSlice(allocator, " (");

    for (idx.columns, 0..) |col, i| {
        try sql.appendSlice(allocator, col);
        if (i < idx.columns.len - 1) {
            try sql.appendSlice(allocator, ", ");
        }
    }

    try sql.appendSlice(allocator, ");\n");
}

/// Generate index change SQL
fn generateIndexChangeSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, ic: IndexChange) !void {
    switch (ic.change_type) {
        .add => {
            if (ic.new_index) |idx| {
                try generateIndexSQL(allocator, sql, table_name, idx);
            }
        },
        .remove => {
            try sql.appendSlice(allocator, "DROP INDEX IF EXISTS ");
            try sql.appendSlice(allocator, ic.index_name);
            try sql.appendSlice(allocator, ";\n");
        },
        .modify => {
            // Drop and recreate
            try sql.appendSlice(allocator, "DROP INDEX IF EXISTS ");
            try sql.appendSlice(allocator, ic.index_name);
            try sql.appendSlice(allocator, ";\n");
            if (ic.new_index) |idx| {
                try generateIndexSQL(allocator, sql, table_name, idx);
            }
        },
    }
}

/// Generate ADD FOREIGN KEY SQL
fn generateAddForeignKeySQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, rel: RelationshipSnapshot) !void {
    // Only many_to_one and one_to_one create FK constraints
    if (!std.mem.eql(u8, rel.relationship_type, "many_to_one") and
        !std.mem.eql(u8, rel.relationship_type, "one_to_one"))
    {
        return;
    }

    try sql.appendSlice(allocator, "ALTER TABLE ");
    try sql.appendSlice(allocator, table_name);
    try sql.appendSlice(allocator, " ADD CONSTRAINT fk_");
    try sql.appendSlice(allocator, table_name);
    try sql.appendSlice(allocator, "_");
    try sql.appendSlice(allocator, rel.name);
    try sql.appendSlice(allocator, "\n  FOREIGN KEY (");
    try sql.appendSlice(allocator, rel.column);
    try sql.appendSlice(allocator, ") REFERENCES ");
    try sql.appendSlice(allocator, rel.references_table);
    try sql.appendSlice(allocator, "(");
    try sql.appendSlice(allocator, rel.references_column);
    try sql.appendSlice(allocator, ")\n  ON DELETE ");
    try sql.appendSlice(allocator, onActionToSQL(rel.on_delete));
    try sql.appendSlice(allocator, " ON UPDATE ");
    try sql.appendSlice(allocator, onActionToSQL(rel.on_update));
    try sql.appendSlice(allocator, ";\n");
}

/// Convert on_delete/on_update string to SQL
fn onActionToSQL(action: []const u8) []const u8 {
    if (std.mem.eql(u8, action, "cascade")) return "CASCADE";
    if (std.mem.eql(u8, action, "set_null")) return "SET NULL";
    if (std.mem.eql(u8, action, "set_default")) return "SET DEFAULT";
    if (std.mem.eql(u8, action, "restrict")) return "RESTRICT";
    return "NO ACTION";
}

/// Generate relationship change SQL
fn generateRelationshipChangeSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, rc: RelationshipChange) !void {
    switch (rc.change_type) {
        .add => {
            if (rc.new_relationship) |rel| {
                try generateAddForeignKeySQL(allocator, sql, table_name, rel);
            }
        },
        .remove => {
            try sql.appendSlice(allocator, "ALTER TABLE ");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS fk_");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, "_");
            try sql.appendSlice(allocator, rc.relationship_name);
            try sql.appendSlice(allocator, ";\n");
        },
        .modify => {
            // Drop and recreate
            try sql.appendSlice(allocator, "ALTER TABLE ");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS fk_");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, "_");
            try sql.appendSlice(allocator, rc.relationship_name);
            try sql.appendSlice(allocator, ";\n");
            if (rc.new_relationship) |rel| {
                try generateAddForeignKeySQL(allocator, sql, table_name, rel);
            }
        },
    }
}

/// Generate rollback SQL for a field change
fn generateRollbackFieldChangeSQL(allocator: std.mem.Allocator, sql: *std.ArrayList(u8), table_name: []const u8, fc: FieldChange) !void {
    switch (fc.change_type) {
        .add => {
            // Rollback: DROP the added column
            try sql.appendSlice(allocator, "ALTER TABLE ");
            try sql.appendSlice(allocator, table_name);
            try sql.appendSlice(allocator, " DROP COLUMN IF EXISTS ");
            try sql.appendSlice(allocator, fc.field_name);
            try sql.appendSlice(allocator, ";\n");
        },
        .remove => {
            // Rollback: ADD the removed column back
            if (fc.old_field) |field| {
                try sql.appendSlice(allocator, "ALTER TABLE ");
                try sql.appendSlice(allocator, table_name);
                try sql.appendSlice(allocator, " ADD COLUMN ");
                try sql.appendSlice(allocator, field.name);
                try sql.appendSlice(allocator, " ");
                try sql.appendSlice(allocator, fieldTypeToPgType(field.type));
                try sql.appendSlice(allocator, ";\n");
            }
        },
        .modify => {
            // Rollback: Restore old field properties
            if (fc.old_field) |old_field| {
                const new_field = fc.new_field orelse return;

                if (!std.mem.eql(u8, old_field.type, new_field.type)) {
                    try sql.appendSlice(allocator, "ALTER TABLE ");
                    try sql.appendSlice(allocator, table_name);
                    try sql.appendSlice(allocator, " ALTER COLUMN ");
                    try sql.appendSlice(allocator, old_field.name);
                    try sql.appendSlice(allocator, " TYPE ");
                    try sql.appendSlice(allocator, fieldTypeToPgType(old_field.type));
                    try sql.appendSlice(allocator, ";\n");
                }
            }
        },
    }
}

/// Migration file info for tracking generated files
pub const MigrationFile = struct {
    filename: []const u8,
    sql_up: []const u8,
    sql_down: []const u8,
};

/// Write incremental migration files - one file per change as per the plan
/// Returns the list of generated migration filenames
pub fn writeIncrementalMigrationFiles(
    allocator: std.mem.Allocator,
    schema_diff: SchemaDiff,
    output_dir: []const u8,
) ![]const []const u8 {
    if (!schema_diff.has_changes) {
        return &.{};
    }

    // Create migrations directory
    std.fs.cwd().makePath(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var generated_files = std.ArrayList([]const u8){};
    errdefer {
        for (generated_files.items) |f| allocator.free(f);
        generated_files.deinit(allocator);
    }

    const base_timestamp = std.time.timestamp();
    var sequence: u32 = 0;

    // Process each table change
    for (schema_diff.table_changes) |tc| {
        switch (tc.change_type) {
            .add => {
                // New table: Generate CREATE TABLE file
                if (tc.new_table) |table| {
                    const timestamp = base_timestamp + sequence;
                    sequence += 1;

                    const migration_name = try std.fmt.allocPrint(allocator, "create_{s}", .{table.name});
                    defer allocator.free(migration_name);

                    // Generate up SQL
                    var up_sql = std.ArrayList(u8){};
                    defer up_sql.deinit(allocator);

                    try up_sql.appendSlice(allocator, "-- Migration: create_");
                    try up_sql.appendSlice(allocator, table.name);
                    try up_sql.appendSlice(allocator, "\n-- Table: ");
                    try up_sql.appendSlice(allocator, table.name);
                    try up_sql.appendSlice(allocator, "\n-- Type: create_table\n\n");
                    try up_sql.appendSlice(allocator, "CREATE TABLE IF NOT EXISTS ");
                    try up_sql.appendSlice(allocator, table.name);
                    try up_sql.appendSlice(allocator, " (\n");

                    for (table.fields, 0..) |field, i| {
                        try generateFieldSnapshotSQL(allocator, &up_sql, field);
                        if (i < table.fields.len - 1) {
                            try up_sql.appendSlice(allocator, ",\n");
                        } else {
                            try up_sql.appendSlice(allocator, "\n");
                        }
                    }
                    try up_sql.appendSlice(allocator, ");\n");

                    // Generate down SQL
                    var down_sql = std.ArrayList(u8){};
                    defer down_sql.deinit(allocator);

                    try down_sql.appendSlice(allocator, "-- Rollback: create_");
                    try down_sql.appendSlice(allocator, table.name);
                    try down_sql.appendSlice(allocator, "\n\nDROP TABLE IF EXISTS ");
                    try down_sql.appendSlice(allocator, table.name);
                    try down_sql.appendSlice(allocator, " CASCADE;\n");

                    // Write files
                    const up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(up_filename);

                    const up_file = try std.fs.cwd().createFile(up_filename, .{});
                    defer up_file.close();
                    try up_file.writeAll(up_sql.items);

                    const down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(down_filename);

                    const down_file = try std.fs.cwd().createFile(down_filename, .{});
                    defer down_file.close();
                    try down_file.writeAll(down_sql.items);

                    // Track generated file
                    const tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, migration_name });
                    try generated_files.append(allocator, tracked_name);

                    // Generate separate files for indexes
                    for (table.indexes) |idx| {
                        const idx_timestamp = base_timestamp + sequence;
                        sequence += 1;

                        const idx_migration_name = try std.fmt.allocPrint(allocator, "{s}_add_index_{s}", .{ table.name, idx.name });
                        defer allocator.free(idx_migration_name);

                        var idx_up_sql = std.ArrayList(u8){};
                        defer idx_up_sql.deinit(allocator);

                        try idx_up_sql.appendSlice(allocator, "-- Migration: ");
                        try idx_up_sql.appendSlice(allocator, idx_migration_name);
                        try idx_up_sql.appendSlice(allocator, "\n-- Table: ");
                        try idx_up_sql.appendSlice(allocator, table.name);
                        try idx_up_sql.appendSlice(allocator, "\n-- Type: add_index\n\n");
                        try generateIndexSQL(allocator, &idx_up_sql, table.name, idx);

                        var idx_down_sql = std.ArrayList(u8){};
                        defer idx_down_sql.deinit(allocator);

                        try idx_down_sql.appendSlice(allocator, "-- Rollback: ");
                        try idx_down_sql.appendSlice(allocator, idx_migration_name);
                        try idx_down_sql.appendSlice(allocator, "\n\nDROP INDEX IF EXISTS ");
                        try idx_down_sql.appendSlice(allocator, idx.name);
                        try idx_down_sql.appendSlice(allocator, ";\n");

                        const idx_up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, idx_timestamp, idx_migration_name });
                        defer allocator.free(idx_up_filename);

                        const idx_up_file = try std.fs.cwd().createFile(idx_up_filename, .{});
                        defer idx_up_file.close();
                        try idx_up_file.writeAll(idx_up_sql.items);

                        const idx_down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, idx_timestamp, idx_migration_name });
                        defer allocator.free(idx_down_filename);

                        const idx_down_file = try std.fs.cwd().createFile(idx_down_filename, .{});
                        defer idx_down_file.close();
                        try idx_down_file.writeAll(idx_down_sql.items);

                        const idx_tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ idx_timestamp, idx_migration_name });
                        try generated_files.append(allocator, idx_tracked_name);
                    }

                    // Generate separate files for foreign keys
                    for (table.relationships) |rel| {
                        // Only many_to_one and one_to_one create FK constraints
                        if (!std.mem.eql(u8, rel.relationship_type, "many_to_one") and
                            !std.mem.eql(u8, rel.relationship_type, "one_to_one"))
                        {
                            continue;
                        }

                        const fk_timestamp = base_timestamp + sequence;
                        sequence += 1;

                        const fk_migration_name = try std.fmt.allocPrint(allocator, "{s}_add_fk_{s}", .{ table.name, rel.column });
                        defer allocator.free(fk_migration_name);

                        var fk_up_sql = std.ArrayList(u8){};
                        defer fk_up_sql.deinit(allocator);

                        try fk_up_sql.appendSlice(allocator, "-- Migration: ");
                        try fk_up_sql.appendSlice(allocator, fk_migration_name);
                        try fk_up_sql.appendSlice(allocator, "\n-- Table: ");
                        try fk_up_sql.appendSlice(allocator, table.name);
                        try fk_up_sql.appendSlice(allocator, "\n-- Type: add_foreign_key\n\n");
                        try generateAddForeignKeySQL(allocator, &fk_up_sql, table.name, rel);

                        var fk_down_sql = std.ArrayList(u8){};
                        defer fk_down_sql.deinit(allocator);

                        try fk_down_sql.appendSlice(allocator, "-- Rollback: ");
                        try fk_down_sql.appendSlice(allocator, fk_migration_name);
                        try fk_down_sql.appendSlice(allocator, "\n\nALTER TABLE ");
                        try fk_down_sql.appendSlice(allocator, table.name);
                        try fk_down_sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS fk_");
                        try fk_down_sql.appendSlice(allocator, table.name);
                        try fk_down_sql.appendSlice(allocator, "_");
                        try fk_down_sql.appendSlice(allocator, rel.name);
                        try fk_down_sql.appendSlice(allocator, ";\n");

                        const fk_up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, fk_timestamp, fk_migration_name });
                        defer allocator.free(fk_up_filename);

                        const fk_up_file = try std.fs.cwd().createFile(fk_up_filename, .{});
                        defer fk_up_file.close();
                        try fk_up_file.writeAll(fk_up_sql.items);

                        const fk_down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, fk_timestamp, fk_migration_name });
                        defer allocator.free(fk_down_filename);

                        const fk_down_file = try std.fs.cwd().createFile(fk_down_filename, .{});
                        defer fk_down_file.close();
                        try fk_down_file.writeAll(fk_down_sql.items);

                        const fk_tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ fk_timestamp, fk_migration_name });
                        try generated_files.append(allocator, fk_tracked_name);
                    }
                }
            },
            .remove => {
                // Drop table
                const timestamp = base_timestamp + sequence;
                sequence += 1;

                const migration_name = try std.fmt.allocPrint(allocator, "drop_{s}", .{tc.table_name});
                defer allocator.free(migration_name);

                var up_sql = std.ArrayList(u8){};
                defer up_sql.deinit(allocator);

                try up_sql.appendSlice(allocator, "-- Migration: drop_");
                try up_sql.appendSlice(allocator, tc.table_name);
                try up_sql.appendSlice(allocator, "\n-- Table: ");
                try up_sql.appendSlice(allocator, tc.table_name);
                try up_sql.appendSlice(allocator, "\n-- Type: drop_table\n\n");
                try up_sql.appendSlice(allocator, "DROP TABLE IF EXISTS ");
                try up_sql.appendSlice(allocator, tc.table_name);
                try up_sql.appendSlice(allocator, " CASCADE;\n");

                var down_sql = std.ArrayList(u8){};
                defer down_sql.deinit(allocator);

                try down_sql.appendSlice(allocator, "-- Rollback: drop_");
                try down_sql.appendSlice(allocator, tc.table_name);
                try down_sql.appendSlice(allocator, "\n\n-- WARNING: Cannot recreate table without schema info\n");
                try down_sql.appendSlice(allocator, "-- Original table structure was not preserved\n");

                // If we have old_table info, recreate it
                if (tc.old_table) |table| {
                    try down_sql.appendSlice(allocator, "CREATE TABLE IF NOT EXISTS ");
                    try down_sql.appendSlice(allocator, table.name);
                    try down_sql.appendSlice(allocator, " (\n");

                    for (table.fields, 0..) |field, i| {
                        try generateFieldSnapshotSQL(allocator, &down_sql, field);
                        if (i < table.fields.len - 1) {
                            try down_sql.appendSlice(allocator, ",\n");
                        } else {
                            try down_sql.appendSlice(allocator, "\n");
                        }
                    }
                    try down_sql.appendSlice(allocator, ");\n");
                }

                const up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, timestamp, migration_name });
                defer allocator.free(up_filename);

                const up_file = try std.fs.cwd().createFile(up_filename, .{});
                defer up_file.close();
                try up_file.writeAll(up_sql.items);

                const down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, timestamp, migration_name });
                defer allocator.free(down_filename);

                const down_file = try std.fs.cwd().createFile(down_filename, .{});
                defer down_file.close();
                try down_file.writeAll(down_sql.items);

                const tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, migration_name });
                try generated_files.append(allocator, tracked_name);
            },
            .modify => {
                // Generate separate files for each field change
                for (tc.field_changes) |fc| {
                    const timestamp = base_timestamp + sequence;
                    sequence += 1;

                    const migration_name = switch (fc.change_type) {
                        .add => try std.fmt.allocPrint(allocator, "{s}_add_column_{s}", .{ tc.table_name, fc.field_name }),
                        .remove => try std.fmt.allocPrint(allocator, "{s}_drop_column_{s}", .{ tc.table_name, fc.field_name }),
                        .modify => try std.fmt.allocPrint(allocator, "{s}_alter_column_{s}", .{ tc.table_name, fc.field_name }),
                    };
                    defer allocator.free(migration_name);

                    var up_sql = std.ArrayList(u8){};
                    defer up_sql.deinit(allocator);

                    try up_sql.appendSlice(allocator, "-- Migration: ");
                    try up_sql.appendSlice(allocator, migration_name);
                    try up_sql.appendSlice(allocator, "\n-- Table: ");
                    try up_sql.appendSlice(allocator, tc.table_name);
                    try up_sql.appendSlice(allocator, "\n-- Type: ");
                    switch (fc.change_type) {
                        .add => try up_sql.appendSlice(allocator, "add_column"),
                        .remove => try up_sql.appendSlice(allocator, "drop_column"),
                        .modify => try up_sql.appendSlice(allocator, "alter_column"),
                    }
                    try up_sql.appendSlice(allocator, "\n\n");
                    try generateFieldChangeSQL(allocator, &up_sql, tc.table_name, fc);

                    var down_sql = std.ArrayList(u8){};
                    defer down_sql.deinit(allocator);

                    try down_sql.appendSlice(allocator, "-- Rollback: ");
                    try down_sql.appendSlice(allocator, migration_name);
                    try down_sql.appendSlice(allocator, "\n\n");
                    try generateRollbackFieldChangeSQL(allocator, &down_sql, tc.table_name, fc);

                    const up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(up_filename);

                    const up_file = try std.fs.cwd().createFile(up_filename, .{});
                    defer up_file.close();
                    try up_file.writeAll(up_sql.items);

                    const down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(down_filename);

                    const down_file = try std.fs.cwd().createFile(down_filename, .{});
                    defer down_file.close();
                    try down_file.writeAll(down_sql.items);

                    const tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, migration_name });
                    try generated_files.append(allocator, tracked_name);
                }

                // Generate separate files for each index change
                for (tc.index_changes) |ic| {
                    const timestamp = base_timestamp + sequence;
                    sequence += 1;

                    const migration_name = switch (ic.change_type) {
                        .add => try std.fmt.allocPrint(allocator, "{s}_add_index_{s}", .{ tc.table_name, ic.index_name }),
                        .remove => try std.fmt.allocPrint(allocator, "{s}_drop_index_{s}", .{ tc.table_name, ic.index_name }),
                        .modify => try std.fmt.allocPrint(allocator, "{s}_alter_index_{s}", .{ tc.table_name, ic.index_name }),
                    };
                    defer allocator.free(migration_name);

                    var up_sql = std.ArrayList(u8){};
                    defer up_sql.deinit(allocator);

                    try up_sql.appendSlice(allocator, "-- Migration: ");
                    try up_sql.appendSlice(allocator, migration_name);
                    try up_sql.appendSlice(allocator, "\n-- Table: ");
                    try up_sql.appendSlice(allocator, tc.table_name);
                    try up_sql.appendSlice(allocator, "\n-- Type: index_change\n\n");
                    try generateIndexChangeSQL(allocator, &up_sql, tc.table_name, ic);

                    var down_sql = std.ArrayList(u8){};
                    defer down_sql.deinit(allocator);

                    try down_sql.appendSlice(allocator, "-- Rollback: ");
                    try down_sql.appendSlice(allocator, migration_name);
                    try down_sql.appendSlice(allocator, "\n\n");

                    // Reverse the index change
                    switch (ic.change_type) {
                        .add => {
                            try down_sql.appendSlice(allocator, "DROP INDEX IF EXISTS ");
                            try down_sql.appendSlice(allocator, ic.index_name);
                            try down_sql.appendSlice(allocator, ";\n");
                        },
                        .remove => {
                            if (ic.old_index) |idx| {
                                try generateIndexSQL(allocator, &down_sql, tc.table_name, idx);
                            }
                        },
                        .modify => {
                            if (ic.old_index) |idx| {
                                try down_sql.appendSlice(allocator, "DROP INDEX IF EXISTS ");
                                try down_sql.appendSlice(allocator, ic.index_name);
                                try down_sql.appendSlice(allocator, ";\n");
                                try generateIndexSQL(allocator, &down_sql, tc.table_name, idx);
                            }
                        },
                    }

                    const up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(up_filename);

                    const up_file = try std.fs.cwd().createFile(up_filename, .{});
                    defer up_file.close();
                    try up_file.writeAll(up_sql.items);

                    const down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(down_filename);

                    const down_file = try std.fs.cwd().createFile(down_filename, .{});
                    defer down_file.close();
                    try down_file.writeAll(down_sql.items);

                    const tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, migration_name });
                    try generated_files.append(allocator, tracked_name);
                }

                // Generate separate files for each relationship change
                for (tc.relationship_changes) |rc| {
                    const timestamp = base_timestamp + sequence;
                    sequence += 1;

                    const migration_name = switch (rc.change_type) {
                        .add => try std.fmt.allocPrint(allocator, "{s}_add_fk_{s}", .{ tc.table_name, rc.relationship_name }),
                        .remove => try std.fmt.allocPrint(allocator, "{s}_drop_fk_{s}", .{ tc.table_name, rc.relationship_name }),
                        .modify => try std.fmt.allocPrint(allocator, "{s}_alter_fk_{s}", .{ tc.table_name, rc.relationship_name }),
                    };
                    defer allocator.free(migration_name);

                    var up_sql = std.ArrayList(u8){};
                    defer up_sql.deinit(allocator);

                    try up_sql.appendSlice(allocator, "-- Migration: ");
                    try up_sql.appendSlice(allocator, migration_name);
                    try up_sql.appendSlice(allocator, "\n-- Table: ");
                    try up_sql.appendSlice(allocator, tc.table_name);
                    try up_sql.appendSlice(allocator, "\n-- Type: foreign_key_change\n\n");
                    try generateRelationshipChangeSQL(allocator, &up_sql, tc.table_name, rc);

                    var down_sql = std.ArrayList(u8){};
                    defer down_sql.deinit(allocator);

                    try down_sql.appendSlice(allocator, "-- Rollback: ");
                    try down_sql.appendSlice(allocator, migration_name);
                    try down_sql.appendSlice(allocator, "\n\n");

                    // Reverse the relationship change
                    switch (rc.change_type) {
                        .add => {
                            try down_sql.appendSlice(allocator, "ALTER TABLE ");
                            try down_sql.appendSlice(allocator, tc.table_name);
                            try down_sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS fk_");
                            try down_sql.appendSlice(allocator, tc.table_name);
                            try down_sql.appendSlice(allocator, "_");
                            try down_sql.appendSlice(allocator, rc.relationship_name);
                            try down_sql.appendSlice(allocator, ";\n");
                        },
                        .remove => {
                            if (rc.old_relationship) |rel| {
                                try generateAddForeignKeySQL(allocator, &down_sql, tc.table_name, rel);
                            }
                        },
                        .modify => {
                            if (rc.old_relationship) |rel| {
                                try down_sql.appendSlice(allocator, "ALTER TABLE ");
                                try down_sql.appendSlice(allocator, tc.table_name);
                                try down_sql.appendSlice(allocator, " DROP CONSTRAINT IF EXISTS fk_");
                                try down_sql.appendSlice(allocator, tc.table_name);
                                try down_sql.appendSlice(allocator, "_");
                                try down_sql.appendSlice(allocator, rc.relationship_name);
                                try down_sql.appendSlice(allocator, ";\n");
                                try generateAddForeignKeySQL(allocator, &down_sql, tc.table_name, rel);
                            }
                        },
                    }

                    const up_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(up_filename);

                    const up_file = try std.fs.cwd().createFile(up_filename, .{});
                    defer up_file.close();
                    try up_file.writeAll(up_sql.items);

                    const down_filename = try std.fmt.allocPrint(allocator, "{s}/{d}_{s}_down.sql", .{ output_dir, timestamp, migration_name });
                    defer allocator.free(down_filename);

                    const down_file = try std.fs.cwd().createFile(down_filename, .{});
                    defer down_file.close();
                    try down_file.writeAll(down_sql.items);

                    const tracked_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, migration_name });
                    try generated_files.append(allocator, tracked_name);
                }
            },
        }
    }

    return generated_files.toOwnedSlice(allocator);
}
