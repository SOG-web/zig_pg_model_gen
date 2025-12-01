// Post table schema definition
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

    // Post title - required
    t.string(.{
        .name = "title",
    });

    // Post content - required
    t.string(.{
        .name = "content",
    });

    // Foreign key to users table
    t.uuid(.{
        .name = "user_id",
    });

    // Published flag
    t.boolean(.{
        .name = "is_published",
        .default_value = "false",
        .create_input = .optional,
    });

    // View count
    t.integer(.{
        .name = "view_count",
        .default_value = "0",
        .create_input = .excluded,
        .update_input = true,
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

    t.string(.{
        .name = "altered",
        .not_null = false,
        .create_input = .excluded,
        .update_input = false,
    });

    // Relationship: post belongs to user (many-to-one)
    t.foreign(.{
        .name = "post_author",
        .column = "user_id",
        .references_table = "users",
        .references_column = "id",
        .relationship_type = .many_to_one,
        .on_delete = .cascade,
    });

    // Add composite index on user_id and created_at for efficient queries
    t.addIndexes(&.{
        .{
            .name = "idx_posts_user_created",
            .columns = &.{ "user_id", "created_at" },
            .unique = false,
        },
    });

    t.alterField(.{
        .name = "altered",
        .type = .f64,
        .create_input = .optional,
        .update_input = true,
    });
}
