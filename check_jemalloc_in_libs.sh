#!/bin/bash

# Script to check all .a files in a directory for memory allocator symbols
# Usage: ./check_jemalloc_in_libs.sh [directory] [allocator]
#   directory: Target directory to search (default: current directory)
#   allocator: Allocator to search for - jemalloc, tcmalloc, mimalloc, or custom pattern (default: jemalloc)
#
# Examples:
#   ./check_jemalloc_in_libs.sh                           # Check current dir for jemalloc
#   ./check_jemalloc_in_libs.sh /path/to/libs             # Check specific dir for jemalloc
#   ./check_jemalloc_in_libs.sh /path/to/libs tcmalloc    # Check for tcmalloc
#   ./check_jemalloc_in_libs.sh . mimalloc                # Check current dir for mimalloc
#   ./check_jemalloc_in_libs.sh . "custom_alloc"          # Check for custom allocator pattern

set -e

TARGET_DIR="${1:-.}"
ALLOCATOR="${2:-jemalloc}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist"
    exit 1
fi

# Define allocator-specific search patterns and version strings
case "$ALLOCATOR" in
    jemalloc)
        SEARCH_PATTERN="jemalloc"
        VERSION_PATTERN="jemalloc.*version"
        ALLOCATOR_NAME="jemalloc"
        ;;
    tcmalloc)
        SEARCH_PATTERN="tcmalloc"
        VERSION_PATTERN="tcmalloc.*version"
        ALLOCATOR_NAME="tcmalloc"
        ;;
    mimalloc)
        SEARCH_PATTERN="mi_malloc"
        VERSION_PATTERN="mimalloc.*version"
        ALLOCATOR_NAME="mimalloc"
        ;;
    *)
        SEARCH_PATTERN="$ALLOCATOR"
        VERSION_PATTERN="${ALLOCATOR}.*version"
        ALLOCATOR_NAME="$ALLOCATOR"
        ;;
esac

echo "================================================"
echo "Checking for $ALLOCATOR_NAME in .a files"
echo "Target directory: $TARGET_DIR"
echo "Search pattern: $SEARCH_PATTERN"
echo "================================================"
echo ""

FOUND_COUNT=0
TOTAL_COUNT=0

# Store results for summary
declare -a LIBS_WITH_ALLOCATOR
declare -a LIBS_WITHOUT_ALLOCATOR

for lib in "$TARGET_DIR"/*.a; do
    [ -e "$lib" ] || continue
    
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    LIBNAME=$(basename "$lib")
    
    # Check for allocator symbols
    ALLOCATOR_SYMBOLS=$(nm "$lib" 2>/dev/null | grep -i "$SEARCH_PATTERN" || true)
    
    if [ -n "$ALLOCATOR_SYMBOLS" ]; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        LIBS_WITH_ALLOCATOR+=("$LIBNAME")
        
        echo "✓ FOUND: $LIBNAME"
        echo "  $ALLOCATOR_NAME symbols:"
        
        # Show first 10 allocator symbols
        echo "$ALLOCATOR_SYMBOLS" | head -10 | sed 's/^/    /'
        
        SYMBOL_COUNT=$(echo "$ALLOCATOR_SYMBOLS" | wc -l | tr -d ' ')
        if [ "$SYMBOL_COUNT" -gt 10 ]; then
            echo "    ... and $((SYMBOL_COUNT - 10)) more symbols"
        fi
        
        # Check for version string
        VERSION=$(strings "$lib" 2>/dev/null | grep -i "$VERSION_PATTERN" | head -1 || true)
        if [ -n "$VERSION" ]; then
            echo "  Version info: $VERSION"
        fi
        
        echo ""
    else
        LIBS_WITHOUT_ALLOCATOR+=("$LIBNAME")
    fi
done

echo "================================================"
echo "SUMMARY"
echo "================================================"
echo "Total .a files checked: $TOTAL_COUNT"
echo "Libraries WITH $ALLOCATOR_NAME: $FOUND_COUNT"
echo "Libraries WITHOUT $ALLOCATOR_NAME: $((TOTAL_COUNT - FOUND_COUNT))"
echo ""

if [ $FOUND_COUNT -gt 0 ]; then
    echo "Libraries containing $ALLOCATOR_NAME:"
    for lib in "${LIBS_WITH_ALLOCATOR[@]}"; do
        echo "  - $lib"
    done
    echo ""
fi

if [ $FOUND_COUNT -eq 0 ]; then
    echo "✓ No $ALLOCATOR_NAME found in any libraries"
else
    echo "⚠ Warning: $FOUND_COUNT libraries contain $ALLOCATOR_NAME symbols"
    echo "  This may cause memory allocator conflicts if your project"
    echo "  doesn't use $ALLOCATOR_NAME globally."
fi
