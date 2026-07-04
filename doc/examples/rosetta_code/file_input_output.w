contents = File.read 'input.txt'

File.write 'output.txt', contents

# OR

File.copy 'input.txt', 'output.txt'

## expect skip filesystem side effects
