// Model Generator - Generates Zig model files from JSON schema definitions
const std = @import("std");

const schema_mod = @import("schema");
const Schema = schema_mod.Schema;
const Field = schema_mod.Field;
const FieldType = schema_mod.FieldType;
const InputMode = schema_mod.InputMode;
const Index = schema_mod.Index;
const Relationship = schema_mod.Relationship;

const json_parser = @import("json_parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <schemas_directory> [output_directory]\n", .{args[0]});
        std.debug.print("Example: {s} schemas src/db/models/generated\n", .{args[0]});
        std.debug.print("\nArguments:\n", .{});
        std.debug.print("  schemas_directory  - Directory containing JSON schema files\n", .{});
        std.debug.print("  output_directory   - Where to generate models (default: ../src/db/models/generated)\n", .{});
        return error.MissingArgument;
    }

    const schemas_dir = args[1];
    const output_dir = if (args.len >= 3) args[2] else "../src/db/models/generated";

    std.debug.print("Scanning schemas directory: {s}\n", .{schemas_dir});
    std.debug.print("Output directory: {s}\n\n", .{output_dir});

    // Open schemas directory
    var dir = std.fs.cwd().openDir(schemas_dir, .{ .iterate = true }) catch |err| {
        std.debug.print("❌ Error: Cannot open directory '{s}': {}\n", .{ schemas_dir, err });
        return err;
    };
    defer dir.close();

    // Iterate through all JSON schema files
    var iterator = dir.iterate();
    var count: usize = 0;

    while (try iterator.next()) |entry| {
        // Only process .json files
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        const schema_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ schemas_dir, entry.name });
        defer allocator.free(schema_path);

        std.debug.print("📄 Processing: {s}\n", .{schema_path});

        // Read JSON file
        const file = std.fs.cwd().openFile(schema_path, .{}) catch |err| {
            std.debug.print("  ❌ Error opening file: {}\n\n", .{err});
            continue;
        };
        defer file.close();

        const json_content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            std.debug.print("  ❌ Error reading file: {}\n\n", .{err});
            continue;
        };
        defer allocator.free(json_content);

        // Parse JSON schema
        const schema = json_parser.parseJsonSchema(allocator, json_content) catch |err| {
            std.debug.print("  ❌ Schema validation failed: {}\n\n", .{err});
            continue;
        };
        defer {
            // Free schema data after use
            allocator.free(schema.table_name);
            allocator.free(schema.struct_name);
            for (schema.fields) |field| {
                allocator.free(field.name);
                if (field.default_value) |dv| {
                    allocator.free(dv);
                }
            }
            allocator.free(schema.fields);
            for (schema.indexes) |index| {
                allocator.free(index.name);
                for (index.columns) |col| {
                    allocator.free(col);
                }
                allocator.free(index.columns);
            }
            allocator.free(schema.indexes);
            for (schema.relationships) |rel| {
                allocator.free(rel.name);
                allocator.free(rel.column);
                allocator.free(rel.references_table);
                allocator.free(rel.references_column);
            }
            allocator.free(schema.relationships);
        }

        // Generate model
        try generateModel(allocator, schema, schema_path, output_dir);
        count += 1;
        std.debug.print("\n", .{});
    }

    if (count == 0) {
        std.debug.print("⚠️  No models generated\n", .{});
        std.debug.print("Make sure:\n", .{});
        std.debug.print("  1. Schema files have .json extension\n", .{});
        std.debug.print("  2. JSON is valid and follows the schema format\n", .{});
        std.debug.print("  3. Schema directory exists and is readable\n", .{});
    } else {
        // Copy base.zig to output directory if it doesn't exist
        try copyBaseModel(allocator, output_dir);
        std.debug.print("✅ Successfully generated {d} model(s)\n", .{count});
    }
}

/// Copy base.zig, query.zig, and transaction.zig to the output directory
fn copyBaseModel(allocator: std.mem.Allocator, output_dir: []const u8) !void {
    const base_dest_path = try std.fmt.allocPrint(allocator, "{s}/base.zig", .{output_dir});
    const query_builder_dest_path = try std.fmt.allocPrint(allocator, "{s}/query.zig", .{output_dir});
    const transaction_dest_path = try std.fmt.allocPrint(allocator, "{s}/transaction.zig", .{output_dir});
    defer allocator.free(base_dest_path);
    defer allocator.free(query_builder_dest_path);
    defer allocator.free(transaction_dest_path);

    // Embed source files directly into the executable
    const base_content = @embedFile("base.zig");
    const query_content = @embedFile("query.zig");
    const transaction_content = @embedFile("transaction.zig");

    // Write to output directory (always overwrite to ensure latest version)
    try std.fs.cwd().writeFile(.{
        .sub_path = base_dest_path,
        .data = base_content,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = query_builder_dest_path,
        .data = query_content,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = transaction_dest_path,
        .data = transaction_content,
    });

    std.debug.print("📦 Bundled base.zig to {s}\n", .{base_dest_path});
    std.debug.print("📦 Bundled query.zig to {s}\n", .{query_builder_dest_path});
    std.debug.print("📦 Bundled transaction.zig to {s}\n", .{transaction_dest_path});
}

fn generateModel(allocator: std.mem.Allocator, schema: Schema, schema_file: []const u8, output_dir: []const u8) !void {

    // Ensure output directory exists
    std.fs.cwd().makePath(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating directory '{s}': {}\n", .{ output_dir, err });
            return err;
        }
    };

    // Generate file name from struct name
    const snake_case_name = try toLowerSnakeCase(allocator, schema.struct_name);
    defer allocator.free(snake_case_name);
    const file_name = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ output_dir, snake_case_name });
    defer allocator.free(file_name);

    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);
    const writer = output.writer(allocator);

    // Generate header
    try generateHeader(writer, schema_file);

    // Generate imports
    try generateImports(writer, schema, allocator);

    // Generate struct definition
    try generateStructDefinition(writer, schema, allocator);

    // Generate CreateInput
    try generateCreateInput(writer, schema, allocator);

    // Generate UpdateInput
    try generateUpdateInput(writer, schema, allocator);

    // Generate SQL methods
    try generateSQLMethods(writer, schema, allocator);

    // Generate base
    try generateBaseModelWrapper(writer, schema);

    // Generate DDL wrappers
    try generateDDLWrappers(writer);

    // Generate CRUD wrappers
    try generateCRUDWrappers(writer, schema);

    // Generate JSON response helpers
    try generateJsonResponseHelpers(writer, schema);

    // Generate relationship methods
    try generateRelationshipMethods(writer, schema, allocator);

    // Generate transaction support
    try generateTransactionSupport(writer, schema);

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

fn generateImports(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    try writer.writeAll(
        \\const std = @import("std");
        \\const pg = @import("pg");
        \\const BaseModel = @import("base.zig").BaseModel;
        \\const QueryBuilder = @import("query.zig").QueryBuilder;
        \\const Transaction = @import("transaction.zig").Transaction;
        \\
    );

    // Add imports for related models
    if (schema.relationships.len > 0) {
        try writer.writeAll("\n// Related models\n");

        var seen_tables = std.StringHashMap(void).init(allocator);
        defer seen_tables.deinit();

        for (schema.relationships) |rel| {
            // Only add each import once
            if (!seen_tables.contains(rel.references_table)) {
                try seen_tables.put(rel.references_table, {});

                const struct_name = try tableToPascalCase(allocator, rel.references_table);
                defer allocator.free(struct_name);

                // Convert struct name to snake_case for filename
                const file_name = try toLowerSnakeCase(allocator, struct_name);
                defer allocator.free(file_name);

                try writer.print("const {s} = @import(\"{s}.zig\").{s};\n", .{
                    struct_name,
                    file_name,
                    struct_name,
                });
            }
        }
    }

    try writer.writeAll("\n");
}

fn generateStructDefinition(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.print("const {s} = @This();\n\n", .{schema.struct_name});
    try writer.writeAll("    // Fields\n");

    for (schema.fields) |field| {
        try writer.print("{s}: {s},\n", .{ field.name, field.type.toZigType() });
    }

    try writer.writeAll("\n\n");
}

fn generateCreateInput(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.writeAll("    // Input type for creating new records\n");
    try writer.writeAll("    pub const CreateInput = struct {\n");

    for (schema.fields) |field| {
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

fn generateUpdateInput(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.writeAll("    // Input type for updating existing records\n");
    try writer.writeAll("    pub const UpdateInput = struct {\n");

    for (schema.fields) |field| {
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

fn generateSQLMethods(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    // tableName
    try writer.print(
        \\    // Model configuration
        \\    pub fn tableName() []const u8 {{
        \\        return "{s}";
        \\    }}
        \\
        \\
    , .{schema.table_name});

    // createTableSQL
    try generateCreateTableSQL(writer, schema, allocator);

    // Index SQL
    try generateIndexSQL(writer, schema);

    // insertSQL
    try generateInsertSQL(writer, schema, allocator);

    // updateSQL
    try generateUpdateSQL(writer, schema, allocator);

    // upsertSQL
    try generateUpsertSQL(writer, schema, allocator);
}

fn generateCreateTableSQL(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    _ = allocator;
    try writer.writeAll("    pub fn createTableSQL() []const u8 {\n");
    try writer.writeAll("        return\n");
    try writer.print("            \\\\CREATE TABLE IF NOT EXISTS {s} (\n", .{schema.table_name});

    // Count how many FK constraints we'll actually create
    var fk_count: usize = 0;
    for (schema.relationships) |rel| {
        const should_create_fk = switch (rel.relationship_type) {
            .many_to_one => true,
            .one_to_one => !std.mem.eql(u8, rel.column, "id"),
            .one_to_many, .many_to_many => false,
        };
        if (should_create_fk) {
            fk_count += 1;
        }
    }

    // Generate column definitions
    for (schema.fields, 0..) |field, i| {
        const is_last = (i == schema.fields.len - 1) and (fk_count == 0);

        // Column definition
        try writer.print("            \\\\    {s} {s}", .{ field.name, field.type.toPgType() });

        // Constraints
        if (field.primary_key) {
            try writer.writeAll(" PRIMARY KEY");
        }
        if (field.not_null and !field.type.isOptional()) {
            try writer.writeAll(" NOT NULL");
        }
        if (field.unique and !field.primary_key) {
            try writer.writeAll(" UNIQUE");
        }
        if (field.default_value) |default| {
            try writer.print(" DEFAULT {s}", .{default});
        }

        if (!is_last) {
            try writer.writeAll(",\n");
        } else if (fk_count == 0) {
            try writer.writeAll("\n");
        } else {
            try writer.writeAll(",\n");
        }
    }

    // Generate foreign key constraints
    // Only for many_to_one and one_to_one (forward) where this table has the FK column
    // Skip one_to_many and one_to_one (reverse) - those are in the other table
    if (fk_count > 0) {
        var current_fk: usize = 0;
        for (schema.relationships) |rel| {
            const should_create_fk = switch (rel.relationship_type) {
                .many_to_one => true,
                .one_to_one => !std.mem.eql(u8, rel.column, "id"),
                .one_to_many, .many_to_many => false,
            };

            if (!should_create_fk) continue;

            const is_last = (current_fk == fk_count - 1);
            current_fk += 1;

            try writer.print("            \\\\    CONSTRAINT {s} FOREIGN KEY ({s}) REFERENCES {s}({s})", .{
                rel.name,
                rel.column,
                rel.references_table,
                rel.references_column,
            });

            // Add ON DELETE action if not NO ACTION
            if (rel.on_delete != .no_action) {
                try writer.print(" ON DELETE {s}", .{rel.on_delete.toSQL()});
            }

            // Add ON UPDATE action if not NO ACTION
            if (rel.on_update != .no_action) {
                try writer.print(" ON UPDATE {s}", .{rel.on_update.toSQL()});
            }

            if (!is_last) {
                try writer.writeAll(",\n");
            } else {
                try writer.writeAll("\n");
            }
        }
    }

    try writer.writeAll("            \\\\)\n");
    try writer.writeAll("        ;\n");
    try writer.writeAll("    }\n\n");
}

fn generateIndexSQL(writer: anytype, schema: Schema) !void {
    if (schema.indexes.len == 0) return;

    try writer.writeAll("    pub fn createIndexSQL() []const []const u8 {\n");
    try writer.writeAll("        return &[_][]const u8{\n");

    for (schema.indexes) |index| {
        const cols = try std.mem.join(std.heap.page_allocator, ", ", index.columns);
        defer std.heap.page_allocator.free(cols);

        if (index.unique) {
            try writer.print("            \"CREATE UNIQUE INDEX IF NOT EXISTS {s} ON {s} ({s})\",\n", .{ index.name, schema.table_name, cols });
        } else {
            try writer.print("            \"CREATE INDEX IF NOT EXISTS {s} ON {s} ({s})\",\n", .{ index.name, schema.table_name, cols });
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");

    try writer.writeAll("    pub fn dropIndexSQL() []const []const u8 {\n");
    try writer.writeAll("        return &[_][]const u8{\n");

    for (schema.indexes) |index| {
        try writer.print("            \"DROP INDEX IF EXISTS {s}\",\n", .{index.name});
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateInsertSQL(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
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
    for (schema.fields) |field| {
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
    try writer.print("            \\\\INSERT INTO {s} (\n", .{schema.table_name});
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

    for (schema.fields) |field| {
        if (field.create_input != .excluded) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateUpdateSQL(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var updates = std.ArrayList([]const u8){};
    defer updates.deinit(arena_allocator);
    var param_types = std.ArrayList([]const u8){};
    defer param_types.deinit(arena_allocator);

    try param_types.append(arena_allocator, "[]const u8"); // ID parameter

    var param_num: usize = 2;
    for (schema.fields) |field| {
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
    try writer.print("            \\\\UPDATE {s} SET\n", .{schema.table_name});

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

    for (schema.fields) |field| {
        if (field.update_input) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateUpsertSQL(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    // Find unique field for ON CONFLICT
    var unique_field: ?[]const u8 = null;
    for (schema.fields) |field| {
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
    for (schema.fields) |field| {
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
    try writer.print("            \\\\INSERT INTO {s} (\n", .{schema.table_name});
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
    for (schema.fields) |field| {
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

    for (schema.fields) |field| {
        if (field.create_input != .excluded) {
            try writer.print("            data.{s},\n", .{field.name});
        }
    }

    try writer.writeAll("        };\n");
    try writer.writeAll("    }\n\n");
}

fn generateBaseModelWrapper(writer: anytype, schema: Schema) !void {
    try writer.print("    const base = BaseModel({s});\n", .{schema.struct_name});
}

fn generateDDLWrappers(writer: anytype) !void {
    try writer.writeAll(
        \\    // DDL operations
        \\    pub const createTable = base.createTable;
        \\
        \\    pub const dropTable = base.dropTable;
        \\
        \\    pub const createIndexes = base.createIndexes;
        \\
        \\    pub const dropIndexes = base.dropIndexes;
        \\
        \\    pub const truncate = base.truncate;
        \\
        \\    pub const tableExists = base.tableExists;
        \\
        \\
    );
}

fn generateCRUDWrappers(writer: anytype, schema: Schema) !void {
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

    try writer.print("    pub fn query() QueryBuilder({s}, UpdateInput) {{\n", .{schema.struct_name});
    try writer.print("        return QueryBuilder({s}, UpdateInput).init();\n", .{schema.struct_name});
    try writer.writeAll("    }\n\n");
}

fn generateJsonResponseHelpers(writer: anytype, schema: Schema) !void {
    const struct_name = schema.struct_name;

    // Generate JsonResponse struct with UUIDs as hex strings
    try writer.writeAll("\n    /// JSON-safe response struct with UUIDs as hex strings\n");
    try writer.writeAll("    pub const JsonResponse = struct {\n");

    for (schema.fields) |field| {
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

    for (schema.fields) |field| {
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

    for (schema.fields) |field| {
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

    for (schema.fields) |field| {
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

fn generateRelationshipMethods(writer: anytype, schema: Schema, allocator: std.mem.Allocator) !void {
    if (schema.relationships.len == 0) return;

    try writer.writeAll("    // Relationship methods\n");

    for (schema.relationships) |rel| {
        const related_struct_name = try tableToPascalCase(allocator, rel.references_table);
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
                    schema.struct_name,
                    method_suffix,
                    schema.struct_name,
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
                        schema.struct_name,
                        method_suffix,
                        schema.struct_name,
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
                        schema.struct_name,
                        method_suffix,
                        schema.struct_name,
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
                    schema.struct_name,
                    method_suffix,
                    schema.struct_name,
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

    // Note: We don't generate findByIdWithRelations anymore
    // because relationship fields are not part of the struct to avoid circular dependencies.
    // Users should fetch relationships individually using fetch*() methods as needed.
}

fn generateTransactionSupport(writer: anytype, schema: Schema) !void {
    try writer.writeAll(
        \\    // Transaction support
        \\    pub const TransactionType = Transaction(
    );
    try writer.print("{s});\n\n", .{schema.struct_name});

    try writer.writeAll("    pub fn beginTransaction(conn: *pg.Conn) !TransactionType {\n");
    try writer.writeAll("        return TransactionType.begin(conn);\n");
    try writer.writeAll("    }\n");
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
