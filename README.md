# Jemalloc Utilities

A collection of bash utilities for jemalloc profiling and memory allocator detection in static libraries.

## Scripts

### 1. jemalloc_profile.sh

A wrapper script for running programs with jemalloc memory profiling enabled.

**Features:**
- Automatic dependency installation (jeprof, graphviz, ghostscript)
- Configurable profiling intervals (dump every N MB allocated)
- Heap dump on program exit
- Signal-based heap dump generation (SIGUSR2)
- Automatic verification of jemalloc availability

**Usage:**
```bash
./jemalloc_profile.sh [options] -- <program> [program_args...]
```

**Options:**
- `-o, --output DIR` - Output directory for profile files (default: ./jeprof_output)
- `-a, --active BOOL` - Enable profiling at startup (default: true)
- `-c, --abort-on-error BOOL` - Abort if jemalloc profiling not available (default: true)
- `-i, --interval-mb NUM` - Dump profile every NUM MB allocated (optional)
- `-h, --help` - Show help message

**Examples:**
```bash
# Only dump on exit
./jemalloc_profile.sh -o /tmp/profiles -- ./bin/my_program arg1 arg2

# Dump every 512MB allocated + final dump on exit
./jemalloc_profile.sh -o /tmp/profiles -i 512 -- ./bin/my_program arg1 arg2

# Disable abort-on-error for testing
./jemalloc_profile.sh -c false -- ./bin/my_program
```

**Analyzing Results:**
```bash
# View allocation summary
jeprof --text ./bin/my_program ./jeprof_output/jeprof.*.heap | head -30

# View current memory usage (not cumulative)
jeprof --inuse_space --text ./bin/my_program ./jeprof_output/jeprof.*.heap | head -30

# Generate PDF call graph
jeprof --pdf --drop_negative ./bin/my_program ./jeprof_output/jeprof.*.heap > profile.pdf

# Generate SVG call graph
jeprof --svg --drop_negative ./bin/my_program ./jeprof_output/jeprof.*.heap > profile.svg
```

### 2. check_jemalloc_in_libs.sh

Scans static library files (.a) for memory allocator symbols to detect potential allocator conflicts.

**Features:**
- Supports multiple allocators: jemalloc, tcmalloc, mimalloc, custom patterns
- Symbol extraction and counting
- Version detection
- Summary report with conflict warnings

**Usage:**
```bash
./check_jemalloc_in_libs.sh [directory] [allocator]
```

**Parameters:**
- `directory` - Target directory to search (default: current directory)
- `allocator` - Allocator to search for: jemalloc, tcmalloc, mimalloc, or custom pattern (default: jemalloc)

**Examples:**
```bash
# Check current directory for jemalloc
./check_jemalloc_in_libs.sh

# Check specific directory for jemalloc
./check_jemalloc_in_libs.sh /path/to/libs

# Check for tcmalloc
./check_jemalloc_in_libs.sh /path/to/libs tcmalloc

# Check current directory for mimalloc
./check_jemalloc_in_libs.sh . mimalloc

# Check for custom allocator pattern
./check_jemalloc_in_libs.sh . "custom_alloc"
```

**Output:**
- List of libraries containing allocator symbols
- Symbol counts and sample symbols
- Version information (if available)
- Summary statistics and conflict warnings

## Requirements

### jemalloc_profile.sh
- bash
- bc (for interval calculations)
- jeprof (auto-installed if missing)
- graphviz (optional, for PDF/SVG generation, auto-installed)
- ghostscript (optional, for PDF generation, auto-installed)
- jemalloc-enabled binary

### check_jemalloc_in_libs.sh
- bash
- nm (binutils)
- strings (binutils)
- grep

## Platform Support

- **Linux** (apt-get, yum)
- **macOS** (Homebrew)

## License

MIT
