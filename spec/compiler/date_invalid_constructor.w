# spec: compiled-rejects -- Date.new expects one to seven arguments
# spec: interpreter-rejects -- Date.new expects one to seven arguments
# Date is a packed scalar whose constructor requires at least a year. A
# zero-argument call must not allocate an ordinary object.
<< Date.new()
