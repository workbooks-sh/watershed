-- Approach A: Pure Lua schema declaration.
-- Each table is a Lua table describing its fields, tenancy, and indexes.

return {
  findings = {
    fields = {
      id = "uuid",
      topic = "string",
      content = "text",
      source = "string",
      score = "number?",
      created_at = "timestamp",
      created_by = "user_id",
    },
    tenant = "workspace",
    indexes = { "topic", "created_at" },
  },

  evaluations = {
    fields = {
      id = "uuid",
      finding_id = "uuid",
      score = "number",
      rationale = "text",
      reviewer = "user_id",
    },
    tenant = "workspace",
    indexes = { "finding_id" },
    relations = {
      finding = { belongs_to = "findings", via = "finding_id" },
    },
  },

  reports = {
    fields = {
      id = "uuid",
      title = "string",
      summary = "text",
      finding_ids = "uuid[]",
    },
    tenant = "workspace",
  },
}
