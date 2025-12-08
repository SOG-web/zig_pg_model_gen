const std = @import("std");

const Alter = @import("schema.zig").Alter;
const AutoGenerateType = @import("schema.zig").AutoGenerateType;
const Field = @import("schema.zig").Field;
const FieldType = @import("schema.zig").FieldType;
const HasManyRelationship = @import("schema.zig").HasManyRelationship;
const Index = @import("schema.zig").Index;
const InputMode = @import("schema.zig").InputMode;
const OnDeleteAction = @import("schema.zig").OnDeleteAction;
const OnUpdateAction = @import("schema.zig").OnUpdateAction;
const Relationship = @import("schema.zig").Relationship;

pub const FieldInput = struct {
    name: []const u8,

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
};

pub const TableSchema = @This();

name: []const u8,
fields: std.ArrayList(Field) = .{},
alters: std.ArrayList(Field) = .{},
indexes: std.ArrayList(Index) = .{},
drop_indexes: std.ArrayList([]const u8) = .{},
relationships: std.ArrayList(Relationship) = .{},
has_many_relationships: std.ArrayList(HasManyRelationship) = .{},
allocator: std.mem.Allocator,
err: ?anyerror = null,

// TODO: to be desided if we want to use this
// due to the way zig works, we can't auto ignore a function's return value
// const Chain = struct {
//     self: *TableSchema,

//     pub fn index(self: *Chain) void {
//         self.self.index();
//     }
// };

// fn chain(self: *TableSchema) Chain {
//     return .{ .self = self };
// }

pub fn create(name: []const u8, allocator: std.mem.Allocator, builder: *const fn (self: *TableSchema) void) !TableSchema {
    var self = TableSchema{
        .name = name,
        .allocator = allocator,
        .fields = std.ArrayList(Field){},
        .alters = std.ArrayList(Field){},
        .indexes = std.ArrayList(Index){},
        .relationships = std.ArrayList(Relationship){},
        .has_many_relationships = std.ArrayList(HasManyRelationship){},
    };

    builder(&self);

    if (self.err) |err| {
        self.deinit();
        return err;
    }

    return self;
}

/// Create an empty TableSchema without calling a builder function.
/// Useful for schema merging where multiple builders will be called.
pub fn createEmpty(name: []const u8, allocator: std.mem.Allocator) !TableSchema {
    return TableSchema{
        .name = name,
        .allocator = allocator,
        .fields = std.ArrayList(Field){},
        .alters = std.ArrayList(Field){},
        .indexes = std.ArrayList(Index){},
        .drop_indexes = std.ArrayList([]const u8){},
        .relationships = std.ArrayList(Relationship){},
        .has_many_relationships = std.ArrayList(HasManyRelationship){},
    };
}

pub fn deinit(self: *TableSchema) void {
    self.fields.deinit(self.allocator);
    self.alters.deinit(self.allocator);
    self.indexes.deinit(self.allocator);
    self.relationships.deinit(self.allocator);
    self.has_many_relationships.deinit(self.allocator);
}

pub fn getFieldByName(self: *TableSchema, field_name: []const u8) !*const Field {
    for (self.fields.items) |*f| {
        if (std.mem.eql(u8, f.name, field_name)) {
            return f;
        }
    }
    return error.FieldNotFound;
}

const IndT = struct {
    index: *Index,
    it: usize,
};

pub fn getIndexByName(self: *TableSchema, index_name: []const u8) !IndT {
    var it: usize = 0;
    for (self.indexes.items) |*i| {
        it += 1;
        if (std.mem.eql(u8, i.name, index_name)) {
            return .{ .index = i, .it = it };
        }
    }
    return error.IndexNotFound;
}

//TODO: leaking memory
fn index(self: *TableSchema) void {
    if (self.err != null) return;
    if (self.fields.items.len == 0) {
        self.err = error.NoFields;
        return;
    }
    //1. get the last field
    const field = self.fields.items[self.fields.items.len - 1];

    //2. create a new index
    const index_name = std.fmt.allocPrint(self.allocator, "idx_{s}", .{field.name}) catch |err| {
        self.err = err;
        return;
    };

    //3. add the index to the list
    self.indexes.append(self.allocator, .{
        .name = index_name,
        .columns = &.{field.name},
        .unique = field.unique,
    }) catch |err| {
        self.err = err;
    };
}

pub fn addIndexes(self: *TableSchema, list: []const Index) void {
    if (self.err != null) return;
    self.indexes.appendSlice(self.allocator, list) catch |err| {
        self.err = err;
    };
}

pub fn bigInt(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .i64 else .i64_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn bigIncrements(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = .i64,
        .primary_key = field.primary_key,
        .unique = true,
        .not_null = true,
        .create_input = .required,
        .update_input = false,
        .redacted = field.redacted,
        .default_value = null,
        .auto_generated = true,
        .auto_generate_type = .increments,
    }) catch |err| {
        self.err = err;
    };
}

pub fn integer(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .i32 else .i32_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn increments(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = .i32,
        .primary_key = field.primary_key,
        .unique = true,
        .not_null = true,
        .create_input = .required,
        .update_input = false,
        .redacted = field.redacted,
        .default_value = null,
        .auto_generated = true,
        .auto_generate_type = .increments,
    }) catch |err| {
        self.err = err;
    };
}

pub fn binary(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .binary else .binary_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn boolean(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .bool else .bool_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn string(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .text else .text_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn uuid(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .uuid else .uuid_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
        .auto_generate_type = .uuid,
    }) catch |err| {
        self.err = err;
    };
}

pub fn dateTime(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .timestamp else .timestamp_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
        .auto_generate_type = .timestamp,
    }) catch |err| {
        self.err = err;
    };
}

/// Adds standard created_at and updated_at timestamp fields to the table schema.
pub fn timestamps(self: *TableSchema) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = "created_at",
        .type = .timestamp,
        .not_null = true,
        .create_input = .excluded,
        .update_input = false,
        .redacted = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
        .auto_generate_type = .timestamp,
    }) catch |err| {
        self.err = err;
    };
    self.fields.append(self.allocator, .{
        .name = "updated_at",
        .type = .timestamp,
        .not_null = true,
        .create_input = .excluded,
        .update_input = false,
        .redacted = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
        .auto_generate_type = .timestamp,
    }) catch |err| {
        self.err = err;
    };
}

pub fn softDelete(self: *TableSchema) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = "deleted_at",
        .type = .timestamp_optional,
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
        .redacted = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
        .auto_generate_type = .timestamp,
    }) catch |err| {
        self.err = err;
    };
}

pub fn float(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .f32 else .f32_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn numeric(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .f64 else .f64_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn json(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .json else .json_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn jsonb(self: *TableSchema, field: FieldInput) void {
    if (self.err != null) return;
    self.fields.append(self.allocator, .{
        .name = field.name,
        .type = if (field.not_null) .jsonb else .jsonb_optional,
        .primary_key = field.primary_key,
        .unique = field.unique,
        .not_null = field.not_null,
        .create_input = field.create_input,
        .update_input = field.update_input,
        .redacted = field.redacted,
        .default_value = field.default_value,
        .auto_generated = field.auto_generated,
    }) catch |err| {
        self.err = err;
    };
}

pub fn foreign(self: *TableSchema, rel: Relationship) void {
    if (self.err != null) return;
    self.relationships.append(self.allocator, rel) catch |err| {
        self.err = err;
    };
}

pub fn foreigns(self: *TableSchema, rels: []const Relationship) void {
    if (self.err != null) return;
    self.relationships.appendSlice(self.allocator, rels) catch |err| {
        self.err = err;
    };
}

/// Define a belongs-to relationship (many-to-one).
/// This table has a foreign key column that references another table.
/// Example: Post belongs to User (posts.user_id -> users.id)
///
/// ```zig
/// t.belongsTo(.{
///     .name = "post_author",
///     .column = "user_id",
///     .references_table = "users",
///     .references_column = "id",
///     .on_delete = .cascade,
/// });
/// ```
pub fn belongsTo(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8 = "id",
    on_delete: OnDeleteAction = .no_action,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .many_to_one,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a has-one relationship (one-to-one).
/// This table has a unique foreign key column that references another table.
/// Example: User has one Profile (users.profile_id -> profiles.id)
///
/// ```zig
/// t.hasOne(.{
///     .name = "user_profile",
///     .column = "profile_id",
///     .references_table = "profiles",
///     .references_column = "id",
///     .on_delete = .set_null,
/// });
/// ```
pub fn hasOne(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8 = "id",
    on_delete: OnDeleteAction = .no_action,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .one_to_one,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a many-to-many relationship through a junction table.
/// This creates metadata for the relationship - the junction table must be defined separately.
/// Example: Users <-> Roles through user_roles junction table
///
/// ```zig
/// t.manyToMany(.{
///     .name = "user_roles",
///     .column = "user_id",           // FK column in junction table pointing to this table
///     .references_table = "user_roles", // The junction table
///     .references_column = "user_id",   // Column in junction that references this table
/// });
/// ```
pub fn manyToMany(self: *TableSchema, options: struct {
    name: []const u8,
    column: []const u8,
    references_table: []const u8,
    references_column: []const u8,
    on_delete: OnDeleteAction = .cascade,
    on_update: OnUpdateAction = .no_action,
}) void {
    self.foreign(.{
        .name = options.name,
        .column = options.column,
        .references_table = options.references_table,
        .references_column = options.references_column,
        .relationship_type = .many_to_many,
        .on_delete = options.on_delete,
        .on_update = options.on_update,
    });
}

/// Define a one-to-many relationship from this table (parent) to another table (child).
/// This is metadata only - no FK constraint is generated here (the FK lives in the child table).
/// This generates helper methods like `fetchUserPosts()` on this model.
///
/// Example in users.zig:
/// ```zig
/// t.hasMany(.{
///     .name = "user_posts",
///     .foreign_table = "posts",
///     .foreign_column = "user_id",
/// });
/// ```
pub fn hasMany(self: *TableSchema, rel: HasManyRelationship) void {
    if (self.err != null) return;
    self.has_many_relationships.append(self.allocator, rel) catch |err| {
        self.err = err;
    };
}

/// Define multiple one-to-many relationships at once.
pub fn hasManyList(self: *TableSchema, rels: []const HasManyRelationship) void {
    if (self.err != null) return;
    self.has_many_relationships.appendSlice(self.allocator, rels) catch |err| {
        self.err = err;
    };
}

pub fn alterField(self: *TableSchema, field: Alter) void {
    if (self.err != null) return;
    if (self.fields.items.len == 0) {
        self.err = error.NoFields;
        return;
    }

    // check if field exists
    const exist = self.getFieldByName(field.name) catch |err| {
        self.err = err;
        return;
    };

    self.alters.append(self.allocator, .{
        .name = field.name,
        .type = if (field.type) |t| t else exist.type,
        .primary_key = if (field.primary_key) |pk| pk else exist.primary_key,
        .unique = if (field.unique) |u| u else exist.unique,
        .not_null = if (field.not_null) |nn| nn else exist.not_null,
        .create_input = if (field.create_input) |ci| ci else exist.create_input,
        .update_input = if (field.update_input) |ui| ui else exist.update_input,
        .redacted = if (field.redacted) |r| r else exist.redacted,
        .default_value = if (field.default_value) |dv| dv else exist.default_value,
        .auto_generated = if (field.auto_generated) |ag| ag else exist.auto_generated,
        .auto_generate_type = if (field.auto_generate_type) |agt| agt else exist.auto_generate_type,
    }) catch |err| {
        self.err = err;
    };
}

pub fn alterFields(self: *TableSchema, fields: []const Alter) void {
    if (self.err != null) return;
    if (self.fields.items.len == 0) {
        self.err = error.NoFields;
        return;
    }

    for (fields) |field| {
        self.alterField(field);
    }
}

pub fn dropIndex(self: *TableSchema, index_name: []const u8) void {
    if (self.err != null) return;
    self.drop_indexes.append(self.allocator, index_name) catch |err| {
        self.err = err;
        return;
    };
}

test "check" {
    const allocator = std.testing.allocator;

    var table = try TableSchema.create(
        "test",
        allocator,
        struct {
            fn build(t: *TableSchema) void {
                t.bigIncrements(.{ .name = "id" });
                t.string(.{ .name = "name" });
                // t.index();
            }
        }.build,
    );
    defer table.deinit();
}

test "deferred error check" {
    const allocator = std.testing.allocator;

    const result = TableSchema.create(
        "test_error",
        allocator,
        struct {
            fn build(t: *TableSchema) void {
                t.index(); // Should fail because no fields
            }
        }.build,
    );

    try std.testing.expectError(error.NoFields, result);
}
