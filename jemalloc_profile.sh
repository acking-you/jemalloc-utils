#!/bin/bash

set -e

OUTPUT_DIR="./jeprof_output"
PROF_ACTIVE=true
ABORT_ON_ERROR=true
INTERVAL_MB=""

usage() {
    echo "Usage: $0 [options] -- <program> [program_args...]"
    echo ""
    echo "Options:"
    echo "  -o, --output DIR          Output directory for profile files (default: ./jeprof_output)"
    echo "  -a, --active BOOL         Enable profiling at startup (default: true)"
    echo "  -c, --abort-on-error BOOL Abort if jemalloc profiling not available (default: true)"
    echo "  -i, --interval-mb NUM     Dump profile every NUM MB allocated (optional, e.g., 100, 512, 1024)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  # Only dump on exit"
    echo "  $0 -o /tmp/profiles -- ./bin/my_program arg1 arg2"
    echo ""
    echo "  # Dump every 512MB allocated + final dump on exit"
    echo "  $0 -o /tmp/profiles -i 512 -- ./bin/my_program arg1 arg2"
    echo ""
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -a|--active)
            PROF_ACTIVE="$2"
            shift 2
            ;;
        -c|--abort-on-error)
            ABORT_ON_ERROR="$2"
            shift 2
            ;;
        -i|--interval-mb)
            INTERVAL_MB="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Error: No program specified"
    usage
fi

PROGRAM="$1"
shift
PROGRAM_ARGS="$@"

if [ ! -x "$PROGRAM" ]; then
    echo "Error: Program not found or not executable: $PROGRAM"
    exit 1
fi

echo "========================================"
echo "Checking dependencies..."
echo "========================================"

# Check and install jeprof if needed
if ! command -v jeprof &> /dev/null; then
    echo "jeprof not found. Attempting to install..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "Installing via apt-get..."
            sudo apt-get update && sudo apt-get install -y libjemalloc-dev
        elif command -v yum &> /dev/null; then
            echo "Installing via yum..."
            sudo yum install -y jemalloc-devel
        else
            echo "Error: No supported package manager found (apt-get/yum)"
            echo "Please manually install jemalloc-dev or jemalloc-devel package"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            echo "Installing via Homebrew..."
            brew install jemalloc
        else
            echo "Error: Homebrew not found"
            echo "Please install Homebrew or manually install jemalloc"
            exit 1
        fi
    else
        echo "Error: Unsupported OS: $OSTYPE"
        exit 1
    fi
    
    if ! command -v jeprof &> /dev/null; then
        echo "Error: jeprof installation failed"
        exit 1
    fi
    
    echo "✓ jeprof installed successfully"
else
    echo "✓ jeprof found: $(which jeprof)"
fi

# Check if graphviz is available (for PDF generation)
if ! command -v dot &> /dev/null; then
    echo "⚠ graphviz not found. Attempting to install..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "Installing graphviz via apt-get..."
            sudo apt-get install -y graphviz
        elif command -v yum &> /dev/null; then
            echo "Installing graphviz via yum..."
            sudo yum install -y graphviz
        else
            echo "⚠ Warning: Could not install graphviz automatically"
            echo "  Please manually install: yum install graphviz  # or apt-get install graphviz"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            echo "Installing graphviz via Homebrew..."
            brew install graphviz
        else
            echo "⚠ Warning: Homebrew not found, cannot install graphviz"
        fi
    fi
    
    if command -v dot &> /dev/null; then
        echo "✓ graphviz installed successfully"
    else
        echo "⚠ Warning: graphviz installation failed. PDF/SVG generation will not be available"
    fi
else
    echo "✓ graphviz found: $(which dot)"
fi

# Check if ghostscript is available (for PDF generation)
if ! command -v ps2pdf &> /dev/null; then
    echo "⚠ ghostscript not found. Attempting to install..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "Installing ghostscript via apt-get..."
            sudo apt-get install -y ghostscript
        elif command -v yum &> /dev/null; then
            echo "Installing ghostscript via yum..."
            sudo yum install -y ghostscript
        else
            echo "⚠ Warning: Could not install ghostscript automatically"
            echo "  Please manually install: yum install ghostscript  # or apt-get install ghostscript"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            echo "Installing ghostscript via Homebrew..."
            brew install ghostscript
        else
            echo "⚠ Warning: Homebrew not found, cannot install ghostscript"
        fi
    fi
    
    if command -v ps2pdf &> /dev/null; then
        echo "✓ ghostscript installed successfully"
    else
        echo "⚠ Warning: ghostscript installation failed. PDF generation will not be available (SVG will still work)"
    fi
else
    echo "✓ ghostscript found: $(which ps2pdf)"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

PROF_PREFIX="$OUTPUT_DIR/jeprof"

echo ""
echo "========================================"
echo "Jemalloc Profiling Configuration"
echo "========================================"
echo "Program: $PROGRAM $PROGRAM_ARGS"
echo "Output directory: $OUTPUT_DIR"
echo "Profile prefix: $PROF_PREFIX"
echo "Profiling active: $PROF_ACTIVE"
echo "Abort on error: $ABORT_ON_ERROR"
if [ -n "$INTERVAL_MB" ]; then
    echo "Interval: Dump every ${INTERVAL_MB}MB allocated"
else
    echo "Interval: Only dump on exit"
fi
echo "========================================"
echo ""

# Configure MALLOC_CONF
# abort_conf:true will cause jemalloc to abort if any conf option is invalid or unavailable
# prof_final:true generates a final dump on exit
# lg_prof_interval:N triggers a dump every 2^N bytes allocated
# lg_prof_sample uses default (19, which is 2^19 = 512KB sampling interval)

MALLOC_CONF_BASE="prof:true,prof_active:${PROF_ACTIVE},prof_prefix:${PROF_PREFIX},prof_final:true,lg_prof_sample:19"

if [ -n "$INTERVAL_MB" ]; then
    # Convert MB to bytes and calculate lg
    BYTES=$((INTERVAL_MB * 1024 * 1024))
    LG_PROF_INTERVAL=$(echo "l($BYTES)/l(2)" | bc -l | awk '{printf "%.0f\n", $1}')
    echo "Calculated lg_prof_interval: $LG_PROF_INTERVAL (2^$LG_PROF_INTERVAL = ~${INTERVAL_MB}MB)"
    MALLOC_CONF_BASE="${MALLOC_CONF_BASE},lg_prof_interval:${LG_PROF_INTERVAL}"
fi

if [ "$ABORT_ON_ERROR" = "true" ]; then
    export MALLOC_CONF="abort_conf:true,${MALLOC_CONF_BASE}"
else
    export MALLOC_CONF="${MALLOC_CONF_BASE}"
fi

echo "Starting program with jemalloc profiling..."
echo "MALLOC_CONF=$MALLOC_CONF"
echo ""
if [ "$ABORT_ON_ERROR" = "true" ]; then
    echo "Note: Program will abort immediately if jemalloc profiling is not available"
    echo "      (due to abort_conf:true)"
fi
echo ""

# Start the program in background
"$PROGRAM" $PROGRAM_ARGS &
PID=$!

# Give the program a moment to start
sleep 2

# Check if program is still running (didn't crash on startup)
if ! kill -0 $PID 2>/dev/null; then
    echo ""
    echo "========================================"
    echo "ERROR: Program exited immediately!"
    echo "========================================"
    echo ""
    if [ "$ABORT_ON_ERROR" = "true" ]; then
        echo "This likely means jemalloc profiling is NOT available in the binary."
        echo ""
        echo "Possible reasons:"
        echo "  1. Jemalloc was not compiled with --enable-prof"
        echo "  2. Binary is not linked with jemalloc at all"
        echo "  3. Binary is using a different allocator (tcmalloc, system malloc, etc.)"
        echo ""
        echo "To fix this:"
        echo "  1. Ensure jemalloc is built with profiling support"
        echo "  2. Check vcpkg.json or build configuration for jemalloc features"
        echo "  3. Verify the binary is actually using jemalloc"
        echo ""
        echo "To run without the abort check, use: --abort-on-error false"
    else
        echo "Check program logs for error messages"
    fi
    exit 1
fi

echo "✓ Program started successfully with PID: $PID"
echo "✓ Jemalloc profiling is available and configured"
echo ""
echo "Program is running. Press Ctrl+C to stop and generate final heap dump."
echo ""

cleanup() {
    echo ""
    echo "Received termination signal. Generating heap dump..."
    
    # Check if there are already heap files
    EXISTING_COUNT=$(ls "$OUTPUT_DIR"/jeprof.*.heap 2>/dev/null | wc -l)
    
    if [ "$EXISTING_COUNT" -gt 0 ]; then
        echo "✓ Found existing heap profile file(s), skipping signal"
    else
        # Trigger jemalloc heap dump with SIGUSR2
        echo "Sending SIGUSR2 to trigger heap dump..."
        kill -SIGUSR2 $PID 2>/dev/null || true
        
        # Wait for heap dump file to be generated (check every 2s, max 30s)
        WAIT_COUNT=0
        MAX_WAIT=15
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            sleep 2
            CURRENT_COUNT=$(ls "$OUTPUT_DIR"/jeprof.*.heap 2>/dev/null | wc -l)
            if [ $CURRENT_COUNT -gt 0 ]; then
                echo "✓ Heap dump generated"
                break
            fi
            WAIT_COUNT=$((WAIT_COUNT + 1))
            if [ $((WAIT_COUNT % 3)) -eq 0 ]; then
                echo "  Waiting for heap dump... ($((WAIT_COUNT * 2))s)"
            fi
        done
        
        if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
            echo "⚠ Timeout waiting for heap dump (30s), proceeding with termination..."
        fi
    fi
    
    echo "Stopping program (PID: $PID)..."
    kill -TERM $PID 2>/dev/null || true
    wait $PID 2>/dev/null || true
    echo ""
    
    HEAP_FILES=$(ls "$OUTPUT_DIR"/jeprof.*.heap 2>/dev/null | wc -l)
    
    if [ "$HEAP_FILES" -eq 0 ]; then
        echo "⚠ Warning: No heap profile files were generated!"
        echo ""
        echo "Possible reasons:"
        echo "  1. Program exited before heap dump could be written"
        echo "  2. No memory allocations occurred"
        echo "  3. Jemalloc profiling was not properly configured"
        echo ""
    else
        echo "✓ Generated $HEAP_FILES heap profile file(s) in: $OUTPUT_DIR"
        echo ""
        
        # Find the latest heap file
        LATEST_HEAP=$(ls -t "$OUTPUT_DIR"/jeprof.*.heap 2>/dev/null | head -1)
        
        echo "To analyze results:"
        echo "  # Analyze latest heap file (recommended)"
        echo "  jeprof --text $PROGRAM $LATEST_HEAP | head -30"
        echo ""
        echo "  # View current memory usage (not cumulative)"
        echo "  jeprof --inuse_space --text $PROGRAM $LATEST_HEAP | head -30"
        echo ""
        echo "  # Generate PDF call graph"
        echo "  jeprof --pdf --drop_negative $PROGRAM $LATEST_HEAP > profile.pdf"
        echo ""
        echo "  # Generate SVG call graph"
        echo "  jeprof --svg --drop_negative $PROGRAM $LATEST_HEAP > profile.svg"
        echo ""
        echo "  # Generate simplified graph (top 30 nodes only)"
        echo "  jeprof --svg --nodecount=30 --drop_negative $PROGRAM $LATEST_HEAP > profile_simple.svg"
        echo ""
        echo "  # Verify symbols from all libraries (arrow, brpc, redis, rocksdb, etc.)"
        echo "  jeprof --text $PROGRAM $LATEST_HEAP | grep -E '(arrow|brpc|redis|rocksdb|parquet)'"
        echo ""
        echo "  # Show detailed allocation sites with line numbers"
        echo "  jeprof --text --lines $PROGRAM $LATEST_HEAP | head -50"
        echo ""
        echo "Note: Using wildcard (jeprof.*.heap) will merge all heap files and show inflated numbers!"
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM

# Wait for program to exit
wait $PID 2>/dev/null || true

echo ""
echo "Program exited normally. Profile files saved in: $OUTPUT_DIR"

# Show final file count
HEAP_FILES=$(ls "$OUTPUT_DIR"/jeprof.*.heap 2>/dev/null | wc -l)
if [ "$HEAP_FILES" -gt 0 ]; then
    echo "✓ Generated $HEAP_FILES heap profile file(s)"
    echo ""
    echo "To analyze results:"
    echo "  jeprof --text $PROGRAM $OUTPUT_DIR/jeprof.*.heap | head -30"
else
    echo "⚠ No heap profile files were generated"
fi
