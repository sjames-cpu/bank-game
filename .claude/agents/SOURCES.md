# Agent sources

`godot-specialist.md`, `godot-gdscript-specialist.md`, and `godot-shader-specialist.md`
are copied, unmodified, from [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)
by Donchitos, MIT licensed. Only these three Godot-specific agents were taken from
that project — its broader studio-hierarchy framework (other 46 agents, workflow
skills, hooks, path-scoped rules, `src/`-based project scaffold) was not adopted,
since it assumes a project layout that doesn't match this repo's `scenes/`/`scripts/`
structure.

Two things carried over from the source project that don't apply here, since we
didn't adopt the rest of its framework:
- Each agent's "Version Awareness" section tells it to read files under
  `docs/engine-reference/godot/` before suggesting engine APIs — this repo has no
  such docs, so that step will just come up empty. Its explicit fallback (WebSearch,
  or falling back to training data) still applies.
- Their "Delegation Map" / "Coordinates with" sections reference other agents
  (`technical-director`, `lead-programmer`, `gameplay-programmer`, etc.) that
  aren't installed here, so those delegation paths are inert.
