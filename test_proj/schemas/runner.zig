const std = @import("std");
const registry = @import("registry.zig");
const fluentorm = @import("fluentorm");
const sql_generator = fluentorm.sql_generator;
const model_generator = fluentorm.model_generator;
const snapshot = fluentorm.snapshot;
const diff = fluentorm.diff;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use merged schemas - multiple schema files with same table_name are combined
    const schemas = try registry.getAllSchemas(allocator);
    defer {
        for (schemas) |*s| s.deinit();
        allocator.free(schemas);
    }

    const output_dir = "src/models/generated";
    const sql_output_dir = "migrations";
    const snapshot_file = "schemas/.fluent_snapshot.json";

    try std.fs.cwd().makePath(output_dir);
    try std.fs.cwd().makePath(sql_output_dir);

    // Create snapshot of current schema state
    const current_snapshot = try snapshot.createDatabaseSnapshot(allocator, schemas);
    defer current_snapshot.deinit(allocator);

    // Try to load previous snapshot
    const prev_snapshot_result = try snapshot.loadSnapshot(allocator, snapshot_file);

    // Compute diff and generate migrations
    if (prev_snapshot_result) |prev| {
        defer prev.deinit();

        const schema_diff = try diff.diffSnapshots(allocator, prev.value, current_snapshot);
        defer schema_diff.deinit(allocator);

        if (schema_diff.has_changes) {
            // Generate incremental migration files - one per change
            const generated_files = try sql_generator.writeIncrementalMigrationFiles(allocator, schema_diff, sql_output_dir);
            defer {
                for (generated_files) |f| allocator.free(f);
                allocator.free(generated_files);
            }

            std.debug.print("Generated {d} migration file(s):\n", .{generated_files.len});
            for (generated_files) |f| {
                std.debug.print("  - {s}\n", .{f});
            }
        } else {
            std.debug.print("No schema changes detected.\n", .{});
        }
    } else {
        // First run - generate initial migration with all tables
        const schema_diff = try diff.diffSnapshots(allocator, null, current_snapshot);
        defer schema_diff.deinit(allocator);

        if (schema_diff.has_changes) {
            // Generate incremental migration files - one per change
            const generated_files = try sql_generator.writeIncrementalMigrationFiles(allocator, schema_diff, sql_output_dir);
            defer {
                for (generated_files) |f| allocator.free(f);
                allocator.free(generated_files);
            }

            std.debug.print("Generated {d} initial migration file(s):\n", .{generated_files.len});
            for (generated_files) |f| {
                std.debug.print("  - {s}\n", .{f});
            }
        }
    }

    // Save current snapshot for next run
    try snapshot.saveSnapshot(allocator, current_snapshot, snapshot_file);
    std.debug.print("Snapshot saved to {s}\n", .{snapshot_file});

    // Generate models (always)
    for (schemas) |schema_item| {
        const schema_file = try std.fmt.allocPrint(allocator, "{s}.zig", .{schema_item.name});
        defer allocator.free(schema_file);
        try model_generator.generateModel(allocator, schema_item, schema_file, output_dir);
    }

    try model_generator.generateBarrelFile(allocator, schemas, output_dir);
    std.debug.print("Models generated in {s}\n", .{output_dir});
}
