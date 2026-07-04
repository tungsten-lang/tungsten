# @todo float prefix or suffix?
ex "~1.0", ~1.0
ex "~0.0", ~0.0
ex "~1.0 * +0", ~+0.0"
ex "~1.0 * -0", ~-0.0"
ex "~1.0 * -1", ~-1.0"

ex " 1.0f",  1.0f
ex "-1.0f", -1.0f
