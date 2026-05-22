-- Approach A: Pure Lua DSL
-- The agent + its tools are defined entirely in Lua tables.
-- This is what the earlier (now-rejected) PLAN.md Section 8 proposed.

local search_papers = {
  description = [[
    Search arxiv for academic papers matching a query.
    Use precise terms; arxiv search is not fuzzy.
  ]],
  args = {
    query = { type = "string", required = true },
    limit = { type = "number", default = 10 },
  },
  handler = function(ctx, args)
    return http.get("https://export.arxiv.org/api/query", {
      search_query = args.query,
      max_results = args.limit or 10,
    })
  end,
}

local save_finding = {
  description = "Save a research finding to the workbook database.",
  args = {
    topic = { type = "string", required = true },
    content = { type = "string", required = true },
    source = { type = "string", required = true },
  },
  handler = function(ctx, args)
    return db.write("findings", args)
  end,
}

return agent.define {
  name = "researcher",
  model = "claude-opus-4-7",

  system = [[
    You are a research assistant. Given a topic, search arxiv for
    relevant academic papers and save findings to the workbook.
  ]],

  tools = { search_papers, save_finding },
}
