pub const Alter = @import("schema.zig").Alter;
pub const AutoGenerateType = @import("schema.zig").AutoGenerateType;
pub const Field = @import("schema.zig").Field;
pub const FieldType = @import("schema.zig").FieldType;
pub const Index = @import("schema.zig").Index;
pub const InputMode = @import("schema.zig").InputMode;
pub const model_generator = @import("model_generator.zig");
pub const OnDeleteAction = @import("schema.zig").OnDeleteAction;
pub const OnUpdateAction = @import("schema.zig").OnUpdateAction;
pub const Relationship = @import("schema.zig").Relationship;
pub const RelationshipType = @import("schema.zig").RelationshipType;
pub const Schema = @import("schema.zig").Schema;
pub const sql_generator = @import("sql_generator.zig");
pub const TableSchema = @import("table.zig");

pub const SchemaBuilder = struct {
    name: []const u8,
    builder_fn: *const fn (*TableSchema) void,
};

test {
    @import("std").testing.refAllDecls(@This());
}
