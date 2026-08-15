# LLVM memory-effect contracts for SSO String helpers. The SSO-5 leaf is
# scalar-only; public helpers remain conservative because rope fallback can
# allocate and write the rope's cached flattened value.

use ../../compiler/lib/emitter

-> check(name, condition)
  if !condition
    << "FAIL string SSO attrs: " + name
    exit(1)
  << "PASS string SSO attrs " + name

decls = declare_runtime()
lines = decls.split("\n")

-> declaration_for(lines, name)
  needle = "@" + name + "("
  i = 0
  while i < lines.size()
    if lines[i].include?(needle)
      return lines[i]
    i += 1
  nil

idx_decl = declaration_for(lines, "w_string_idx_raw")
size_decl = declaration_for(lines, "w_string_byte_length")
first_decl = declaration_for(lines, "w_string_first_byte")
slice_decl = declaration_for(lines, "w_string_slice_raw")

check("generic index declared", idx_decl != nil)
check("generic index is conservative", idx_decl == "declare i64 @w_string_idx_raw(i64, i64) nounwind")
check("generic size is read-only", size_decl == "declare i64 @w_string_byte_length(i64) nounwind willreturn memory(read)")
check("generic first-byte is conservative", first_decl == "declare i64 @w_string_first_byte(i64) nounwind")
check("generic slice is conservative", slice_decl == "declare i64 @w_string_slice_raw(i64, i64, i64) nounwind")

ir = string_idx_fast_helper_ir()
leaf_end = ir.index("define private i64 @__w_string_idx_fast")
leaf = ir.slice(0, leaf_end)
wrapper = ir.slice(leaf_end, ir.size() - leaf_end)

check("SSO leaf is memory-none", leaf.include?("alwaysinline nounwind willreturn memory(none) speculatable"))
check("SSO leaf has no load", !leaf.include?(" load "))
check("SSO leaf has no store", !leaf.include?("store "))
check("SSO leaf has no call", !leaf.include?("call "))
check("wrapper guards string tag", wrapper.include?("%is.stringy = icmp eq i64 %tag, 65529"))
check("wrapper guards inline mode", wrapper.include?("%is.inline = icmp ule i64 %mode, 5"))
check("wrapper retains runtime fallback", wrapper.include?("call i64 @w_string_idx_raw(i64 %str, i64 %idx)"))
check("wrapper is not falsely memory-none", !wrapper.split("\n")[0].include?("memory("))

size_ir = string_size_fast_helper_ir()
size_leaf_end = size_ir.index("define private i64 @__w_string_byte_length_fast")
size_leaf = size_ir.slice(0, size_leaf_end)
size_wrapper = size_ir.slice(size_leaf_end, size_ir.size() - size_leaf_end)
check("SSO size leaf is memory-none", size_leaf.include?("alwaysinline nounwind willreturn memory(none) speculatable"))
check("SSO size leaf has no load", !size_leaf.include?(" load "))
check("size wrapper is read-only", size_wrapper.split("\n")[0].include?("willreturn memory(read)"))
check("size wrapper retains read-only fallback", size_wrapper.include?("call i64 @w_string_byte_length(i64 %str)"))
