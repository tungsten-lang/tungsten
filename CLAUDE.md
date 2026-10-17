@AGENTS.md

# Claude Code specifics

- Deciding when to enter plan mode is the user's call, not yours.
- Use subagents liberally: offload research, exploration, and parallel analysis
  to keep the main context clean. Give each subagent one focused task, and fan
  out on hard problems.
- After the user corrects you, save the pattern as a `feedback` memory with a
  rule that prevents a repeat.

## Skill routing

When a request clearly matches an available skill, invoke it with the Skill
tool instead of answering ad hoc. Answer direct questions and quick lookups
yourself.

- Product ideas, "is this worth building", brainstorming → `/office-hours`
- Bugs, errors, "why is this broken", 500 errors → `/investigate`
- Ship, deploy, push, create PR → `/ship`
- QA, test the site, find bugs → `/qa`
- Code review, check my diff → `/review`
- Update docs after shipping → `/document-release`
- Weekly retro → `/retro`
- Design system, brand → `/design-consultation`
- Visual audit, design polish → `/design-review`
- Architecture review → `/plan-eng-review`
