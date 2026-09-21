// wasi_shim.js — a dependency-free `wasi_snapshot_preview1` host for tungsten.wasm.
//
// Runs unchanged in Cloudflare Workers, browsers, Node and Bun. It implements
// just what a one-shot interpreter run needs:
//
//   * an in-memory READ-ONLY filesystem behind one preopen ("/", fd 3)
//   * stdin from a Uint8Array, captured stdout / stderr with a byte cap
//   * args / environ, clock_time_get, random_get, poll_oneoff (virtual sleep)
//   * proc_exit (a thrown sentinel), and ENOSYS / EROFS for everything else
//
//   import { run, loadBundle } from "./wasi_shim.js";
//   const fs = loadBundle(tungstenFsArrayBuffer);          // once per isolate
//   const { stdout, stderr, exitCode } = run(module, {     // once per request
//     args: ["tungsten", "/work/main.w"],
//     files: [new Map([["/work/main.w", sourceBytes]]), fs],
//     maxOutputBytes: 64 * 1024,
//   });
//
// `module` is an already-compiled WebAssembly.Module (Workers forbid compiling
// from bytes at run time). Every run gets a fresh Instance and fresh memory.

const ERRNO = {
  SUCCESS: 0, ACCES: 2, BADF: 8, EXIST: 20, FAULT: 21, INVAL: 28, IO: 29, ISDIR: 31,
  NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTSUP: 58, PERM: 63, ROFS: 69, SPIPE: 70,
};
const FILETYPE = { UNKNOWN: 0, CHARACTER_DEVICE: 2, DIRECTORY: 3, REGULAR_FILE: 4 };
const OFLAGS = { CREAT: 1, DIRECTORY: 2, EXCL: 4, TRUNC: 8 };
const RIGHTS_FD_WRITE = 1n << 6n;
// Every right except the mutating ones: what a read-only tree can grant.
const RIGHTS_READ_ONLY = 0x1fffffffn & ~((1n << 6n) | (1n << 8n) | (1n << 9n) | (1n << 10n) |
  (1n << 11n) | (1n << 12n) | (1n << 16n) | (1n << 17n) | (1n << 20n) | (1n << 22n) |
  (1n << 23n) | (1n << 24n) | (1n << 25n) | (1n << 26n));
const WHENCE = { SET: 0, CUR: 1, END: 2 };
const PREOPEN_FD = 3;
const PREOPEN_NAME = "/";

const utf8Encoder = new TextEncoder();
const utf8Decoder = new TextDecoder("utf-8", { fatal: false });

/** Thrown by proc_exit; carries the guest's exit status. */
export class WasiExit extends Error {
  constructor(code) {
    super(`wasi exit ${code}`);
    this.code = code;
  }
}

/** Thrown when a run exceeds `maxOutputBytes` or `timeoutMs`. */
export class WasiAbort extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

// ---------------------------------------------------------------------------
// Filesystem sources
//
// A source answers three questions about canonical absolute paths ("/core/x.w"):
//   get(path)  -> Uint8Array | undefined
//   isDir(path)-> boolean
//   list(path) -> string[] (entry names) | undefined
// Map<string, Uint8Array|string>, plain lookup functions and bundles all adapt.
// ---------------------------------------------------------------------------

function toBytes(value) {
  if (value == null) return undefined;
  if (typeof value === "string") return utf8Encoder.encode(value);
  if (value instanceof Uint8Array) return value;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  throw new TypeError("file contents must be a string, ArrayBuffer or typed array");
}

/** Directory index over a known set of file paths (built lazily, once). */
class PathTree {
  constructor(paths) {
    this.paths = paths;
    this.dirs = null;
  }
  build() {
    if (this.dirs) return this.dirs;
    const dirs = new Map([["/", new Set()]]);
    for (const path of this.paths()) {
      let end = path.lastIndexOf("/");
      let child = path.slice(end + 1);
      for (;;) {
        const dir = end <= 0 ? "/" : path.slice(0, end);
        let entries = dirs.get(dir);
        const seen = entries !== undefined;
        if (!seen) dirs.set(dir, (entries = new Set()));
        entries.add(child);
        if (dir === "/" || seen) break;
        end = dir.lastIndexOf("/");
        child = dir.slice(end + 1);
      }
    }
    return (this.dirs = dirs);
  }
  isDir(path) { return this.build().has(path); }
  list(path) {
    const entries = this.build().get(path);
    return entries ? [...entries] : undefined;
  }
}

function mapSource(map) {
  const tree = new PathTree(() => map.keys());
  return {
    get: (path) => toBytes(map.get(path)),
    isDir: (path) => tree.isDir(path),
    list: (path) => tree.list(path),
  };
}

function functionSource(lookup) {
  return { get: (path) => toBytes(lookup(path)), isDir: () => false, list: () => undefined };
}

function adaptSource(source) {
  if (source instanceof Map) return mapSource(source);
  if (typeof source === "function") return functionSource(source);
  if (source && typeof source.get === "function") {
    return {
      get: (path) => toBytes(source.get(path)),
      isDir: source.isDir ? (path) => source.isDir(path) : () => false,
      list: source.list ? (path) => source.list(path) : () => undefined,
    };
  }
  throw new TypeError("files: expected a Map, a lookup function, a bundle, or an array of those");
}

/** Layer several sources; earlier ones win. */
function layerSources(files) {
  if (files == null) return [];
  return (Array.isArray(files) ? files : [files]).map(adaptSource);
}

/**
 * Open a tungsten.fs bundle (see pack_fs.py). Parses only the small index;
 * file contents are served as zero-copy subarrays of `buffer`.
 *
 *   "TFS1" | u32 file_count | u32 index_bytes | index | data
 *   index entry: u32 data_offset, u32 length, u16 path_len, path (utf-8)
 */
export function loadBundle(buffer) {
  const bytes = toBytes(buffer);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 12 || utf8Decoder.decode(bytes.subarray(0, 4)) !== "TFS1") {
    throw new Error("not a tungsten.fs bundle (bad magic)");
  }
  const count = view.getUint32(4, true);
  const dataStart = 12 + view.getUint32(8, true);
  const index = new Map();
  let cursor = 12;
  for (let i = 0; i < count; i++) {
    const offset = view.getUint32(cursor, true);
    const length = view.getUint32(cursor + 4, true);
    const pathLength = view.getUint16(cursor + 8, true);
    const path = utf8Decoder.decode(bytes.subarray(cursor + 10, cursor + 10 + pathLength));
    index.set(path, [dataStart + offset, length]);
    cursor += 10 + pathLength;
  }
  const tree = new PathTree(() => index.keys());
  return {
    size: count,
    paths: () => [...index.keys()],
    get(path) {
      const entry = index.get(path);
      return entry ? bytes.subarray(entry[0], entry[0] + entry[1]) : undefined;
    },
    isDir: (path) => tree.isDir(path),
    list: (path) => tree.list(path),
  };
}

/** Collapse ".", ".." and duplicate slashes; the result is absolute. */
function normalizePath(base, relative) {
  const parts = [];
  for (const part of `${base}/${relative}`.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return "/" + parts.join("/");
}

// ---------------------------------------------------------------------------
// run
// ---------------------------------------------------------------------------

/**
 * @param {WebAssembly.Module} module  compiled tungsten.wasm
 * @param {object}   [options]
 * @param {string[]} [options.args]            argv, including argv[0]
 * @param {object}   [options.env]             environment variables
 * @param {Uint8Array|string} [options.stdin]  also readable as /dev/stdin
 * @param {Map|Function|object|Array} [options.files]  filesystem source(s)
 * @param {number}   [options.maxOutputBytes]  stdout+stderr cap (default 1 MiB)
 * @param {number}   [options.timeoutMs]       wall-clock budget, checked on every
 *                                             WASI call (a pure compute loop makes
 *                                             none; the host's CPU limit covers it)
 * @param {(path:string)=>void} [options.onOpen]  called with every path_open path
 * @param {boolean}  [options.debug]           append the JS/wasm stack to stderr on a trap
 * @returns {{stdout:string, stderr:string, exitCode:number, truncated:boolean,
 *            stdoutBytes:Uint8Array, stderrBytes:Uint8Array}}
 */
export function run(module, options = {}) {
  const args = options.args ?? ["tungsten"];
  const env = options.env ?? {};
  const stdin = toBytes(options.stdin) ?? new Uint8Array(0);
  const maxOutputBytes = options.maxOutputBytes ?? 1 << 20;
  const timeoutMs = options.timeoutMs ?? 0;
  const onOpen = options.onOpen;
  const sources = layerSources(options.files);

  const now = typeof performance !== "undefined" ? () => performance.now() : () => Date.now();
  const startedAt = now();
  let virtualSleepNs = 0n;      // poll_oneoff "sleeps" by advancing this, not by waiting
  let outputBytes = 0;
  let truncated = false;
  const captured = { 1: [], 2: [] };

  const lookupFile = (path) => {
    if (path === "/dev/stdin") return stdin;
    for (const source of sources) {
      const data = source.get(path);
      if (data !== undefined) return data;
    }
    return undefined;
  };
  const isDirectory = (path) => path === "/" || path === "/dev" || sources.some((s) => s.isDir(path));
  const listDirectory = (path) => {
    const names = new Set();
    for (const source of sources) for (const name of source.list(path) ?? []) names.add(name);
    if (path === "/") names.add("dev");
    if (path === "/dev") names.add("stdin");
    return [...names].sort();
  };

  // fd table: 0-2 stdio, 3 the preopen, 4+ opened files / directories.
  const fds = new Map([
    [0, { kind: "stdin", position: 0 }],
    [1, { kind: "out" }],
    [2, { kind: "out" }],
    [PREOPEN_FD, { kind: "dir", path: "/" }],
  ]);
  let nextFd = PREOPEN_FD + 1;

  let memory;
  let cachedView = null;
  const view = () => (cachedView && cachedView.buffer === memory.buffer ? cachedView : (cachedView = new DataView(memory.buffer)));
  const bytesAt = (ptr, len) => new Uint8Array(memory.buffer, ptr, len);
  const readString = (ptr, len) => utf8Decoder.decode(bytesAt(ptr, len));

  const checkBudget = () => {
    if (timeoutMs > 0 && now() - startedAt > timeoutMs) throw new WasiAbort(`time limit of ${timeoutMs} ms exceeded`);
  };

  const writeStringList = (list, arrayPtr, bufferPtr) => {
    const v = view();
    for (const item of list) {
      v.setUint32(arrayPtr, bufferPtr, true);
      arrayPtr += 4;
      const encoded = utf8Encoder.encode(item);
      bytesAt(bufferPtr, encoded.length).set(encoded);
      v.setUint8(bufferPtr + encoded.length, 0);
      bufferPtr += encoded.length + 1;
    }
    return ERRNO.SUCCESS;
  };
  const stringListSizes = (list, countPtr, sizePtr) => {
    const v = view();
    v.setUint32(countPtr, list.length, true);
    v.setUint32(sizePtr, list.reduce((n, item) => n + utf8Encoder.encode(item).length + 1, 0), true);
    return ERRNO.SUCCESS;
  };
  const envList = Object.entries(env).map(([key, value]) => `${key}=${value}`);

  const writeFilestat = (ptr, filetype, size) => {
    const v = view();
    bytesAt(ptr, 64).fill(0);
    v.setUint8(ptr + 16, filetype);
    v.setBigUint64(ptr + 24, 1n, true);           // nlink
    v.setBigUint64(ptr + 32, BigInt(size), true); // size
  };
  const filestatFor = (entry, ptr) => {
    if (entry.kind === "file") writeFilestat(ptr, FILETYPE.REGULAR_FILE, entry.data.length);
    else if (entry.kind === "dir") writeFilestat(ptr, FILETYPE.DIRECTORY, 0);
    else writeFilestat(ptr, FILETYPE.CHARACTER_DEVICE, 0);
    return ERRNO.SUCCESS;
  };

  /** Scatter `source[position..]` into the guest's iovec array. */
  const readInto = (iovsPtr, iovsLen, source, position) => {
    const v = view();
    let total = 0;
    for (let i = 0; i < iovsLen; i++) {
      const ptr = v.getUint32(iovsPtr + i * 8, true);
      const len = v.getUint32(iovsPtr + i * 8 + 4, true);
      const chunk = source.subarray(position + total, position + total + len);
      bytesAt(ptr, chunk.length).set(chunk);
      total += chunk.length;
      if (chunk.length < len) break;
    }
    return total;
  };

  const nowNs = () => BigInt(Math.round(now() * 1e6));
  const wasi = {
    args_get: (argvPtr, bufferPtr) => writeStringList(args, argvPtr, bufferPtr),
    args_sizes_get: (countPtr, sizePtr) => stringListSizes(args, countPtr, sizePtr),
    environ_get: (environPtr, bufferPtr) => writeStringList(envList, environPtr, bufferPtr),
    environ_sizes_get: (countPtr, sizePtr) => stringListSizes(envList, countPtr, sizePtr),

    clock_res_get(_id, resultPtr) {
      view().setBigUint64(resultPtr, 1000n, true);
      return ERRNO.SUCCESS;
    },
    clock_time_get(id, _precision, resultPtr) {
      checkBudget();
      // 0 realtime; 1 monotonic; 2/3 cpu time (approximated by elapsed time).
      const base = id === 0 ? BigInt(Date.now()) * 1000000n : id === 1 ? nowNs() : nowNs() - BigInt(Math.round(startedAt * 1e6));
      view().setBigUint64(resultPtr, base + virtualSleepNs, true);
      return ERRNO.SUCCESS;
    },
    random_get(ptr, len) {
      for (let done = 0; done < len; done += 65536) {
        crypto.getRandomValues(bytesAt(ptr + done, Math.min(65536, len - done)));
      }
      return ERRNO.SUCCESS;
    },
    sched_yield: () => ERRNO.SUCCESS,
    proc_exit(code) { throw new WasiExit(code); },
    proc_raise: () => ERRNO.NOSYS,

    // Sleeping never blocks the host: the requested interval is added to the
    // guest-visible clocks and the earliest clock subscription fires at once.
    poll_oneoff(subsPtr, eventsPtr, count, resultPtr) {
      checkBudget();
      const v = view();
      let earliest = null;
      for (let i = 0; i < count; i++) {
        const sub = subsPtr + i * 48;
        if (v.getUint8(sub + 8) !== 0) continue;   // only clock subscriptions
        let timeout = v.getBigUint64(sub + 24, true);
        if (v.getUint16(sub + 40, true) & 1) {     // absolute deadline
          const clockNow = (v.getUint32(sub + 16, true) === 0 ? BigInt(Date.now()) * 1000000n : nowNs()) + virtualSleepNs;
          timeout = timeout > clockNow ? timeout - clockNow : 0n;
        }
        if (earliest === null || timeout < earliest.timeout) earliest = { timeout, userdata: v.getBigUint64(sub, true) };
      }
      if (earliest === null) return ERRNO.NOTSUP;
      virtualSleepNs += earliest.timeout;
      bytesAt(eventsPtr, 32).fill(0);
      v.setBigUint64(eventsPtr, earliest.userdata, true);
      v.setUint32(resultPtr, 1, true);
      return ERRNO.SUCCESS;
    },

    fd_prestat_get(fd, resultPtr) {
      if (fd !== PREOPEN_FD) return ERRNO.BADF;
      const v = view();
      v.setUint8(resultPtr, 0);
      v.setUint32(resultPtr + 4, utf8Encoder.encode(PREOPEN_NAME).length, true);
      return ERRNO.SUCCESS;
    },
    fd_prestat_dir_name(fd, pathPtr, pathLen) {
      if (fd !== PREOPEN_FD) return ERRNO.BADF;
      bytesAt(pathPtr, pathLen).set(utf8Encoder.encode(PREOPEN_NAME).subarray(0, pathLen));
      return ERRNO.SUCCESS;
    },
    fd_fdstat_get(fd, resultPtr) {
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      const v = view();
      bytesAt(resultPtr, 24).fill(0);
      const filetype = entry.kind === "file" ? FILETYPE.REGULAR_FILE : entry.kind === "dir" ? FILETYPE.DIRECTORY : FILETYPE.CHARACTER_DEVICE;
      v.setUint8(resultPtr, filetype);
      const rights = entry.kind === "out" ? RIGHTS_FD_WRITE | (1n << 21n) : RIGHTS_READ_ONLY;
      v.setBigUint64(resultPtr + 8, rights, true);
      v.setBigUint64(resultPtr + 16, entry.kind === "dir" ? RIGHTS_READ_ONLY : 0n, true);
      return ERRNO.SUCCESS;
    },
    fd_fdstat_set_flags: (fd) => (fds.has(fd) ? ERRNO.SUCCESS : ERRNO.BADF),
    fd_filestat_get(fd, resultPtr) {
      const entry = fds.get(fd);
      return entry ? filestatFor(entry, resultPtr) : ERRNO.BADF;
    },
    fd_close(fd) {
      if (!fds.has(fd)) return ERRNO.BADF;
      if (fd > PREOPEN_FD) fds.delete(fd);
      return ERRNO.SUCCESS;
    },
    fd_sync: (fd) => (fds.has(fd) ? ERRNO.SUCCESS : ERRNO.BADF),
    fd_datasync: (fd) => (fds.has(fd) ? ERRNO.SUCCESS : ERRNO.BADF),
    fd_advise: (fd) => (fds.has(fd) ? ERRNO.SUCCESS : ERRNO.BADF),
    fd_tell(fd, resultPtr) {
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind !== "file") return ERRNO.SPIPE;
      view().setBigUint64(resultPtr, BigInt(entry.position), true);
      return ERRNO.SUCCESS;
    },
    fd_seek(fd, offset, whence, resultPtr) {
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind !== "file") return ERRNO.SPIPE;
      const base = whence === WHENCE.SET ? 0 : whence === WHENCE.CUR ? entry.position : whence === WHENCE.END ? entry.data.length : -1;
      if (base < 0) return ERRNO.INVAL;
      const target = base + Number(offset);
      if (target < 0) return ERRNO.INVAL;
      entry.position = target;
      view().setBigUint64(resultPtr, BigInt(target), true);
      return ERRNO.SUCCESS;
    },
    fd_read(fd, iovsPtr, iovsLen, resultPtr) {
      checkBudget();
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind === "dir") return ERRNO.ISDIR;
      if (entry.kind === "out") return ERRNO.BADF;
      const source = entry.kind === "stdin" ? stdin : entry.data;
      const total = readInto(iovsPtr, iovsLen, source, entry.position);
      entry.position += total;
      view().setUint32(resultPtr, total, true);
      return ERRNO.SUCCESS;
    },
    fd_pread(fd, iovsPtr, iovsLen, offset, resultPtr) {
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind !== "file") return ERRNO.SPIPE;
      view().setUint32(resultPtr, readInto(iovsPtr, iovsLen, entry.data, Number(offset)), true);
      return ERRNO.SUCCESS;
    },
    fd_write(fd, iovsPtr, iovsLen, resultPtr) {
      checkBudget();
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind !== "out") return entry.kind === "stdin" ? ERRNO.BADF : ERRNO.ROFS;
      const v = view();
      let total = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = v.getUint32(iovsPtr + i * 8, true);
        const len = v.getUint32(iovsPtr + i * 8 + 4, true);
        const room = maxOutputBytes - outputBytes;
        if (len > room) {
          if (room > 0) captured[fd].push(bytesAt(ptr, room).slice());
          outputBytes = maxOutputBytes;
          truncated = true;
          throw new WasiAbort(`output limit of ${maxOutputBytes} bytes exceeded`);
        }
        captured[fd].push(bytesAt(ptr, len).slice());
        outputBytes += len;
        total += len;
      }
      v.setUint32(resultPtr, total, true);
      return ERRNO.SUCCESS;
    },
    fd_pwrite: () => ERRNO.ROFS,
    fd_allocate: () => ERRNO.ROFS,
    fd_filestat_set_size: () => ERRNO.ROFS,
    fd_filestat_set_times: () => ERRNO.ROFS,
    fd_renumber: () => ERRNO.NOTSUP,

    fd_readdir(fd, bufferPtr, bufferLen, cookie, resultPtr) {
      const entry = fds.get(fd);
      if (!entry) return ERRNO.BADF;
      if (entry.kind !== "dir") return ERRNO.NOTDIR;
      const names = (entry.listing ??= listDirectory(entry.path));
      const v = view();
      let used = 0;
      for (let i = Number(cookie); i < names.length && used < bufferLen; i++) {
        const name = utf8Encoder.encode(names[i]);
        const child = normalizePath(entry.path, names[i]);
        const record = new Uint8Array(24 + name.length);
        const recordView = new DataView(record.buffer);
        recordView.setBigUint64(0, BigInt(i + 1), true);  // d_next
        recordView.setBigUint64(8, BigInt(i + 1), true);  // d_ino
        recordView.setUint32(16, name.length, true);
        recordView.setUint8(20, isDirectory(child) ? FILETYPE.DIRECTORY : FILETYPE.REGULAR_FILE);
        record.set(name, 24);
        const chunk = record.subarray(0, Math.min(record.length, bufferLen - used));
        bytesAt(bufferPtr + used, chunk.length).set(chunk);
        used += chunk.length;
      }
      v.setUint32(resultPtr, used, true);
      return ERRNO.SUCCESS;
    },

    path_open(dirFd, _dirFlags, pathPtr, pathLen, oflags, rightsBase, _rightsInheriting, _fdFlags, resultPtr) {
      checkBudget();
      const dir = fds.get(dirFd);
      if (!dir) return ERRNO.BADF;
      if (dir.kind !== "dir") return ERRNO.NOTDIR;
      const path = normalizePath(dir.path, readString(pathPtr, pathLen));
      if (onOpen) onOpen(path);
      if (oflags & (OFLAGS.CREAT | OFLAGS.TRUNC)) return ERRNO.ROFS;
      const directory = isDirectory(path);
      const data = directory ? undefined : lookupFile(path);
      if (!directory && data === undefined) return ERRNO.NOENT;
      if (oflags & OFLAGS.DIRECTORY && !directory) return ERRNO.NOTDIR;
      if (BigInt(rightsBase) & RIGHTS_FD_WRITE) return directory ? ERRNO.ISDIR : ERRNO.ROFS;
      const fd = nextFd++;
      fds.set(fd, directory ? { kind: "dir", path } : { kind: "file", path, data, position: 0 });
      view().setUint32(resultPtr, fd, true);
      return ERRNO.SUCCESS;
    },
    path_filestat_get(dirFd, _flags, pathPtr, pathLen, resultPtr) {
      const dir = fds.get(dirFd);
      if (!dir) return ERRNO.BADF;
      if (dir.kind !== "dir") return ERRNO.NOTDIR;
      const path = normalizePath(dir.path, readString(pathPtr, pathLen));
      if (isDirectory(path)) return filestatFor({ kind: "dir" }, resultPtr);
      const data = lookupFile(path);
      if (data === undefined) return ERRNO.NOENT;
      return filestatFor({ kind: "file", data }, resultPtr);
    },
    path_readlink: () => ERRNO.INVAL,
    path_create_directory: () => ERRNO.ROFS,
    path_remove_directory: () => ERRNO.ROFS,
    path_unlink_file: () => ERRNO.ROFS,
    path_rename: () => ERRNO.ROFS,
    path_link: () => ERRNO.ROFS,
    path_symlink: () => ERRNO.ROFS,
    path_filestat_set_times: () => ERRNO.ROFS,

    sock_accept: () => ERRNO.NOSYS,
    sock_recv: () => ERRNO.NOSYS,
    sock_send: () => ERRNO.NOSYS,
    sock_shutdown: () => ERRNO.NOSYS,
  };

  let exitCode = 0;
  let failure = "";
  try {
    const instance = new WebAssembly.Instance(module, { wasi_snapshot_preview1: wasi });
    memory = instance.exports.memory;
    instance.exports._start();
  } catch (error) {
    if (error instanceof WasiExit) {
      exitCode = error.code;
    } else if (error instanceof WasiAbort) {
      exitCode = 124;
      failure = `\n[tungsten.wasm] aborted: ${error.reason}\n`;
    } else if (error instanceof RangeError || (typeof WebAssembly !== "undefined" && error instanceof WebAssembly.RuntimeError)) {
      // A trap (stack overflow, unreachable, out-of-bounds). The instance is
      // discarded either way; report it like a crashed process.
      exitCode = 134;
      failure = `\n[tungsten.wasm] trapped: ${error.message}\n`;
      if (options.debug) failure += `${error.stack}\n`;
    } else {
      throw error;
    }
  }

  const join = (chunks) => {
    const out = new Uint8Array(chunks.reduce((n, chunk) => n + chunk.length, 0));
    let offset = 0;
    for (const chunk of chunks) {
      out.set(chunk, offset);
      offset += chunk.length;
    }
    return out;
  };
  const stdoutBytes = join(captured[1]);
  const stderrBytes = join(captured[2]);
  return {
    stdout: utf8Decoder.decode(stdoutBytes),
    stderr: utf8Decoder.decode(stderrBytes) + failure,
    exitCode,
    truncated,
    stdoutBytes,
    stderrBytes,
  };
}
