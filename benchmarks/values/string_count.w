t0 = clock

base = "the quick brown fox jumps over the lazy dog "
text = base.repeat(2500000)

count = text.count("fox")

t1 = clock
<< count
<< "elapsed: [t1 - t0]s"
