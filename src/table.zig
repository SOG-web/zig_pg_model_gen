const std = @import("std");

const AutoGenerateType = @import("schema.zig").AutoGenerateType;
const Field = @import("schema.zig").Field;
const FieldType = @import("schema.zig").FieldType;
const Index = @import("schema.zig").Index;
const InputMode = @import("schema.zig").InputMode;
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
alters: std.ArrayList(FieldInput) = .{},
indexes: std.ArrayList(Index) = .{},
drop_indexes: std.ArrayList([]const u8) = .{},
relationships: std.ArrayList(Relationship) = .{},
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

pub fn create(name: []const u8, allocator: std.mem.Allocator, builder: fn (self: *TableSchema) void) !TableSchema {
    var self = TableSchema{
        .name = name,
        .allocator = allocator,
        .fields = std.ArrayList(Field){},
        .alters = std.ArrayList(FieldInput){},
        .indexes = std.ArrayList(Index){},
        .relationships = std.ArrayList(Relationship){},
    };

    builder(&self);

    if (self.err) |err| {
        self.deinit();
        return err;
    }

    return self;
}

pub fn deinit(self: *TableSchema) void {
    self.fields.deinit(self.allocator);
    self.alters.deinit(self.allocator);
    self.indexes.deinit(self.allocator);
    self.relationships.deinit(self.allocator);
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

pub fn alterField(self: *TableSchema, field: FieldInput) void {
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

    if (exist == null) {
        self.err = error.FieldNotFound;
        return;
    }

    self.alters.append(self.allocator, field) catch |err| {
        self.err = err;
    };
}

pub fn alterFields(self: *TableSchema, fields: []const FieldInput) void {
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
