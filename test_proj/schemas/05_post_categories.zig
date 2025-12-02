// PostCategory junction table schema definition
// Many-to-many relationship between posts and categories

const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Table name for schema merging - multiple schemas with same table_name will be merged
pub const table_name = "post_categories";

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

    // Foreign key to posts table
    t.uuid(.{
        .name = "post_id",
    });

    // Foreign key to categories table
    t.uuid(.{
        .name = "category_id",
    });

    // Timestamps
    t.dateTime(.{
        .name = "created_at",
        .create_input = .excluded,
        .update_input = false,
        .default_value = "CURRENT_TIMESTAMP",
        .auto_generated = true,
    });

    // BelongsTo: Junction entry belongs to a Post
    t.belongsTo(.{
        .name = "junction_post",
        .column = "post_id",
        .references_table = "posts",
        .on_delete = .cascade,
    });

    // BelongsTo: Junction entry belongs to a Category
    t.belongsTo(.{
        .name = "junction_category",
        .column = "category_id",
        .references_table = "categories",
        .on_delete = .cascade,
    });

    // Composite unique index to prevent duplicate post-category pairs
    t.addIndexes(&.{
        .{
            .name = "idx_post_categories_unique",
            .columns = &.{ "post_id", "category_id" },
            .unique = true,
        },
    });
}
