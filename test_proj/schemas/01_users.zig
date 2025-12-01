// User table schema definition
// Naming convention: XX_tablename.zig where XX is the order number

const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Build function called by the registry generator
pub fn build(t: *TableSchema) void {
    // Primary key - UUID auto-generated
    t.uuid(.{
        .name = "id",
        .primary_key = true,
        .unique = true,
        .create_input = .excluded,
        .update_input = false,
    });

    // User's email - required, unique
    t.string(.{
        .name = "email",
        .unique = true,
    });

    // User's name - required
    t.string(.{
        .name = "name",
    });

    // Password hash - required, redacted from JSON responses
    t.string(.{
        .name = "password_hash",
        .redacted = true,
    });

    // Is active flag
    t.boolean(.{
        .name = "is_active",
        .default_value = "true",
        .create_input = .optional,
    });

    // Timestamps - auto-generated
    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    t.dateTime(.{
        .name = "updated_at",
        .create_input = .excluded,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // Soft delete support
    t.dateTime(.{
        .name = "deleted_at",
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
    });

    // Relationship: one user has many posts
    t.foreign(.{
        .name = "user_posts",
        .column = "id",
        .references_table = "posts",
        .references_column = "user_id",
        .relationship_type = .one_to_many,
        .on_delete = .cascade,
    });
}
