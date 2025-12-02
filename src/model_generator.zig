const std = @import("std");

const Field = @import("schema.zig").Field;
const HasManyRelationship = @import("schema.zig").HasManyRelationship;
const Relationship = @import("schema.zig").Relationship;
const TableSchema = @import("table.zig").TableSchema;

fn singularize(table_name: []const u8) []const u8 {
    // Simple singularization: remove trailing 's' if present
    // This handles: posts -> post, comments -> comment, profiles -> profile
    // Note: doesn't handle complex cases like "categories" -> "category"
    if (table_name.len > 1 and table_name[table_name.len - 1] == 's') {
        return table_name[0 .. table_name.len - 1];
    }
    return table_name;
}

fn tableToPascalCase(allocator: std.mem.Allocator, table_name: []const u8) ![]const u8 {
    //  Singularize first (posts -> post, comments -> comment)
    const singular = singularize(table_name);

    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var capitalize_next = true;
    for (singular) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn toLowerSnakeCase(allocator: std.mem.Allocator, camel: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    for (camel, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0) {
                try result.append(allocator, '_');
            }
            try result.append(allocator, std.ascii.toLower(c));
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn toPascalCaseNonSingular(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Convert to PascalCase WITHOUT singularizing
    // e.g., "comments" -> "Comments" (not "Comment")
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var capitalize_next = true;
    for (name) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn columnToMethodName(allocator: std.mem.Allocator, column_name: []const u8, table_name: []const u8, is_plural: bool) ![]const u8 {
    // Convert organization_id -> Organization
    // Convert user_id -> User
    // For one-to-many: use table name directly keeping plurality (e.g., "comments" -> "Comments")
    // Strip _id suffix and convert to PascalCase

    // If column is just "id", use the table name (don't singularize for one-to-many)
    if (std.mem.eql(u8, column_name, "id")) {
        if (is_plural) {
            // Keep plural for one-to-many: "comments" -> "Comments"
            return toPascalCaseNonSingular(allocator, table_name);
        } else {
            // Singularize for one-to-one reverse: "profiles" -> "Profile"
            return tableToPascalCase(allocator, table_name);
        }
    }

    var name_without_id = column_name;
    if (std.mem.endsWith(u8, column_name, "_id")) {
        name_without_id = column_name[0 .. column_name.len - 3];
    }

    return tableToPascalCase(allocator, name_without_id);
}

fn relationshipToFieldName(allocator: std.mem.Allocator, rel: Relationship) ![]const u8 {
    // Convert organization_id -> organization (snake_case, strip _id)
    // Convert user_id -> user
    // For one_to_many: use references_table directly (e.g., "comments")
    // For reverse relationships (column="id"): use references_table

    switch (rel.relationship_type) {
        .one_to_many, .many_to_many => {
            // For one_to_many, use the referenced table name as-is (already plural)
            // e.g., references "comments" table -> field "comments"
            return allocator.dupe(u8, rel.references_table);
        },
        .one_to_one => {
            // If column is "id", this is a reverse relationship - use table name
            if (std.mem.eql(u8, rel.column, "id")) {
                // Remove plural 's' for one-to-one if present
                if (std.mem.endsWith(u8, rel.references_table, "s")) {
                    return allocator.dupe(u8, rel.references_table[0 .. rel.references_table.len - 1]);
                }
                return allocator.dupe(u8, rel.references_table);
            }
            // Forward relationship - use column name without _id
            var name_without_id = rel.column;
            if (std.mem.endsWith(u8, rel.column, "_id")) {
                name_without_id = rel.column[0 .. rel.column.len - 3];
            }
            return allocator.dupe(u8, name_without_id);
        },
        .many_to_one => {
            // For many_to_one, use column name without _id suffix
            var name_without_id = rel.column;
            if (std.mem.endsWith(u8, rel.column, "_id")) {
                name_without_id = rel.column[0 .. rel.column.len - 3];
            }
            return allocator.dupe(u8, name_without_id);
        },
    }
}

fn hasManyMethodName(allocator: std.mem.Allocator, rel_name: []const u8) ![]const u8 {
    // Convert "user_posts" -> "Posts", "user_comments" -> "Comments"
    // Takes the last part after underscore and converts to PascalCase
    // If no underscore, just capitalize first letter

    // Find the last underscore
    var last_underscore: ?usize = null;
    for (rel_name, 0..) |c, i| {
        if (c == '_') {
            last_underscore = i;
        }
    }

    const name_part = if (last_underscore) |idx|
        rel_name[idx + 1 ..]
    else
        rel_name;

    // Convert to PascalCase (capitalize first letter, keep the rest including plural 's')
    return toPascalCaseNonSingular(allocator, name_part);
}

fn getFinalFields(allocator: std.mem.Allocator, schema: TableSchema) ![]Field {
    var fields = std.ArrayList(Field){};
    defer fields.deinit(allocator);
    try fields.appendSlice(allocator, schema.fields.items);

    for (schema.alters.items) |alter| {
        for (fields.items) |*f| {
            if (std.mem.eql(u8, f.name, alter.name)) {
                f.* = alter;
                break;
            }
        }
    }

    return fields.toOwnedSlice(allocator);
}

pub fn generateModel(allocator: std.mem.Allocator, schema: TableSchema, schema_file: []const u8, output_dir: []const u8) !void {

    // Ensure output directory exists
    std.fs.cwd().makePath(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating directory '{s}': {}\n", .{ output_dir, err });
            return err;
        }
    };

    // Calculate final fields (applying alters)
    const final_fields = try getFinalFields(allocator, schema);
    defer allocator.free(final_fields);

    // Generate file name from struct name
    const snake_case_name = try toLowerSnakeCase(allocator, schema.name);
    defer allocator.free(snake_case_name);
    const file_name = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ output_dir, snake_case_name });
    defer allocator.free(file_name);

    // Generate PascalCase struct name (e.g., "comments" -> "Comments")
    const struct_name = try toPascalCaseNonSingular(allocator, schema.name);
    defer allocator.free(struct_name);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    // Generate header
    try generateHeader(writer, schema_file);

    // Generate imports
    try generateImports(writer, schema, allocator);

    // Generate struct definition
    try generateStructDefinition(writer, schema, struct_name, final_fields, allocator);

    // Generate CreateInput
    try generateCreateInput(writer, final_fields, allocator);

    // Generate UpdateInput
    try generateUpdateInput(writer, final_fields, allocator);

    // Generate SQL methods
    try generateSQLMethods(writer, schema, struct_name, final_fields, allocator);

    // Generate base
    try generateBaseModelWrapper(writer, struct_name);

    // Generate DDL wrappers
    try generateDDLWrappers(writer);

    // Generate CRUD wrappers
    try generateCRUDWrappers(writer, struct_name);

    // Generate JSON response helpers
    try generateJsonResponseHelpers(writer, struct_name, final_fields);

    // Generate relationship methods
    try generateRelationshipMethods(writer, schema, struct_name, allocator);

    // Generate transaction support
    try generateTransactionSupport(writer, struct_name);

    // Write to file
    try std.fs.cwd().writeFile(.{ .sub_path = file_name, .data = output.items });

    std.debug.print("✅ Generated: {s}\n", .{file_name});
}

fn generateHeader(writer: anytype, schema_file: []const u8) !void {
    try writer.print(
        \\// AUTO-GENERATED CODE - DO NOT EDIT
        \\// Generated by scripts/generate_model.zig
        \\// Source schema: {s}
        \\// To regenerate: zig run scripts/generate_model.zig -- {s}
        \\
        \\
    , .{ schema_file, schema_file });
}

fn generateImports(writer: anytype, schema: TableSchema, allocator: std.mem.Allocator) !void {
    try writer.writeAll(
        \\const std = @import("std");
        \\const pg = @import("pg");
        \\const BaseModel = @import("base.zig").BaseModel;
        \\const QueryBuilder = @import("query.zig").QueryBuilder;
        \\const Transaction = @import("transaction.zig").Transaction;
        \\
    );

    // Collect all related tables from both relationships and has_many_relationships
    var seen_tables = std.StringHashMap(void).init(allocator);
    defer seen_tables.deinit();

    // Add imports from regular relationships (belongsTo, hasOne, foreign)
    for (schema.relationships.items) |rel| {
        // Skip self-references (e.g., comments referencing comments for parent_id)
        if (std.mem.eql(u8, rel.references_table, schema.name)) continue;

        if (!seen_tables.contains(rel.references_table)) {
            try seen_tables.put(rel.references_table, {});
        }
    }

    // Add imports from hasMany relationships
    for (schema.has_many_relationships.items) |rel| {
        // Skip self-references (e.g., comments has many comments for replies)
        if (std.mem.eql(u8, rel.foreign_table, schema.name)) continue;

        if (!seen_tables.contains(rel.foreign_table)) {
            try seen_tables.put(rel.foreign_table, {});
        }
    }

    // Generate imports if we have any related models
    if (seen_tables.count() > 0) {
        try writer.writeAll("\n// Related models\n");

        var iter = seen_tables.keyIterator();
        while (iter.next()) |table_name| {
            // Use PascalCase non-singular for both import name and struct reference
            // e.g., "comments" -> "Comments" (the struct is Comments, not Comment)
            const struct_name = try toPascalCaseNonSingular(allocator, table_name.*);
            defer allocator.free(struct_name);

            try writer.print("const {s} = @import(\"{s}.zig\");\n", .{
                struct_name,
                table_name.*,
            });
        }
    }

    try writer.writeAll("\n");
}

fn generateStructDefinition(writer: anytype, schema: TableSchema, struct_name: []const u8, fields: []const Field, allocator: std.mem.Allocator) !void {
    _ = schema;
    _ = allocator;

    try writer.print("const {s} = @This();\n\n", .{struct_name});
    try writer.writeAll("// Fields\n");

    for (fields) |field| {
        try writer.print("{s}: {s},\n", .{ field.name, field.type.toZigType() });
    }

    // generate field enum
    try writer.writeAll("    pub const FieldEnum = enum {\n");
    for (fields) |field| {
        try writer.print("        {s},\n", .{field.name});
    }
    try writer.writeAll("    };\n");

    try writer.writeAll("\n\n");
}

fn generateCreateInput(writer: anytype, fields: []const Field, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.writeAll("    // Input type for creating new records\n");
    try writer.writeAll("    pub const CreateInput = struct {\n");

    for (fields) |field| {
        if (field.create_input == .required) {
            try writer.print("        {s}: {s},\n", .{ field.name, field.type.toZigType() });
        } else if (field.create_input == .optional) {
            const zig_type = field.type.toZigType();
            if (field.type.isOptional()) {
                try writer.print("        {s}: {s} = null,\n", .{ field.name, zig_type });
            } else {
                try writer.print("        {s}: ?{s} = null,\n", .{ field.name, zig_type });
            }
        }
    }

    try writer.writeAll("    };\n\n");
}

fn generateUpdateInput(writer: anytype, fields: []const Field, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.writeAll("    // Input type for updating existing records\n");
    try writer.writeAll("    pub const UpdateInput = struct {\n");

    for (fields) |field| {
        if (field.update_input) {
            const zig_type = field.type.toZigType();
            if (field.type.isOptional()) {
                try writer.print("        {s}: {s} = null,\n", .{ field.name, zig_type });
            } else {
                try writer.print("        {s}: ?{s} = null,\n", .{ field.name, zig_type });
            }
        }
    }

    try writer.writeAll("    };\n\n");
}

fn generateSQLMethods(writer: anytype, schema: TableSchema, struct_name: []const u8, fields: []const Field, allocator: std.mem.Allocator) !void {
    _ = struct_name;
    // tableName - uses table name (snake_case) for SQL
    try writer.print(
        \\    // Model configuration
        \\    pub fn tableName() []const u8 {{
        \\        return "{s}";
        \\    }}
        \\
        \\
    , .{schema.name});

    // insertSQL
    try generateInsertSQL(writer, schema, fields, allocator);

    // updateSQL
    try generateUpdateSQL(writer, schema, fields, allocator);

    // upsertSQL
    try generateUpsertSQL(writer, schema, fields, allocator);
}

fn generateInsertSQL(writer: anytype, schema: TableSchema, fields: []const Field, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var cols = std.ArrayList([]const u8){};
    defer cols.deinit(arena_allocator);
    var params = std.ArrayList([]const u8){};
    defer params.deinit(arena_allocator);
    var param_types = std.ArrayList([]const u8){};
    defer param_types.deinit(arena_allocator);

    var param_num: usize = 1;
    for (fields) |field| {
        if (field.create_input != .excluded) {
            try cols.append(arena_allocator, field.name);

            const param_str = try std.fmt.allocPrint(arena_allocator, "${d}", .{param_num});
            if (field.create_input == .optional and field.default_value != null) {
                const coalesce = try std.fmt.allocPrint(arena_allocator, "COALESCE(${d}, {s})", .{ param_num, field.default_value.? });
                try params.append(arena_allocator, coalesce);
            } else {
                try params.append(arena_allocator, param_str);
            }
            param_num += 1;

            const zig_type = field.type.toZigType();
            if (field.create_input == .optional) {
                if (field.type.isOptional()) {
                    try param_types.append(arena_allocator, zig_type);
                } else {
                    const optional_type = try std.fmt.allocPrint(arena_allocator, "?{s}", .{zig_type});
                    try param_types.append(arena_allocator, optional_type);
                }
            } else {
                try param_types.append(arena_allocator, zig_type);
            }
        }
    }

    const cols_str = try std.mem.join(arena_allocator, ", ", cols.items);
    const params_str = try std.mem.join(arena_allocator, ", ", params.items);

    try writer.writeAll("    pub fn insertSQL() []const u8 {\n");
    try writer.writeAll("        return\n");
    try writer.print("            \\\\INSERT INTO {s} (\n", .{schema.name});
    try writer.print("            \\\\    {s}\n", .{cols_str});
    try writer.print("            \\\\) VALUES ({s})\n", .{params_str});
    try writer.writeAll("            \\\\RETURNING id\n");
    try writer.writeAll("        ;\n");
    try writer.writeAll("    }\n\n");

    // insertParams
    try writer.writeAll("    pub fn insertParams(data: CreateInput) struct {\n");
    for (param_types.items) |ptype| {
        try writer.print("        {s},\n", .{ptype});
    }
    try writer.writeAll("    } {\n");
    try writer.writeAll("        return .{\n");

    for (fields) |field| {
        if (field.create_input != .excluded) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateUpdateSQL(writer: anytype, schema: TableSchema, fields: []const Field, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var updates = std.ArrayList([]const u8){};
    defer updates.deinit(arena_allocator);
    var param_types = std.ArrayList([]const u8){};
    defer param_types.deinit(arena_allocator);

    try param_types.append(arena_allocator, "[]const u8"); // ID parameter

    var param_num: usize = 2;
    for (fields) |field| {
        if (field.update_input) {
            const update_str = try std.fmt.allocPrint(arena_allocator, "            \\\\    {s} = COALESCE(${d}, {s})", .{ field.name, param_num, field.name });
            try updates.append(arena_allocator, update_str);
            param_num += 1;

            const zig_type = field.type.toZigType();
            if (field.type.isOptional()) {
                try param_types.append(arena_allocator, zig_type);
            } else {
                const optional_type = try std.fmt.allocPrint(arena_allocator, "?{s}", .{zig_type});
                try param_types.append(arena_allocator, optional_type);
            }
        }
    }

    try writer.writeAll("    pub fn updateSQL() []const u8 {\n");
    try writer.writeAll("        return\n");
    try writer.print("            \\\\UPDATE {s} SET\n", .{schema.name});

    for (updates.items, 0..) |update, i| {
        try writer.writeAll(update);
        if (i < updates.items.len - 1) {
            try writer.writeAll(",\n");
        } else {
            try writer.writeAll(",\n");
        }
    }

    try writer.writeAll("            \\\\    updated_at = CURRENT_TIMESTAMP\n");
    try writer.writeAll("            \\\\WHERE id = $1\n");
    try writer.writeAll("        ;\n");
    try writer.writeAll("    }\n\n");

    // updateParams
    try writer.writeAll("    pub fn updateParams(id: []const u8, data: UpdateInput) struct {\n");
    for (param_types.items) |ptype| {
        try writer.print("        {s},\n", .{ptype});
    }
    try writer.writeAll("    } {\n");
    try writer.writeAll("        return .{\n");
    try writer.writeAll("            id,\n");

    for (fields) |field| {
        if (field.update_input) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateUpsertSQL(writer: anytype, schema: TableSchema, fields: []const Field, allocator: std.mem.Allocator) !void {
    // Find unique field for ON CONFLICT
    var unique_field: ?[]const u8 = null;
    for (fields) |field| {
        if (field.unique and !field.primary_key) {
            unique_field = field.name;
            break;
        }
    }

    if (unique_field == null) {
        // No unique field, skip upsert
        return;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var cols = std.ArrayList([]const u8){};
    defer cols.deinit(arena_allocator);
    var params = std.ArrayList([]const u8){};
    defer params.deinit(arena_allocator);
    var updates = std.ArrayList([]const u8){};
    defer updates.deinit(arena_allocator);

    var param_num: usize = 1;
    for (fields) |field| {
        if (field.create_input != .excluded) {
            try cols.append(arena_allocator, field.name);
            const param_str = try std.fmt.allocPrint(arena_allocator, "${d}", .{param_num});
            try params.append(arena_allocator, param_str);
            param_num += 1;

            if (!field.unique and !field.primary_key and !field.auto_generated) {
                const update_str = try std.fmt.allocPrint(arena_allocator, "            \\\\    {s} = EXCLUDED.{s}", .{ field.name, field.name });
                try updates.append(arena_allocator, update_str);
            }
        }
    }

    const cols_str = try std.mem.join(arena_allocator, ", ", cols.items);
    const params_str = try std.mem.join(arena_allocator, ", ", params.items);

    try writer.writeAll("    pub fn upsertSQL() []const u8 {\n");
    try writer.writeAll("        return\n");
    try writer.print("            \\\\INSERT INTO {s} (\n", .{schema.name});
    try writer.print("            \\\\    {s}\n", .{cols_str});
    try writer.print("            \\\\) VALUES ({s})\n", .{params_str});
    try writer.print("            \\\\ON CONFLICT ({s}) DO UPDATE SET\n", .{unique_field.?});

    for (updates.items, 0..) |update, i| {
        try writer.writeAll(update);
        if (i < updates.items.len - 1) {
            try writer.writeAll(",\n");
        } else {
            try writer.writeAll(",\n");
        }
    }

    try writer.writeAll("            \\\\    updated_at = CURRENT_TIMESTAMP\n");
    try writer.writeAll("            \\\\RETURNING id\n");
    try writer.writeAll("        ;\n");
    try writer.writeAll("    }\n\n");

    // upsertParams (same as insertParams)
    try writer.writeAll("    pub fn upsertParams(data: CreateInput) struct {\n");
    for (fields) |field| {
        if (field.create_input != .excluded) {
            const zig_type = field.type.toZigType();
            if (field.create_input == .optional) {
                if (field.type.isOptional()) {
                    try writer.print("        {s},\n", .{zig_type});
                } else {
                    try writer.print("        ?{s},\n", .{zig_type});
                }
            } else {
                try writer.print("        {s},\n", .{zig_type});
            }
        }
    }
    try writer.writeAll("    } {\n");
    try writer.writeAll("        return .{\n");

    for (fields) |field| {
        if (field.create_input != .excluded) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateBaseModelWrapper(writer: anytype, struct_name: []const u8) !void {
    try writer.print("    const base = BaseModel({s});\n", .{struct_name});
}

fn generateDDLWrappers(writer: anytype) !void {
    try writer.writeAll(
        \\    // DDL operations
        \\
        \\    pub const truncate = base.truncate;
        \\
        \\    pub const tableExists = base.tableExists;
        \\
        \\
    );
}

fn generateCRUDWrappers(writer: anytype, struct_name: []const u8) !void {
    try writer.writeAll(
        \\    // CRUD operations
        \\    pub const findById = base.findById;
        \\
        \\    pub const findAll = base.findAll;
        \\
        \\    pub const insert = base.insert;
        \\
        \\    pub const insertAndReturn = base.insertAndReturn;
        \\
        \\    pub const update = base.update;
        \\
        \\    pub const updateAndReturn = base.updateAndReturn;
        \\
        \\    pub const upsert = base.upsert;
        \\
        \\    pub const upsertAndReturn = base.upsertAndReturn;
        \\
        \\    pub const softDelete = base.softDelete;
        \\
        \\    pub const hardDelete = base.hardDelete;
        \\
        \\    pub const count = base.count;
        \\
        \\    pub const fromRow = base.fromRow;
        \\
        \\
    );

    try writer.print("    pub fn query() QueryBuilder({s}, UpdateInput, FieldEnum) {{\n", .{struct_name});
    try writer.print("        return QueryBuilder({s}, UpdateInput, FieldEnum).init();\n", .{struct_name});
    try writer.writeAll("    }\n\n");
}

fn generateJsonResponseHelpers(writer: anytype, struct_name: []const u8, fields: []const Field) !void {
    // Generate JsonResponse struct with UUIDs as hex strings
    try writer.writeAll("\n    /// JSON-safe response struct with UUIDs as hex strings\n");
    try writer.writeAll("    pub const JsonResponse = struct {\n");

    for (fields) |field| {
        try writer.writeAll("        ");
        try writer.print("{s}: ", .{field.name});

        // Convert UUID fields to [36]u8 hex strings
        if (field.type == .uuid) {
            try writer.writeAll("[36]u8");
        } else {
            // Keep the same type for non-UUID fields
            const zig_type = field.type.toZigType();
            try writer.print("{s}", .{zig_type});
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("    };\n\n");

    // Generate toJsonResponse method
    try writer.writeAll("    /// Convert model to JSON-safe response with UUIDs as hex strings\n");
    try writer.writeAll("    pub fn toJsonResponse(self: ");
    try writer.print("{s}) !JsonResponse {{\n", .{struct_name});
    try writer.writeAll("        return JsonResponse{\n");

    for (fields) |field| {
        try writer.writeAll("            .");
        try writer.print("{s} = ", .{field.name});

        // Convert UUID fields using pg.uuidToHex
        if (field.type == .uuid) {
            try writer.print("try pg.uuidToHex(&self.{s}[0..16].*)", .{field.name});
        } else {
            try writer.print("self.{s}", .{field.name});
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    // Generate JsonResponseSafe struct (excludes redacted fields)
    try writer.writeAll("    /// JSON-safe response struct with UUIDs as hex strings (excludes redacted fields)\n");
    try writer.writeAll("    pub const JsonResponseSafe = struct {\n");

    for (fields) |field| {
        if (field.redacted) continue; // Skip redacted fields

        try writer.writeAll("        ");
        try writer.print("{s}: ", .{field.name});

        // Convert UUID fields to [36]u8 hex strings
        if (field.type == .uuid) {
            try writer.writeAll("[36]u8");
        } else {
            // Keep the same type for non-UUID fields
            const zig_type = field.type.toZigType();
            try writer.print("{s}", .{zig_type});
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("    };\n\n");

    // Generate toJsonResponseSafe method
    try writer.writeAll("    /// Convert model to JSON-safe response excluding redacted fields (passwords, tokens, etc.)\n");
    try writer.writeAll("    pub fn toJsonResponseSafe(self: ");
    try writer.print("{s}) !JsonResponseSafe {{\n", .{struct_name});
    try writer.writeAll("        return JsonResponseSafe{\n");

    for (fields) |field| {
        if (field.redacted) continue; // Skip redacted fields

        try writer.writeAll("            .");
        try writer.print("{s} = ", .{field.name});

        // Convert UUID fields using pg.uuidToHex
        if (field.type == .uuid) {
            try writer.print("try pg.uuidToHex(&self.{s}[0..16].*)", .{field.name});
        } else {
            try writer.print("self.{s}", .{field.name});
        }
        try writer.writeAll(",\n");
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n");
}

fn generateRelationshipMethods(writer: anytype, schema: TableSchema, struct_name: []const u8, allocator: std.mem.Allocator) !void {
    const has_relationships = schema.relationships.items.len > 0;
    const has_many_relationships = schema.has_many_relationships.items.len > 0;

    if (!has_relationships and !has_many_relationships) return;

    try writer.writeAll("    // Relationship methods\n");

    // Generate methods for regular relationships (belongsTo, hasOne, foreign)
    for (schema.relationships.items) |rel| {
        // Skip self-references for method generation - we'll use @This() for those
        const is_self_reference = std.mem.eql(u8, rel.references_table, schema.name);

        // Use PascalCase non-singular to match struct names (Comments, not Comment)
        const related_struct_name = if (is_self_reference)
            try allocator.dupe(u8, struct_name)
        else
            try toPascalCaseNonSingular(allocator, rel.references_table);
        defer allocator.free(related_struct_name);

        const is_plural = (rel.relationship_type == .one_to_many or rel.relationship_type == .many_to_many);
        const method_suffix = try columnToMethodName(allocator, rel.column, rel.references_table, is_plural);
        defer allocator.free(method_suffix);

        const field_name = try relationshipToFieldName(allocator, rel);
        defer allocator.free(field_name);

        // Generate fetch method based on relationship type
        switch (rel.relationship_type) {
            .many_to_one => {
                // Fetch single related entity (forward relationship)
                try writer.print(
                    \\    /// Fetch the related {s} record for this {s}
                    \\    pub fn fetch{s}(self: *const {s}, db: *pg.Pool, allocator: std.mem.Allocator) !?{s} {{
                    \\        return {s}.findById(db, allocator, self.{s});
                    \\    }}
                    \\
                    \\
                , .{
                    related_struct_name,
                    struct_name,
                    method_suffix,
                    struct_name,
                    related_struct_name,
                    related_struct_name,
                    rel.column,
                });
            },
            .one_to_one => {
                // For one-to-one, check if it's forward (this table has FK) or reverse (other table has FK)
                // If column is "id", this is reverse side - need to query by foreign key
                // Otherwise, it's forward side - use findById
                if (std.mem.eql(u8, rel.column, "id")) {
                    // Reverse side: query the related table by its foreign key
                    try writer.print(
                        \\    /// Fetch the related {s} record for this {s}
                        \\    pub fn fetch{s}(self: *const {s}, db: *pg.Pool, allocator: std.mem.Allocator) !?{s} {{
                        \\        const queryt = "SELECT * FROM {s} WHERE {s} = $1 LIMIT 1";
                        \\        var result = try db.query(queryt, .{{self.id}});
                        \\        defer result.deinit();
                        \\
                        \\        if (try result.next()) |row| {{
                        \\            return try row.to({s}, .{{ .allocator = allocator, .map = .ordinal }});
                        \\        }}
                        \\        return null;
                        \\    }}
                        \\
                        \\
                    , .{
                        related_struct_name,
                        struct_name,
                        method_suffix,
                        struct_name,
                        related_struct_name,
                        rel.references_table,
                        rel.references_column,
                        related_struct_name,
                    });
                } else {
                    // Forward side: use findById
                    try writer.print(
                        \\    /// Fetch the related {s} record for this {s}
                        \\    pub fn fetch{s}(self: *const {s}, db: *pg.Pool, allocator: std.mem.Allocator) !?{s} {{
                        \\        return {s}.findById(db, allocator, self.{s});
                        \\    }}
                        \\
                        \\
                    , .{
                        related_struct_name,
                        struct_name,
                        method_suffix,
                        struct_name,
                        related_struct_name,
                        related_struct_name,
                        rel.column,
                    });
                }
            },
            .one_to_many => {
                // Fetch multiple related entities (reverse lookup)
                try writer.print(
                    \\    /// Fetch all {s} records related to this {s}
                    \\    pub fn fetch{s}(self: *const {s}, db: *pg.Pool, allocator: std.mem.Allocator) ![]{s} {{
                    \\        const queryt = "SELECT * FROM {s} WHERE {s} = $1";
                    \\        var result = try db.query(queryt, .{{self.id}});
                    \\        defer result.deinit();
                    \\
                    \\        var list = std.ArrayList({s}){{}};
                    \\        errdefer list.deinit(allocator);
                    \\
                    \\        while (try result.next()) |row| {{
                    \\            const item = try row.to({s}, .{{ .allocator = allocator, .map = .ordinal }});
                    \\            try list.append(allocator, item);
                    \\        }}
                    \\
                    \\        return try list.toOwnedSlice(allocator);
                    \\    }}
                    \\
                    \\
                , .{
                    related_struct_name,
                    struct_name,
                    method_suffix,
                    struct_name,
                    related_struct_name,
                    rel.references_table,
                    rel.references_column,
                    related_struct_name,
                    related_struct_name,
                });
            },
            .many_to_many => {
                // Many-to-many relationships are implemented via junction tables
                // Example: To get all Tags for a Post, you would:
                // 1. Query post_tags WHERE post_id = self.id
                // 2. For each result, fetch the related tag
                // This is best handled with custom methods or by directly using the junction table
                // We don't generate automatic many-to-many fetch methods as they require
                // junction table configuration and multiple queries
            },
        }
    }

    // Generate methods for hasMany relationships
    for (schema.has_many_relationships.items) |rel| {
        // Skip self-references for method generation - we'll use struct_name for those
        const is_self_reference = std.mem.eql(u8, rel.foreign_table, schema.name);

        // Use PascalCase non-singular to match struct names (Comments, not Comment)
        const related_struct_name = if (is_self_reference)
            try allocator.dupe(u8, struct_name)
        else
            try toPascalCaseNonSingular(allocator, rel.foreign_table);
        defer allocator.free(related_struct_name);

        // Create method name from relationship name: "user_posts" -> "Posts"
        const method_suffix = try hasManyMethodName(allocator, rel.name);
        defer allocator.free(method_suffix);

        // Generate fetchMany method
        try writer.print(
            \\    /// Fetch all related {s} records for this {s} (one-to-many)
            \\    pub fn fetch{s}(self: *const {s}, db: *pg.Pool, allocator: std.mem.Allocator) ![]{s} {{
            \\        const queryt = "SELECT * FROM {s} WHERE {s} = $1";
            \\        var result = try db.query(queryt, .{{self.{s}}});
            \\        defer result.deinit();
            \\
            \\        var list = std.ArrayList({s}){{}};
            \\        errdefer list.deinit(allocator);
            \\
            \\        while (try result.next()) |row| {{
            \\            const item = try row.to({s}, .{{ .allocator = allocator, .map = .ordinal }});
            \\            try list.append(allocator, item);
            \\        }}
            \\
            \\        return try list.toOwnedSlice(allocator);
            \\    }}
            \\
            \\
        , .{
            related_struct_name,
            struct_name,
            method_suffix,
            struct_name,
            related_struct_name,
            rel.foreign_table,
            rel.foreign_column,
            rel.local_column,
            related_struct_name,
            related_struct_name,
        });
    }
}

fn generateTransactionSupport(writer: anytype, struct_name: []const u8) !void {
    try writer.writeAll(
        \\    // Transaction support
        \\    pub const TransactionType = Transaction(
    );
    try writer.print("{s});\n\n", .{struct_name});

    try writer.writeAll("    pub fn beginTransaction(conn: *pg.Conn) !TransactionType {\n");
    try writer.writeAll("        return TransactionType.begin(conn);\n");
    try writer.writeAll("    }\n");
}

pub fn generateBarrelFile(allocator: std.mem.Allocator, schemas: []const TableSchema, output_dir: []const u8) !void {
    const file_name = try std.fmt.allocPrint(allocator, "{s}/root.zig", .{output_dir});
    defer allocator.free(file_name);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    try writer.writeAll("// AUTO-GENERATED CODE - DO NOT EDIT\n");
    try writer.writeAll("// Generated by scripts/generate_model.zig\n\n");

    for (schemas) |schema| {
        // Use non-singular PascalCase to match struct names (Users, Posts, Comments)
        const struct_name = try toPascalCaseNonSingular(allocator, schema.name);
        defer allocator.free(struct_name);

        const snake_case_name = try toLowerSnakeCase(allocator, schema.name);
        defer allocator.free(snake_case_name);

        try writer.print("pub const {s} = @import(\"{s}.zig\");\n", .{ struct_name, snake_case_name });
    }

    try std.fs.cwd().writeFile(.{ .sub_path = file_name, .data = output.items });
    std.debug.print("✅ Generated: {s}\n", .{file_name});
}
