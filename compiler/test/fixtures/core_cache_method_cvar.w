# Base64's alphabet lives in class variables that only its method bodies
# touch (no class-body initializer), so a lowered-Core cache hit must still
# define their globals.
<< Base64.__alpha_table(false).size
