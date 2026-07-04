.PHONY: lowering-graph specs

# Print the dependency graph of lowering.w's worker modules.
# Reads `use lowering/<name>` lines from compiler/lib/lowering.w in
# import order — the order shown is the dep chain, since each module
# only imports earlier ones (see compiler/lib/lowering/pass_registry.w
# for the rationale).
lowering-graph:
	@grep "^use lowering/" compiler/lib/lowering.w | awk '{print $$2}'

# Run the default self-checking `.w` specs. Build the compiler first
# (`bin/tungsten build`). Set RUN_CORE_SPECS=1, RUN_METAL_SPECS=1, or
# RUN_REPL_SPECS=1 for broader runtime/hardware/system specs.
specs:
	@scripts/test-specs.sh
