const std = @import("std");

const pg = @import("pg");

const QueryBuilder = @import("query.zig").QueryBuilder;

/// Base Model provides common database operations for any model type
/// Note: This is used internally by generated models.
/// For custom extensions, create wrapper structs (see docs/EXTENDING_MODELS.md)
pub fn BaseModel(comptime T: type) type {
    if (!@hasDecl(T, "tableName")) {
        @compileError("Struct must have a tableName field");
    }
    return struct {
        /// Creates the table for this model
        pub fn createTable(db: *pg.Pool) !void {
            if (!@hasDecl(T, "createTableSQL")) {
                @compileError("Model must implement 'createTableSQL() []const u8'");
            }
            const sql = T.createTableSQL();
            _ = try db.exec(sql, .{});
        }

        /// Drops the table for this model
        pub fn dropTable(db: *pg.Pool) !void {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "DROP TABLE IF EXISTS {s}", .{table_name});
            _ = try db.exec(sql, .{});
        }

        /// Creates all indexes for this model
        pub fn createIndexes(db: *pg.Pool) !void {
            if (@hasDecl(T, "createIndexSQL")) {
                const indexes = T.createIndexSQL();
                for (indexes) |index_sql| {
                    _ = try db.exec(index_sql, .{});
                }
            }
        }

        /// Drops all indexes for this model
        pub fn dropIndexes(db: *pg.Pool) !void {
            if (@hasDecl(T, "dropIndexSQL")) {
                const indexes = T.dropIndexSQL();
                for (indexes) |index_sql| {
                    _ = try db.exec(index_sql, .{});
                }
            }
        }

        /// Truncates the table (removes all data but keeps structure)
        pub fn truncate(db: *pg.Pool) !void {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "TRUNCATE TABLE {s}", .{table_name});
            _ = try db.exec(sql, .{});
        }

        /// Checks if the table exists
        pub fn tableExists(db: *pg.Pool) !bool {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            const table_name = T.tableName();
            const sql =
                \\SELECT EXISTS (
                \\    SELECT FROM information_schema.tables
                \\    WHERE table_schema = 'public'
                \\    AND table_name = $1
                \\)
            ;
            const result = try db.query(sql, .{table_name});
            defer result.deinit();
            // Parse result to get boolean (implementation depends on pg library)
            return false; // TODO: parse result
        }

        /// Find a record by ID
        pub fn findById(db: *pg.Pool, allocator: std.mem.Allocator, id: []const u8) !?T {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            const table_name = T.tableName();

            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            // Check if model has deleted_at field for soft delete support
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (has_deleted_at)
                try std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE id = $1 AND deleted_at IS NULL", .{table_name})
            else
                try std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE id = $1", .{table_name});

            var result = try db.queryOpts(sql, .{id}, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(T, .{
                .allocator = allocator,
            });
            // Use pg.zig's built-in row.to() for mapping
            if (try mapper.next()) |item| {
                return item;
            }
            return null;
        }

        /// Find all records (optionally filtered by deleted_at)
        pub fn findAll(db: *pg.Pool, allocator: std.mem.Allocator, include_deleted: bool) ![]T {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            const table_name = T.tableName();

            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            // Check if model has deleted_at field for soft delete support
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (!has_deleted_at or include_deleted)
                try std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s}", .{table_name})
            else
                try std.fmt.allocPrint(temp_allocator, "SELECT * FROM {s} WHERE deleted_at IS NULL", .{table_name});

            var result = try db.queryOpts(sql, .{}, .{
                .column_names = true,
            });
            defer result.deinit();

            // Use pg.zig's built-in row.to() for mapping
            var items = std.ArrayList(T){};
            errdefer items.deinit(allocator);

            var mapper = result.mapper(T, .{ .allocator = allocator });
            while (try mapper.next()) |item| {
                try items.append(allocator, item);
            }
            return try items.toOwnedSlice(allocator);
        }

        /// Insert a new record using CreateInput type
        /// Models should define a CreateInput type with only user-provided fields
        pub fn insert(db: *pg.Pool, allocator: std.mem.Allocator, data: anytype) ![]const u8 {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            const sql = T.insertSQL();
            const params = T.insertParams(data);

            var result = try db.query(sql, params);
            defer result.deinit();

            // Get the returned ID from INSERT...RETURNING
            if (try result.next()) |row| {
                const id = row.get([]const u8, 0); // ID is first column in RETURNING
                return try allocator.dupe(u8, id);
            }

            return error.InsertFailed;
        }

        /// Insert a new record and return the full model
        pub fn insertAndReturn(db: *pg.Pool, allocator: std.mem.Allocator, data: anytype) !T {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "insertSQL")) {
                @compileError("Model must implement 'insertSQL() []const u8'");
            }
            if (!@hasDecl(T, "insertParams")) {
                @compileError("Model must implement 'insertParams(data: CreateInput) anytype'");
            }

            // Build SQL with RETURNING *
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.insertSQL();
            // Replace "RETURNING id" with "RETURNING *"
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING id")) |_| {
                    break :blk try std.mem.replaceOwned(u8, temp_allocator, base_sql, "RETURNING id", "RETURNING *");
                }
                break :blk base_sql;
            };

            const params = T.insertParams(data);

            var result = try db.queryOpts(sql, params, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(T, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }

            return error.InsertFailed;
        }

        /// Update an existing record
        pub fn update(db: *pg.Pool, id: []const u8, data: anytype) !void {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "updateSQL")) {
                @compileError("Model must implement 'updateSQL() []const u8'");
            }
            if (!@hasDecl(T, "updateParams")) {
                @compileError("Model must implement 'updateParams(id: []const u8, data: UpdateInput) anytype'");
            }

            const sql = T.updateSQL();
            const params = T.updateParams(id, data);

            _ = try db.exec(sql, params);
        }

        /// Update an existing record and return the full updated model
        pub fn updateAndReturn(db: *pg.Pool, allocator: std.mem.Allocator, id: []const u8, data: anytype) !T {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "updateSQL")) {
                @compileError("Model must implement 'updateSQL() []const u8'");
            }
            if (!@hasDecl(T, "updateParams")) {
                @compileError("Model must implement 'updateParams(id: []const u8, data: UpdateInput) anytype'");
            }

            // Build SQL with RETURNING *
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.updateSQL();
            // Append RETURNING * if not already present
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING")) |_| {
                    break :blk base_sql;
                }
                break :blk try std.fmt.allocPrint(temp_allocator, "{s} RETURNING *", .{base_sql});
            };

            const params = T.updateParams(id, data);

            var result = try db.queryOpts(sql, params, .{
                .column_names = true,
            });
            defer result.deinit();

            var mapper = result.mapper(T, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }

            return error.UpdateFailed;
        }

        /// Upsert (insert or update) a record
        pub fn upsert(db: *pg.Pool, allocator: std.mem.Allocator, data: anytype) ![]const u8 {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "upsertSQL")) {
                @compileError("Model must implement 'upsertSQL() []const u8'");
            }
            if (!@hasDecl(T, "upsertParams")) {
                @compileError("Model must implement 'upsertParams(data: CreateInput) anytype'");
            }

            const sql = T.upsertSQL();
            const params = T.upsertParams(data);

            var result = try db.query(sql, params);
            defer result.deinit();

            // Get the returned ID from UPSERT...RETURNING
            if (try result.next()) |row| {
                const id = row.get([]const u8, 0);
                return try allocator.dupe(u8, id);
            }

            return error.UpsertFailed;
        }

        /// Upsert (insert or update) a record and return the full model
        pub fn upsertAndReturn(db: *pg.Pool, allocator: std.mem.Allocator, data: anytype) !T {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            if (!@hasDecl(T, "upsertSQL")) {
                @compileError("Model must implement 'upsertSQL() []const u8'");
            }
            if (!@hasDecl(T, "upsertParams")) {
                @compileError("Model must implement 'upsertParams(data: CreateInput) anytype'");
            }

            // Build SQL with RETURNING *
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const base_sql = T.upsertSQL();
            // Replace "RETURNING id" with "RETURNING *"
            const sql = blk: {
                if (std.mem.indexOf(u8, base_sql, "RETURNING id")) |_| {
                    break :blk try std.mem.replaceOwned(u8, temp_allocator, base_sql, "RETURNING id", "RETURNING *");
                }
                break :blk base_sql;
            };

            const params = T.upsertParams(data);

            var result = try db.queryOpts(sql, params, .{ .column_names = true });
            defer result.deinit();

            var mapper = result.mapper(T, .{ .allocator = allocator });
            if (try mapper.next()) |item| {
                return item;
            }

            return error.UpsertFailed;
        }

        /// Soft delete a record (sets deleted_at timestamp)
        pub fn softDelete(db: *pg.Pool, id: []const u8) !void {
            if (!@hasField(T, "deleted_at")) {
                @compileError("Model must have 'deleted_at' field to support soft delete");
            }
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "UPDATE {s} SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1", .{table_name});
            _ = try db.exec(sql, .{id});
        }

        /// Hard delete a record (permanently removes from database)
        pub fn hardDelete(db: *pg.Pool, id: []const u8) !void {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();
            const sql = try std.fmt.allocPrint(temp_allocator, "DELETE FROM {s} WHERE id = $1", .{table_name});
            _ = try db.exec(sql, .{id});
        }

        /// Count records in the table
        pub fn count(db: *pg.Pool, include_deleted: bool) !i64 {
            if (!@hasDecl(T, "tableName")) {
                @compileError("Model must implement 'tableName() []const u8'");
            }
            // Use arena for temporary SQL string
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const temp_allocator = arena.allocator();

            const table_name = T.tableName();

            // Check if model has deleted_at field for soft delete support
            const has_deleted_at = @hasField(T, "deleted_at");
            const sql = if (!has_deleted_at or include_deleted)
                try std.fmt.allocPrint(temp_allocator, "SELECT COUNT(*) FROM {s}", .{table_name})
            else
                try std.fmt.allocPrint(temp_allocator, "SELECT COUNT(*) FROM {s} WHERE deleted_at IS NULL", .{table_name});

            var result = try db.query(sql, .{});
            defer result.deinit();

            // Parse count result
            if (try result.next()) |row| {
                return row.get(i64, 0);
            }

            return 0;
        }

        /// From row
        pub fn fromRow(row: anytype, allocator: std.mem.Allocator) !T {
            return row.to(T, .{ .allocator = allocator });
        }
    };
}
