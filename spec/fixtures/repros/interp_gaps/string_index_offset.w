# String#index / #rindex must honor their optional second argument (search
# start offset / match-start cap) in BOTH engines. The interpreter's builtin
# dropped it and always searched from 0 (blocking forge Request#parse's
# single-pass rewrite); compiled always honored it via w_ic_string_index /
# w_ic_string_rindex.
s = "hello world hello"
a = s.index("hello")
b = s.index("hello", 1)
c = s.index("o", 5)
d = s.rindex("hello")
e = s.rindex("hello", 11)
f = s.rindex("o", 6)
<< "index base=[a] off1=[b] o5=[c]"
<< "rindex base=[d] cap11=[e] o6=[f]"
g = s.index("hello", 13)
gn = g == nil
<< "past-end-nil=[gn]"
