/* wasm32-wasi compat: no native unwinder — backtraces are empty. */
#ifndef TUNGSTEN_WASI_EXECINFO_H
#define TUNGSTEN_WASI_EXECINFO_H
int backtrace(void **buffer, int size);
char **backtrace_symbols(void *const *buffer, int size);
void backtrace_symbols_fd(void *const *buffer, int size, int fd);
#endif
