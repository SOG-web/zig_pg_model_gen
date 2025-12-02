// Model Generator - Generates Zig model files from schema definitions
//
// This CLI generates:
// 1. registry.zig - Auto-imports all schema files
// 2. runner.zig - Script to generate models (user runs this via build.zig)
//
// Usage: fluentzig-gen <schemas_directory> [output_directory]
// Then add a build step to run the generated runner.zig

const std = @import("std");

const generateRegistry = @import("registry_generator.zig").generateRegistry;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <schemas_directory> <output_directory> <sql_output_directory>\n", .{args[0]});
        std.debug.print("Example: {s} schemas src/models/generated migrations\n", .{args[0]});
        std.debug.print("\nThis generates registry.zig and runner.zig in the schemas directory.\n", .{});
        std.debug.print("Then add a build step in your build.zig to run the runner.\n", .{});
        return error.MissingArgument;
    }

    const schemas_dir = args[1];
    const output_dir = if (args.len >= 3) args[2] else "src/models/generated";
    const sql_output_dir = if (args.len >= 4) args[3] else "migrations";

    std.debug.print("Scanning schemas directory: {s}\n", .{schemas_dir});
    std.debug.print("Output directory for models: {s}\n\n", .{output_dir});

    // 1. Generate Registry
    const registry_path = try std.fmt.allocPrint(allocator, "{s}/registry.zig", .{schemas_dir});
    defer allocator.free(registry_path);

    try generateRegistry(schemas_dir, registry_path);
    std.debug.print("✅ Generated registry at {s}\n", .{registry_path});

    // 2. Generate Runner Script
    const runner_path = try std.fmt.allocPrint(allocator, "{s}/runner.zig", .{schemas_dir});
    defer allocator.free(runner_path);

    try generateRunner(
        allocator,
        runner_path,
        output_dir,
        sql_output_dir,
        schemas_dir,
    );
    std.debug.print("✅ Generated runner at {s}\n", .{runner_path});

    // Copy base model files to output directory
    try copyBaseModel(allocator, output_dir);

    // 3. Print next steps for the user
    std.debug.print("\n🎉 Generation complete!\n", .{});
    std.debug.print("\n📋 Next steps:\n", .{});
    std.debug.print("   Add this to your build.zig to run the model generator:\n\n", .{});
    std.debug.print("   // Model runner step\n", .{});
    std.debug.print("   const runner_exe = b.addExecutable(.{{\n", .{});
    std.debug.print("       .name = \"model-runner\",\n", .{});
    std.debug.print("       .root_module = b.createModule(.{{\n", .{});
    std.debug.print("           .root_source_file = b.path(\"{s}\"),\n", .{runner_path});
    std.debug.print("           .target = target,\n", .{});
    std.debug.print("           .optimize = optimize,\n", .{});
    std.debug.print("           .imports = &.{{\n", .{});
    std.debug.print("               .{{ .name = \"fluentorm\", .module = fluentorm }},\n", .{});
    std.debug.print("           }},\n", .{});
    std.debug.print("       }}),\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   const run_runner = b.step(\"generate-models\", \"Generate models from schemas\");\n", .{});
    std.debug.print("   run_runner.dependOn(&b.addRunArtifact(runner_exe).step);\n\n", .{});
    std.debug.print("   Then run: zig build generate-models\n", .{});
}

fn generateRunner(
    allocator: std.mem.Allocator,
    output_path: []const u8,
    output_dir: []const u8,
    sql_output_dir: []const u8,
    schemas_dir: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    const content = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\const registry = @import("registry.zig");
        \\const fluentorm = @import("fluentorm");
        \\const sql_generator = fluentorm.sql_generator;
        \\const model_generator = fluentorm.model_generator;
        \\const snapshot = fluentorm.snapshot;
        \\const diff = fluentorm.diff;
        \\
        \\pub fn main() !void {{
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\
        \\    // Use merged schemas - multiple schema files with same table_name are combined
        \\    const schemas = try registry.getAllSchemas(allocator);
        \\    defer {{
        \\        for (schemas) |*s| s.deinit();
        \\        allocator.free(schemas);
        \\    }}
        \\
        \\    const output_dir = "{s}";
        \\    const sql_output_dir = "{s}";
        \\    const snapshot_file = "{s}/.fluent_snapshot.json";
        \\
        \\    try std.fs.cwd().makePath(output_dir);
        \\    try std.fs.cwd().makePath(sql_output_dir);
        \\
        \\    // Create snapshot of current schema state
        \\    const current_snapshot = try snapshot.createDatabaseSnapshot(allocator, schemas);
        \\    defer current_snapshot.deinit(allocator);
        \\
        \\    // Try to load previous snapshot
        \\    const prev_snapshot_result = try snapshot.loadSnapshot(allocator, snapshot_file);
        \\
        \\    // Compute diff and generate migrations
        \\    if (prev_snapshot_result) |prev| {{
        \\        defer prev.deinit();
        \\
        \\        const schema_diff = try diff.diffSnapshots(allocator, prev.value, current_snapshot);
        \\        defer schema_diff.deinit(allocator);
        \\
        \\        if (schema_diff.has_changes) {{
        \\            // Generate incremental migration files - one per change
        \\            const generated_files = try sql_generator.writeIncrementalMigrationFiles(allocator, schema_diff, sql_output_dir);
        \\            defer {{
        \\                for (generated_files) |f| allocator.free(f);
        \\                allocator.free(generated_files);
        \\            }}
        \\
        \\            std.debug.print("Generated {{d}} migration file(s):\n", .{{generated_files.len}});
        \\            for (generated_files) |f| {{
        \\                std.debug.print("  - {{s}}\n", .{{f}});
        \\            }}
        \\        }} else {{
        \\            std.debug.print("No schema changes detected.\n", .{{}});
        \\        }}
        \\    }} else {{
        \\        // First run - generate initial migration with all tables
        \\        const schema_diff = try diff.diffSnapshots(allocator, null, current_snapshot);
        \\        defer schema_diff.deinit(allocator);
        \\
        \\        if (schema_diff.has_changes) {{
        \\            // Generate incremental migration files - one per change
        \\            const generated_files = try sql_generator.writeIncrementalMigrationFiles(allocator, schema_diff, sql_output_dir);
        \\            defer {{
        \\                for (generated_files) |f| allocator.free(f);
        \\                allocator.free(generated_files);
        \\            }}
        \\
        \\            std.debug.print("Generated {{d}} initial migration file(s):\n", .{{generated_files.len}});
        \\            for (generated_files) |f| {{
        \\                std.debug.print("  - {{s}}\n", .{{f}});
        \\            }}
        \\        }}
        \\    }}
        \\
        \\    // Save current snapshot for next run
        \\    try snapshot.saveSnapshot(allocator, current_snapshot, snapshot_file);
        \\    std.debug.print("Snapshot saved to {{s}}\n", .{{snapshot_file}});
        \\
        \\    // Generate models (always)
        \\    for (schemas) |schema_item| {{
        \\        const schema_file = try std.fmt.allocPrint(allocator, "{{s}}.zig", .{{schema_item.name}});
        \\        defer allocator.free(schema_file);
        \\        try model_generator.generateModel(allocator, schema_item, schema_file, output_dir);
        \\    }}
        \\
        \\    try model_generator.generateBarrelFile(allocator, schemas, output_dir);
        \\    std.debug.print("Models generated in {{s}}\n", .{{output_dir}});
        \\}}
        \\
    , .{ output_dir, sql_output_dir, schemas_dir });
    defer allocator.free(content);

    try file.writeAll(content);
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

    // Ensure output directory exists
    std.fs.cwd().makePath(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

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
