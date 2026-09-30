# Scheme calculus on MFW1 files: the constructions of the derivation and composition pipeline as commands.
# Library: lib/metaflip/gf2/derive.w (ports of verify_composition_targets.py, verify_cofactor_mergers.py and
# screen_structured_parent_projections.py). The result is printed as canonical MFW1 on standard output.
#
#   scheme_ops project  IN.mfw DIMENSION COORDINATE        delete one coordinate (dimension 0, 1 or 2)
#   scheme_ops compress IN.mfw                             shared-factor compression until nothing changes
#   scheme_ops rewrite  IN.mfw AXIS [reverse]              refactor every group of terms that share a factor on AXIS
#   scheme_ops child    IN.mfw DIMENSION COORDINATE        project, then compress at the width of the smaller shape
#   scheme_ops basis    IN.mfw MODE                        the two-pass basis rewrite of modes 6..17, then compress
#   scheme_ops kron     A.mfw B.mfw                        the product scheme
#   scheme_ops block    IN.mfw N M P O1 O2 O3              place the scheme at offsets O1 O2 O3 inside an N x M x P shape
#
# Run as `bin/tungsten run tools/scheme_ops.w -- ARGS` or compile with `-o`. Errors go to standard error with status 1.
use ../lib/metaflip/gf2/derive

-> fail(message)
  ccall("w_eputs", "scheme_ops: " + message)
  exit(1)

-> usage()
  ccall("w_eputs", "usage: scheme_ops project IN DIMENSION COORDINATE | child IN DIMENSION COORDINATE | compress IN | rewrite IN AXIS \[reverse\] | basis IN MODE | kron A B | block IN N M P O1 O2 O3")
  exit(2)

-> load(path)
  scheme = nil
  begin
    scheme = Metaflip:Gf2:Scheme.read(path)
  rescue failure
    fail(failure.to_s)
  scheme

-> widest(shape)
  Metaflip:Gf2:Derive.width(shape)

-> emit(shape, terms)
  result = Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms)
  <- result.blob

args = argv()
usage() if args.size < 2
command = args[0]
scheme = load(args[1])
shape = [scheme.n, scheme.m, scheme.p]
terms = scheme.terms
begin
  if command == "project" && args.size == 4
    projected = Metaflip:Gf2:Derive.project(shape, terms, args[2].to_i, args[3].to_i)
    emit(projected[0], projected[1])
  elsif command == "compress" && args.size == 2
    emit(shape, Metaflip:Gf2:Derive.compress_shared(terms, widest(shape))[0])
  elsif command == "rewrite" && (args.size == 3 || args.size == 4)
    emit(shape, Metaflip:Gf2:Derive.refactor_shared(terms, args[2].to_i, widest(shape), args.size == 4 && args[3] == "reverse")[0])
  elsif command == "child" && args.size == 4
    child = Metaflip:Gf2:Derive.child(shape, terms, args[2].to_i, args[3].to_i)
    emit(child[0], child[1])
  elsif command == "basis" && args.size == 3
    emit(shape, Metaflip:Gf2:Derive.two_pass(terms, shape, args[2].to_i))
  elsif command == "kron" && args.size == 3
    other = load(args[2])
    other_shape = [other.n, other.m, other.p]
    product = [shape[0] * other_shape[0], shape[1] * other_shape[1], shape[2] * other_shape[2]]
    emit(product, Metaflip:Gf2:Derive.kronecker(shape, terms, other_shape, other.terms))
  elsif command == "block" && args.size == 8
    target = [args[2].to_i, args[3].to_i, args[4].to_i]
    emit(target, Metaflip:Gf2:Derive.block(shape, terms, target, [args[5].to_i, args[6].to_i, args[7].to_i]))
  else
    usage()
rescue failure
  fail(failure.to_s)
