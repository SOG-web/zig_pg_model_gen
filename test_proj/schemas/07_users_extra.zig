// Extra fields for users table - demonstrates schema merging
// This file adds additional fields to the users table defined in 01_users.zig

const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Table name for schema merging - SAME as 01_users.zig to merge into users table
pub const table_name = "users";

/// Build function - adds extra fields to users table
pub fn build(t: *TableSchema) void {
    // Add phone number field
    t.string(.{
        .name = "phone",
        .not_null = false,
        .create_input = .optional,
    });

    // Add bio field
    t.string(.{
        .name = "bio",
        .not_null = false,
        .create_input = .optional,
    });
}
