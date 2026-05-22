-- Approach A: Lua orchestrator coordinating sub-agents.
-- An orchestrator agent uses `agent.invoke` to call the others in order.
-- Dependencies are encoded as call order; failure handling is manual.

local function run_research_pipeline(ctx, args)
  -- Stage 1: researcher
  local research = agent.invoke("researcher", {
    topic = args.topic,
  })
  if research.status ~= "ok" then
    return { status = "failed", at = "research", error = research.error }
  end

  -- Stage 2: critic (depends on stage 1)
  local critique = agent.invoke("critic", {
    findings = research.findings,
  })
  if critique.status ~= "ok" then
    return { status = "failed", at = "critique", error = critique.error }
  end

  -- Stage 3: summarizer (depends on stage 2)
  local summary = agent.invoke("summarizer", {
    findings = research.findings,
    evaluations = critique.evaluations,
  })
  if summary.status ~= "ok" then
    return { status = "failed", at = "summary", error = summary.error }
  end

  return {
    status = "ok",
    research = research,
    critique = critique,
    summary = summary,
  }
end

return agent.define {
  name = "research-pipeline",
  model = "claude-opus-4-7",
  system = "Coordinate a research pipeline: find, evaluate, summarize.",
  tools = {
    {
      description = "Run the full research pipeline.",
      args = { topic = { type = "string", required = true } },
      handler = run_research_pipeline,
    },
  },
}
