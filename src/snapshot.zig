// Snapshot system for schema versioning
// Serializes TableSchema to JSON for comparison and migration generation

const std = @import("std");
const schema = @import("schema.zig");
const TableSchema = @import("table.zig").TableSchema;

const Field = schema.Field;
const FieldType = schema.FieldType;
const Index = schema.Index;
const Relationship = schema.Relationship;
const HasManyRelationship = schema.HasManyRelationship;
const InputMode = schema.InputMode;
const AutoGenerateType = schema.AutoGenerateType;
const OnDeleteAction = schema.OnDeleteAction;
const OnUpdateAction = schema.OnUpdateAction;
const RelationshipType = schema.RelationshipType;

/// Snapshot of a single table's schema
pub const TableSnapshot = struct {
    name: []const u8,
    fields: []const FieldSnapshot,
    indexes: []const IndexSnapshot,
    relationships: []const RelationshipSnapshot,
    has_many: []const HasManySnapshot,
};

/// Snapshot of a field
pub const FieldSnapshot = struct {
    name: []const u8,
    type: []const u8, // String representation of FieldType
    primary_key: bool,
    unique: bool,
    not_null: bool,
    default_value: ?[]const u8,
    auto_generated: bool,
    auto_generate_type: []const u8,
};

/// Snapshot of an index
pub const IndexSnapshot = struct {
    name: []const u8,
    columns: []const []const u8,
    unique: bool,
};

/// Snapshot of a relationship (foreign key)
pub const RelationshipSnapshot = struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8,
    relationship_type: []const u8,
    on_delete: []const u8,
    on_update: []const u8,
};

/// Snapshot of a hasMany relationship
pub const HasManySnapshot = struct {
    name: []const u8,
    foreign_table: []const u8,
    foreign_column: []const u8,
    local_column: []const u8,
};

/// Free a single TableSnapshot's allocated memory
fn freeTableSnapshotInternal(allocator: std.mem.Allocator, table: TableSnapshot) void {
    for (table.fields) |f| {
        allocator.free(f.name);
        if (f.default_value) |dv| allocator.free(dv);
    }
    allocator.free(table.fields);

    for (table.indexes) |idx| {
        for (idx.columns) |col| allocator.free(col);
        allocator.free(idx.columns);
        allocator.free(idx.name);
    }
    allocator.free(table.indexes);

    for (table.relationships) |rel| {
        allocator.free(rel.name);
        allocator.free(rel.column);
        allocator.free(rel.references_table);
        allocator.free(rel.references_column);
    }
    allocator.free(table.relationships);

    for (table.has_many) |hm| {
        allocator.free(hm.name);
        allocator.free(hm.foreign_table);
        allocator.free(hm.foreign_column);
        allocator.free(hm.local_column);
    }
    allocator.free(table.has_many);

    allocator.free(table.name);
}

/// Complete database snapshot containing all tables
pub const DatabaseSnapshot = struct {
    version: u32 = 1,
    created_at: i64,
    tables: []const TableSnapshot,

    /// Free all allocated memory in the snapshot
    pub fn deinit(self: DatabaseSnapshot, allocator: std.mem.Allocator) void {
        for (self.tables) |table| {
            freeTableSnapshotInternal(allocator, table);
        }
        allocator.free(self.tables);
    }
};

/// Convert FieldType enum to string for JSON
fn fieldTypeToString(ft: FieldType) []const u8 {
    return @tagName(ft);
}

/// Convert AutoGenerateType enum to string for JSON
fn autoGenTypeToString(agt: AutoGenerateType) []const u8 {
    return @tagName(agt);
}

/// Convert RelationshipType enum to string for JSON
fn relTypeToString(rt: RelationshipType) []const u8 {
    return @tagName(rt);
}

/// Convert OnDeleteAction enum to string for JSON
fn onDeleteToString(od: OnDeleteAction) []const u8 {
    return @tagName(od);
}

/// Convert OnUpdateAction enum to string for JSON
fn onUpdateToString(ou: OnUpdateAction) []const u8 {
    return @tagName(ou);
}

/// Create a snapshot from a TableSchema
pub fn createTableSnapshot(allocator: std.mem.Allocator, table: TableSchema) !TableSnapshot {
    // Convert fields
    var fields = std.ArrayList(FieldSnapshot){};
    errdefer {
        for (fields.items) |f| {
            allocator.free(f.name);
            if (f.default_value) |dv| allocator.free(dv);
        }
        fields.deinit(allocator);
    }

    for (table.fields.items) |field| {
        const name = try allocator.dupe(u8, field.name);
        errdefer allocator.free(name);

        const default_value = if (field.default_value) |dv| try allocator.dupe(u8, dv) else null;

        try fields.append(allocator, .{
            .name = name,
            .type = fieldTypeToString(field.type),
            .primary_key = field.primary_key,
            .unique = field.unique,
            .not_null = field.not_null,
            .default_value = default_value,
            .auto_generated = field.auto_generated,
            .auto_generate_type = autoGenTypeToString(field.auto_generate_type),
        });
    }

    // Convert indexes
    var indexes = std.ArrayList(IndexSnapshot){};
    errdefer {
        for (indexes.items) |idx| {
            for (idx.columns) |col| allocator.free(col);
            allocator.free(idx.columns);
            allocator.free(idx.name);
        }
        indexes.deinit(allocator);
    }

    for (table.indexes.items) |idx| {
        // Dupe the columns array
        var cols = std.ArrayList([]const u8){};
        errdefer {
            for (cols.items) |col| allocator.free(col);
            cols.deinit(allocator);
        }

        for (idx.columns) |col| {
            try cols.append(allocator, try allocator.dupe(u8, col));
        }

        const name = try allocator.dupe(u8, idx.name);
        errdefer allocator.free(name);

        const columns = try cols.toOwnedSlice(allocator);

        try indexes.append(allocator, .{
            .name = name,
            .columns = columns,
            .unique = idx.unique,
        });
    }

    // Convert relationships
    var rels = std.ArrayList(RelationshipSnapshot){};
    errdefer {
        for (rels.items) |rel| {
            allocator.free(rel.name);
            allocator.free(rel.column);
            allocator.free(rel.references_table);
            allocator.free(rel.references_column);
        }
        rels.deinit(allocator);
    }

    for (table.relationships.items) |rel| {
        const name = try allocator.dupe(u8, rel.name);
        errdefer allocator.free(name);

        const column = try allocator.dupe(u8, rel.column);
        errdefer allocator.free(column);

        const references_table = try allocator.dupe(u8, rel.references_table);
        errdefer allocator.free(references_table);

        const references_column = try allocator.dupe(u8, rel.references_column);

        try rels.append(allocator, .{
            .name = name,
            .column = column,
            .references_table = references_table,
            .references_column = references_column,
            .relationship_type = relTypeToString(rel.relationship_type),
            .on_delete = onDeleteToString(rel.on_delete),
            .on_update = onUpdateToString(rel.on_update),
        });
    }

    // Convert hasMany relationships
    var has_many = std.ArrayList(HasManySnapshot){};
    errdefer {
        for (has_many.items) |hm| {
            allocator.free(hm.name);
            allocator.free(hm.foreign_table);
            allocator.free(hm.foreign_column);
            allocator.free(hm.local_column);
        }
        has_many.deinit(allocator);
    }

    for (table.has_many_relationships.items) |hm| {
        const name = try allocator.dupe(u8, hm.name);
        errdefer allocator.free(name);

        const foreign_table = try allocator.dupe(u8, hm.foreign_table);
        errdefer allocator.free(foreign_table);

        const foreign_column = try allocator.dupe(u8, hm.foreign_column);
        errdefer allocator.free(foreign_column);

        const local_column = try allocator.dupe(u8, hm.local_column);

        try has_many.append(allocator, .{
            .name = name,
            .foreign_table = foreign_table,
            .foreign_column = foreign_column,
            .local_column = local_column,
        });
    }

    const table_name = try allocator.dupe(u8, table.name);

    return .{
        .name = table_name,
        .fields = try fields.toOwnedSlice(allocator),
        .indexes = try indexes.toOwnedSlice(allocator),
        .relationships = try rels.toOwnedSlice(allocator),
        .has_many = try has_many.toOwnedSlice(allocator),
    };
}

/// Create a database snapshot from multiple TableSchemas
pub fn createDatabaseSnapshot(allocator: std.mem.Allocator, tables: []TableSchema) !DatabaseSnapshot {
    var table_snapshots = std.ArrayList(TableSnapshot){};
    errdefer {
        for (table_snapshots.items) |ts| {
            freeTableSnapshotInternal(allocator, ts);
        }
        table_snapshots.deinit(allocator);
    }

    for (tables) |table| {
        try table_snapshots.append(allocator, try createTableSnapshot(allocator, table));
    }

    return .{
        .version = 1,
        .created_at = std.time.timestamp(),
        .tables = try table_snapshots.toOwnedSlice(allocator),
    };
}

/// Serialize a DatabaseSnapshot to JSON string
pub fn toJson(allocator: std.mem.Allocator, snapshot: DatabaseSnapshot) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(snapshot, .{
        .whitespace = .indent_2,
    })});
}

/// Parse a DatabaseSnapshot from JSON string
pub fn fromJson(allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(DatabaseSnapshot) {
    return std.json.parseFromSlice(DatabaseSnapshot, allocator, json_str, .{
        .allocate = .alloc_always,
    });
}

/// Save snapshot to file
pub fn saveSnapshot(allocator: std.mem.Allocator, snapshot: DatabaseSnapshot, file_path: []const u8) !void {
    const json = try toJson(allocator, snapshot);
    defer allocator.free(json);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(json);
}

/// Load snapshot from file
pub fn loadSnapshot(allocator: std.mem.Allocator, file_path: []const u8) !?std.json.Parsed(DatabaseSnapshot) {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    return try fromJson(allocator, content);
}

// ============================================================================
// Tests
// ============================================================================

test "create table snapshot" {
    const allocator = std.testing.allocator;

    var table = try TableSchema.createEmpty("users", allocator);
    defer table.deinit();

    table.uuid(.{ .name = "id", .primary_key = true });
    table.string(.{ .name = "email", .unique = true });
    table.string(.{ .name = "name" });

    const snapshot_data = try createTableSnapshot(allocator, table);

    try std.testing.expectEqualStrings("users", snapshot_data.name);
    try std.testing.expectEqual(@as(usize, 3), snapshot_data.fields.len);
    try std.testing.expectEqualStrings("id", snapshot_data.fields[0].name);
    try std.testing.expectEqualStrings("email", snapshot_data.fields[1].name);
    try std.testing.expectEqualStrings("name", snapshot_data.fields[2].name);

    // Free snapshot memory manually (single table, not from createDatabaseSnapshot)
    for (snapshot_data.fields) |f| {
        allocator.free(f.name);
        if (f.default_value) |dv| allocator.free(dv);
    }
    allocator.free(snapshot_data.fields);
    allocator.free(snapshot_data.indexes);
    allocator.free(snapshot_data.relationships);
    allocator.free(snapshot_data.has_many);
    allocator.free(snapshot_data.name);
}

test "serialize and deserialize snapshot" {
    const allocator = std.testing.allocator;

    var table = try TableSchema.createEmpty("posts", allocator);
    defer table.deinit();

    table.uuid(.{ .name = "id", .primary_key = true });
    table.string(.{ .name = "title" });
    table.string(.{ .name = "content" });

    const table_snapshot = try createTableSnapshot(allocator, table);
    defer {
        for (table_snapshot.fields) |f| {
            allocator.free(f.name);
            if (f.default_value) |dv| allocator.free(dv);
        }
        allocator.free(table_snapshot.fields);
        allocator.free(table_snapshot.indexes);
        allocator.free(table_snapshot.relationships);
        allocator.free(table_snapshot.has_many);
        allocator.free(table_snapshot.name);
    }

    // Create a database snapshot with our table
    const db_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{table_snapshot},
    };

    // Serialize to JSON
    const json = try toJson(allocator, db_snapshot);
    defer allocator.free(json);

    // Deserialize from JSON
    var parsed = try fromJson(allocator, json);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.tables.len);
    try std.testing.expectEqualStrings("posts", parsed.value.tables[0].name);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.tables[0].fields.len);
}
