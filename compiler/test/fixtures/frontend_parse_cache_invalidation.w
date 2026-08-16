use ../../lib/loader

target = argv()[0]
loader_enable_parse_cache()

first_loader = Loader.new()
first = first_loader.load_program_ast(target)
first_size = first.expressions.size()
source = read_file(target)

# Same bytes with a new stat tuple should take the fingerprint reuse path.
write_file(target, source)
second_loader = Loader.new()
second = second_loader.load_program_ast(target)
second_summary = second_loader.parse_cache_verbose_text()

# A real content/size change must parse a new local AST.
write_file(target, source + "\nfrontend_cache_added = 2\n")
third_loader = Loader.new()
third = third_loader.load_program_ast(target)

<< second.expressions.size() == first_size
<< second_summary != nil && second_summary.index("fingerprint") != nil
<< third.expressions.size() == first_size + 1
