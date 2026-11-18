# spec: compiled -- packed WIRE inspection uses native intrinsics
use ../../compiler/lib/emitter

-> dispatch_fixture(first, middle, last)
  calls = []
  slots = [first, middle, last]
  i = 0
  while i < slots.size
    calls.push(wire_instruction({
      op: :call_method_i64, temp: "%r" + i.to_s, temp_args_val: "%args" + i.to_s,
      receiver: "%.value", method_name_val: "0", args: [], ic_id: slots[i]
    }))
    i += 1
  calls.push(wire_instruction({op: :ret_i64, value: "%r2"}))
  {name: "cached_dispatch_fixture", params: ["value"], return_type: "i64",
   source_path: "fixture.w", blocks: [{label: "entry", instructions: calls}]}

-> render_dispatch_fixture(bucket, f)
  emit_function_with_cache(f, nil, {}, {}, false, "", nil, true, false, false, bucket, false)

bucket = {scope: :library, library_paths: {"fixture.w": true}, functions: {}}
original = render_dispatch_fixture(bucket, dispatch_fixture(1, 2, 4))
shifted = render_dispatch_fixture(bucket, dispatch_fixture(1, 3, 4))
raise "stale dispatch slot reused" unless original.include?("ptr @.ic, i64 2\n") && shifted.include?("ptr @.ic, i64 3\n")
raise "old slot remained in the rendered body" if shifted.include?("ptr @.ic, i64 2\n")
hits = function_emit_cache_state[:hits]
again = render_dispatch_fixture(bucket, dispatch_fixture(1, 3, 4))
raise "unchanged layout missed the cache" unless again == shifted && function_emit_cache_state[:hits] == hits + 1
<< "PASS cached LLVM follows the current dispatch layout"
