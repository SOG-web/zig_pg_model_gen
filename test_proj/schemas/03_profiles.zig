// Profile table schema definition
// One-to-one relationship with users - each user has exactly one profile

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

    // Foreign key to users table - unique for one-to-one
    t.uuid(.{
        .name = "user_id",
        .unique = true, // Ensures one-to-one relationship
    });

    // Profile bio - optional
    t.string(.{
        .name = "bio",
        .not_null = false,
        .create_input = .optional,
    });

    // Avatar URL - optional
    t.string(.{
        .name = "avatar_url",
        .not_null = false,
        .create_input = .optional,
    });

    // Website - optional
    t.string(.{
        .name = "website",
        .not_null = false,
        .create_input = .optional,
    });

    // Location - optional
    t.string(.{
        .name = "location",
        .not_null = false,
        .create_input = .optional,
    });

    // Date of birth - optional
    t.dateTime(.{
        .name = "date_of_birth",
        .not_null = false,
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

    // One-to-one: Profile belongs to User - using hasOne convenience method!
    // The unique constraint on user_id enforces the one-to-one relationship
    t.hasOne(.{
        .name = "profile_user",
        .column = "user_id",
        .references_table = "users",
        .on_delete = .cascade,
    });
}
