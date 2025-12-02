// Schema definition types for the model generator
const std = @import("std");

pub const AutoGenerateType = enum {
    none,
    uuid,
    timestamp,
    increments,
};

pub const FieldType = enum {
    uuid,
    uuid_optional,
    text,
    text_optional,
    bool,
    bool_optional,
    i16,
    i16_optional,
    i32,
    i32_optional,
    i64,
    i64_optional,
    f32,
    f32_optional,
    f64,
    f64_optional,
    timestamp,
    timestamp_optional,
    json,
    json_optional,
    jsonb,
    jsonb_optional,
    binary,
    binary_optional,

    pub fn toZigType(self: FieldType) []const u8 {
        return switch (self) {
            .uuid => "[]const u8",
            .uuid_optional => "?[]const u8",
            .text => "[]const u8",
            .text_optional => "?[]const u8",
            .bool => "bool",
            .bool_optional => "?bool",
            .i16 => "i16",
            .i16_optional => "?i16",
            .i32 => "i32",
            .i32_optional => "?i32",
            .i64 => "i64",
            .i64_optional => "?i64",
            .f32 => "f32",
            .f32_optional => "?f32",
            .f64 => "f64",
            .f64_optional => "?f64",
            .timestamp => "i64",
            .timestamp_optional => "?i64",
            .json => "[]const u8",
            .json_optional => "?[]const u8",
            .jsonb => "[]const u8",
            .jsonb_optional => "?[]const u8",
            .binary => "[]const u8",
            .binary_optional => "?[]const u8",
        };
    }

    pub fn toPgType(self: FieldType) []const u8 {
        return switch (self) {
            .uuid => "UUID",
            .uuid_optional => "UUID",
            .text => "TEXT",
            .text_optional => "TEXT",
            .bool => "BOOLEAN",
            .bool_optional => "BOOLEAN",
            .i16 => "SMALLINT",
            .i16_optional => "SMALLINT",
            .i32 => "INT",
            .i32_optional => "INT",
            .i64 => "BIGINT",
            .i64_optional => "BIGINT",
            .f32 => "float4",
            .f32_optional => "float4",
            .f64 => "numeric",
            .f64_optional => "numeric",
            .timestamp => "TIMESTAMP",
            .timestamp_optional => "TIMESTAMP",
            .json => "JSON",
            .json_optional => "JSON",
            .jsonb => "JSONB",
            .jsonb_optional => "JSONB",
            .binary => "bytea",
            .binary_optional => "bytea",
        };
    }

    pub fn isOptional(self: FieldType) bool {
        return switch (self) {
            .text_optional, .i64_optional, .timestamp_optional, .json_optional => true,
            else => false,
        };
    }
};

pub const InputMode = enum {
    required, // Must be in CreateInput
    optional, // Optional in CreateInput
    excluded, // Not in CreateInput (auto-generated)
};

pub const Field = struct {
    name: []const u8,
    type: FieldType,

    // Constraints
    primary_key: bool = false,
    unique: bool = false,
    not_null: bool = true,

    // Generation hints
    create_input: InputMode = .required,
    update_input: bool = true,

    // JSON response hints
    redacted: bool = false, // If true, field is excluded from toJsonResponseSafe()

    // SQL defaults
    default_value: ?[]const u8 = null,
    auto_generated: bool = false,
    auto_generate_type: AutoGenerateType = .none,
};

pub const Alter = struct {
    name: []const u8,
    type: ?FieldType = null,

    // Constraints
    primary_key: ?bool = null,
    unique: ?bool = null,
    not_null: ?bool = null,

    // Generation hints
    create_input: ?InputMode = null,
    update_input: ?bool = null,

    // JSON response hints
    redacted: ?bool = null, // If true, field is excluded from toJsonResponseSafe()

    // SQL defaults
    default_value: ?[]const u8 = null,
    auto_generated: ?bool = null,
    auto_generate_type: ?AutoGenerateType = null,
};

pub const Index = struct {
    name: []const u8,
    columns: []const []const u8,
    unique: bool = false,
};

pub const RelationshipType = enum {
    many_to_one, // This table has foreign key to another table (e.g., Post -> User)
    one_to_many, // Another table has foreign key to this table (e.g., User -> Posts)
    one_to_one, // One-to-one relationship
    many_to_many, // Many-to-many through junction table
};

pub const OnDeleteAction = enum {
    cascade,
    set_null,
    set_default,
    restrict,
    no_action,

    pub fn toSQL(self: OnDeleteAction) []const u8 {
        return switch (self) {
            .cascade => "CASCADE",
            .set_null => "SET NULL",
            .set_default => "SET DEFAULT",
            .restrict => "RESTRICT",
            .no_action => "NO ACTION",
        };
    }
};

pub const OnUpdateAction = enum {
    cascade,
    set_null,
    set_default,
    restrict,
    no_action,

    pub fn toSQL(self: OnUpdateAction) []const u8 {
        return switch (self) {
            .cascade => "CASCADE",
            .set_null => "SET NULL",
            .set_default => "SET DEFAULT",
            .restrict => "RESTRICT",
            .no_action => "NO ACTION",
        };
    }
};

pub const Relationship = struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8,
    relationship_type: RelationshipType = .many_to_one,
    on_delete: OnDeleteAction = .no_action,
    on_update: OnUpdateAction = .no_action,
};

/// HasMany relationship definition for one-to-many relationships defined in the parent table.
/// This is metadata only - no SQL constraint is generated (the FK is in the child table).
/// Used to generate helper methods like `fetchUserPosts()` on the parent model.
pub const HasManyRelationship = struct {
    name: []const u8, // e.g., "user_posts"
    foreign_table: []const u8, // e.g., "posts"
    foreign_column: []const u8, // e.g., "user_id" (the FK column in foreign table)
    local_column: []const u8 = "id", // e.g., "id" (usually the PK of this table)
};

pub const Schema = struct {
    table_name: []const u8,
    struct_name: []const u8,
    fields: []const Field,
    indexes: []const Index,
    relationships: []const Relationship,

    pub fn getCreateInputFields(self: Schema) []const Field {
        var count: usize = 0;
        for (self.fields) |field| {
            if (field.create_input != .excluded) {
                count += 1;
            }
        }

        var result = std.heap.page_allocator.alloc(Field, count) catch unreachable;
        var i: usize = 0;
        for (self.fields) |field| {
            if (field.create_input != .excluded) {
                result[i] = field;
                i += 1;
            }
        }
        return result;
    }

    pub fn getUpdateInputFields(self: Schema) []const Field {
        var count: usize = 0;
        for (self.fields) |field| {
            if (field.update_input) {
                count += 1;
            }
        }

        var result = std.heap.page_allocator.alloc(Field, count) catch unreachable;
        var i: usize = 0;
        for (self.fields) |field| {
            if (field.update_input) {
                result[i] = field;
                i += 1;
            }
        }
        return result;
    }
};
