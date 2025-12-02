// Category table schema definition
// Categories for posts - used in many-to-many relationship

const fluentorm = @import("fluentorm");
const TableSchema = fluentorm.TableSchema;

/// Table name for schema merging - multiple schemas with same table_name will be merged
pub const table_name = "categories";

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

    // Category name - required, unique
    t.string(.{
        .name = "name",
        .unique = true,
    });

    // Category slug for URLs - required, unique
    t.string(.{
        .name = "slug",
        .unique = true,
    });

    // Category description - optional
    t.string(.{
        .name = "description",
        .not_null = false,
        .create_input = .optional,
    });

    // Category color for UI - optional
    t.string(.{
        .name = "color",
        .not_null = false,
        .create_input = .optional,
        .default_value = "'#3B82F6'",
    });

    // Sort order for display
    t.integer(.{
        .name = "sort_order",
        .default_value = "0",
        .create_input = .optional,
    });

    // Is active flag
    t.boolean(.{
        .name = "is_active",
        .default_value = "true",
        .create_input = .optional,
    });

    // Timestamps
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

    // Many-to-many: Category has many posts through post_categories
    t.hasMany(.{
        .name = "category_posts",
        .foreign_table = "post_categories",
        .foreign_column = "category_id",
    });

    // Add index on slug for fast lookups
    t.addIndexes(&.{
        .{
            .name = "idx_categories_slug",
            .columns = &.{"slug"},
            .unique = true,
        },
    });
}
