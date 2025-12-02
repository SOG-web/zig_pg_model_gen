// Diff engine for comparing schema snapshots
// Detects added, removed, and modified tables/fields/indexes/relationships

const std = @import("std");
const snapshot = @import("snapshot.zig");

const TableSnapshot = snapshot.TableSnapshot;
const FieldSnapshot = snapshot.FieldSnapshot;
const IndexSnapshot = snapshot.IndexSnapshot;
const RelationshipSnapshot = snapshot.RelationshipSnapshot;
const HasManySnapshot = snapshot.HasManySnapshot;
const DatabaseSnapshot = snapshot.DatabaseSnapshot;

// ============================================================================
// Change Types
// ============================================================================

pub const ChangeType = enum {
    add,
    remove,
    modify,
};

pub const FieldChange = struct {
    change_type: ChangeType,
    field_name: []const u8,
    old_field: ?FieldSnapshot = null,
    new_field: ?FieldSnapshot = null,
};

pub const IndexChange = struct {
    change_type: ChangeType,
    index_name: []const u8,
    old_index: ?IndexSnapshot = null,
    new_index: ?IndexSnapshot = null,
};

pub const RelationshipChange = struct {
    change_type: ChangeType,
    relationship_name: []const u8,
    old_relationship: ?RelationshipSnapshot = null,
    new_relationship: ?RelationshipSnapshot = null,
};

pub const TableChange = struct {
    change_type: ChangeType,
    table_name: []const u8,
    old_table: ?TableSnapshot = null,
    new_table: ?TableSnapshot = null,
    // Detailed changes for modified tables
    field_changes: []const FieldChange = &.{},
    index_changes: []const IndexChange = &.{},
    relationship_changes: []const RelationshipChange = &.{},
};

pub const SchemaDiff = struct {
    table_changes: []const TableChange,
    has_changes: bool,

    pub fn deinit(self: *const SchemaDiff, allocator: std.mem.Allocator) void {
        for (self.table_changes) |tc| {
            allocator.free(tc.field_changes);
            allocator.free(tc.index_changes);
            allocator.free(tc.relationship_changes);
        }
        allocator.free(self.table_changes);
    }
};

// ============================================================================
// Diff Functions
// ============================================================================

/// Compare two database snapshots and return the differences
pub fn diffSnapshots(
    allocator: std.mem.Allocator,
    old_snapshot: ?DatabaseSnapshot,
    new_snapshot: DatabaseSnapshot,
) !SchemaDiff {
    var table_changes = std.ArrayList(TableChange){};

    const old_tables = if (old_snapshot) |os| os.tables else &[_]TableSnapshot{};

    // Find added and modified tables
    for (new_snapshot.tables) |new_table| {
        if (findTable(old_tables, new_table.name)) |old_table| {
            // Table exists in both - check for modifications
            const diff = try diffTables(allocator, old_table, new_table);
            if (diff.field_changes.len > 0 or
                diff.index_changes.len > 0 or
                diff.relationship_changes.len > 0)
            {
                try table_changes.append(allocator, .{
                    .change_type = .modify,
                    .table_name = new_table.name,
                    .old_table = old_table,
                    .new_table = new_table,
                    .field_changes = diff.field_changes,
                    .index_changes = diff.index_changes,
                    .relationship_changes = diff.relationship_changes,
                });
            }
        } else {
            // New table
            try table_changes.append(allocator, .{
                .change_type = .add,
                .table_name = new_table.name,
                .new_table = new_table,
            });
        }
    }

    // Find removed tables
    for (old_tables) |old_table| {
        if (findTable(new_snapshot.tables, old_table.name) == null) {
            try table_changes.append(allocator, .{
                .change_type = .remove,
                .table_name = old_table.name,
                .old_table = old_table,
            });
        }
    }

    const changes = try table_changes.toOwnedSlice(allocator);
    return .{
        .table_changes = changes,
        .has_changes = changes.len > 0,
    };
}

/// Find a table by name in a slice
fn findTable(tables: []const TableSnapshot, name: []const u8) ?TableSnapshot {
    for (tables) |table| {
        if (std.mem.eql(u8, table.name, name)) {
            return table;
        }
    }
    return null;
}

/// Compare two tables and return field/index/relationship changes
fn diffTables(
    allocator: std.mem.Allocator,
    old_table: TableSnapshot,
    new_table: TableSnapshot,
) !struct {
    field_changes: []const FieldChange,
    index_changes: []const IndexChange,
    relationship_changes: []const RelationshipChange,
} {
    return .{
        .field_changes = try diffFields(allocator, old_table.fields, new_table.fields),
        .index_changes = try diffIndexes(allocator, old_table.indexes, new_table.indexes),
        .relationship_changes = try diffRelationships(allocator, old_table.relationships, new_table.relationships),
    };
}

/// Compare fields between old and new table
fn diffFields(
    allocator: std.mem.Allocator,
    old_fields: []const FieldSnapshot,
    new_fields: []const FieldSnapshot,
) ![]const FieldChange {
    var changes = std.ArrayList(FieldChange){};

    // Find added and modified fields
    for (new_fields) |new_field| {
        if (findField(old_fields, new_field.name)) |old_field| {
            // Field exists - check if modified
            if (!fieldsEqual(old_field, new_field)) {
                try changes.append(allocator, .{
                    .change_type = .modify,
                    .field_name = new_field.name,
                    .old_field = old_field,
                    .new_field = new_field,
                });
            }
        } else {
            // New field
            try changes.append(allocator, .{
                .change_type = .add,
                .field_name = new_field.name,
                .new_field = new_field,
            });
        }
    }

    // Find removed fields
    for (old_fields) |old_field| {
        if (findField(new_fields, old_field.name) == null) {
            try changes.append(allocator, .{
                .change_type = .remove,
                .field_name = old_field.name,
                .old_field = old_field,
            });
        }
    }

    return changes.toOwnedSlice(allocator);
}

/// Find a field by name
fn findField(fields: []const FieldSnapshot, name: []const u8) ?FieldSnapshot {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return field;
        }
    }
    return null;
}

/// Check if two fields are equal
fn fieldsEqual(a: FieldSnapshot, b: FieldSnapshot) bool {
    if (!std.mem.eql(u8, a.type, b.type)) return false;
    if (a.primary_key != b.primary_key) return false;
    if (a.unique != b.unique) return false;
    if (a.not_null != b.not_null) return false;
    if (a.auto_generated != b.auto_generated) return false;
    if (!std.mem.eql(u8, a.auto_generate_type, b.auto_generate_type)) return false;

    // Compare default values
    if (a.default_value) |adv| {
        if (b.default_value) |bdv| {
            if (!std.mem.eql(u8, adv, bdv)) return false;
        } else {
            return false;
        }
    } else if (b.default_value != null) {
        return false;
    }

    return true;
}

/// Compare indexes between old and new table
fn diffIndexes(
    allocator: std.mem.Allocator,
    old_indexes: []const IndexSnapshot,
    new_indexes: []const IndexSnapshot,
) ![]const IndexChange {
    var changes = std.ArrayList(IndexChange){};

    // Find added and modified indexes
    for (new_indexes) |new_index| {
        if (findIndex(old_indexes, new_index.name)) |old_index| {
            if (!indexesEqual(old_index, new_index)) {
                try changes.append(allocator, .{
                    .change_type = .modify,
                    .index_name = new_index.name,
                    .old_index = old_index,
                    .new_index = new_index,
                });
            }
        } else {
            try changes.append(allocator, .{
                .change_type = .add,
                .index_name = new_index.name,
                .new_index = new_index,
            });
        }
    }

    // Find removed indexes
    for (old_indexes) |old_index| {
        if (findIndex(new_indexes, old_index.name) == null) {
            try changes.append(allocator, .{
                .change_type = .remove,
                .index_name = old_index.name,
                .old_index = old_index,
            });
        }
    }

    return changes.toOwnedSlice(allocator);
}

/// Find an index by name
fn findIndex(indexes: []const IndexSnapshot, name: []const u8) ?IndexSnapshot {
    for (indexes) |index| {
        if (std.mem.eql(u8, index.name, name)) {
            return index;
        }
    }
    return null;
}

/// Check if two indexes are equal
fn indexesEqual(a: IndexSnapshot, b: IndexSnapshot) bool {
    if (a.unique != b.unique) return false;
    if (a.columns.len != b.columns.len) return false;
    for (a.columns, b.columns) |ac, bc| {
        if (!std.mem.eql(u8, ac, bc)) return false;
    }
    return true;
}

/// Compare relationships between old and new table
fn diffRelationships(
    allocator: std.mem.Allocator,
    old_rels: []const RelationshipSnapshot,
    new_rels: []const RelationshipSnapshot,
) ![]const RelationshipChange {
    var changes = std.ArrayList(RelationshipChange){};

    // Find added and modified relationships
    for (new_rels) |new_rel| {
        if (findRelationship(old_rels, new_rel.name)) |old_rel| {
            if (!relationshipsEqual(old_rel, new_rel)) {
                try changes.append(allocator, .{
                    .change_type = .modify,
                    .relationship_name = new_rel.name,
                    .old_relationship = old_rel,
                    .new_relationship = new_rel,
                });
            }
        } else {
            try changes.append(allocator, .{
                .change_type = .add,
                .relationship_name = new_rel.name,
                .new_relationship = new_rel,
            });
        }
    }

    // Find removed relationships
    for (old_rels) |old_rel| {
        if (findRelationship(new_rels, old_rel.name) == null) {
            try changes.append(allocator, .{
                .change_type = .remove,
                .relationship_name = old_rel.name,
                .old_relationship = old_rel,
            });
        }
    }

    return changes.toOwnedSlice(allocator);
}

/// Find a relationship by name
fn findRelationship(rels: []const RelationshipSnapshot, name: []const u8) ?RelationshipSnapshot {
    for (rels) |rel| {
        if (std.mem.eql(u8, rel.name, name)) {
            return rel;
        }
    }
    return null;
}

/// Check if two relationships are equal
fn relationshipsEqual(a: RelationshipSnapshot, b: RelationshipSnapshot) bool {
    if (!std.mem.eql(u8, a.column, b.column)) return false;
    if (!std.mem.eql(u8, a.references_table, b.references_table)) return false;
    if (!std.mem.eql(u8, a.references_column, b.references_column)) return false;
    if (!std.mem.eql(u8, a.relationship_type, b.relationship_type)) return false;
    if (!std.mem.eql(u8, a.on_delete, b.on_delete)) return false;
    if (!std.mem.eql(u8, a.on_update, b.on_update)) return false;
    return true;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Print a human-readable summary of the diff
pub fn printDiff(diff: SchemaDiff, writer: anytype) !void {
    if (!diff.has_changes) {
        try writer.writeAll("No schema changes detected.\n");
        return;
    }

    try writer.writeAll("Schema Changes:\n");
    try writer.writeAll("===============\n\n");

    for (diff.table_changes) |tc| {
        switch (tc.change_type) {
            .add => {
                try writer.print("+ CREATE TABLE {s}\n", .{tc.table_name});
                if (tc.new_table) |t| {
                    for (t.fields) |f| {
                        try writer.print("    + {s} ({s})\n", .{ f.name, f.type });
                    }
                }
            },
            .remove => {
                try writer.print("- DROP TABLE {s}\n", .{tc.table_name});
            },
            .modify => {
                try writer.print("~ ALTER TABLE {s}\n", .{tc.table_name});

                for (tc.field_changes) |fc| {
                    switch (fc.change_type) {
                        .add => try writer.print("    + ADD COLUMN {s}\n", .{fc.field_name}),
                        .remove => try writer.print("    - DROP COLUMN {s}\n", .{fc.field_name}),
                        .modify => try writer.print("    ~ ALTER COLUMN {s}\n", .{fc.field_name}),
                    }
                }

                for (tc.index_changes) |ic| {
                    switch (ic.change_type) {
                        .add => try writer.print("    + CREATE INDEX {s}\n", .{ic.index_name}),
                        .remove => try writer.print("    - DROP INDEX {s}\n", .{ic.index_name}),
                        .modify => try writer.print("    ~ ALTER INDEX {s}\n", .{ic.index_name}),
                    }
                }

                for (tc.relationship_changes) |rc| {
                    switch (rc.change_type) {
                        .add => try writer.print("    + ADD CONSTRAINT {s}\n", .{rc.relationship_name}),
                        .remove => try writer.print("    - DROP CONSTRAINT {s}\n", .{rc.relationship_name}),
                        .modify => try writer.print("    ~ ALTER CONSTRAINT {s}\n", .{rc.relationship_name}),
                    }
                }
            },
        }
        try writer.writeAll("\n");
    }
}

// ============================================================================
// Tests
// ============================================================================

test "detect new table" {
    const allocator = std.testing.allocator;

    const new_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "id",
                        .type = "uuid",
                        .primary_key = true,
                        .unique = false,
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const diff = try diffSnapshots(allocator, null, new_snapshot);
    defer diff.deinit(allocator);

    try std.testing.expect(diff.has_changes);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes.len);
    try std.testing.expectEqual(ChangeType.add, diff.table_changes[0].change_type);
    try std.testing.expectEqualStrings("users", diff.table_changes[0].table_name);
}

test "detect removed table" {
    const allocator = std.testing.allocator;

    const old_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &.{},
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const new_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567891,
        .tables = &.{},
    };

    const diff = try diffSnapshots(allocator, old_snapshot, new_snapshot);
    defer diff.deinit(allocator);

    try std.testing.expect(diff.has_changes);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes.len);
    try std.testing.expectEqual(ChangeType.remove, diff.table_changes[0].change_type);
    try std.testing.expectEqualStrings("users", diff.table_changes[0].table_name);
}

test "detect added field" {
    const allocator = std.testing.allocator;

    const old_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "id",
                        .type = "uuid",
                        .primary_key = true,
                        .unique = false,
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const new_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567891,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "id",
                        .type = "uuid",
                        .primary_key = true,
                        .unique = false,
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                    .{
                        .name = "email",
                        .type = "text",
                        .primary_key = false,
                        .unique = true,
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const diff = try diffSnapshots(allocator, old_snapshot, new_snapshot);
    defer diff.deinit(allocator);

    try std.testing.expect(diff.has_changes);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes.len);
    try std.testing.expectEqual(ChangeType.modify, diff.table_changes[0].change_type);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes[0].field_changes.len);
    try std.testing.expectEqual(ChangeType.add, diff.table_changes[0].field_changes[0].change_type);
    try std.testing.expectEqualStrings("email", diff.table_changes[0].field_changes[0].field_name);
}

test "detect modified field" {
    const allocator = std.testing.allocator;

    const old_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "email",
                        .type = "text",
                        .primary_key = false,
                        .unique = false, // Not unique
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const new_snapshot = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567891,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "email",
                        .type = "text",
                        .primary_key = false,
                        .unique = true, // Now unique
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const diff = try diffSnapshots(allocator, old_snapshot, new_snapshot);
    defer diff.deinit(allocator);

    try std.testing.expect(diff.has_changes);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes.len);
    try std.testing.expectEqual(ChangeType.modify, diff.table_changes[0].change_type);
    try std.testing.expectEqual(@as(usize, 1), diff.table_changes[0].field_changes.len);
    try std.testing.expectEqual(ChangeType.modify, diff.table_changes[0].field_changes[0].change_type);
    try std.testing.expectEqualStrings("email", diff.table_changes[0].field_changes[0].field_name);
}

test "no changes detected" {
    const allocator = std.testing.allocator;

    const snapshots = DatabaseSnapshot{
        .version = 1,
        .created_at = 1234567890,
        .tables = &[_]TableSnapshot{
            .{
                .name = "users",
                .fields = &[_]FieldSnapshot{
                    .{
                        .name = "id",
                        .type = "uuid",
                        .primary_key = true,
                        .unique = false,
                        .not_null = true,
                        .default_value = null,
                        .auto_generated = false,
                        .auto_generate_type = "none",
                    },
                },
                .indexes = &.{},
                .relationships = &.{},
                .has_many = &.{},
            },
        },
    };

    const diff = try diffSnapshots(allocator, snapshots, snapshots);
    defer diff.deinit(allocator);

    try std.testing.expect(!diff.has_changes);
    try std.testing.expectEqual(@as(usize, 0), diff.table_changes.len);
}
