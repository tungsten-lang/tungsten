# Assignment emits STORE_LOCAL + POP, which leaves the operand stack empty.
# The following expression must repopulate it without the dispatch loop reading
# stack[sp - 1] while sp is zero.
answer = 40 + 2
<< answer * 2
