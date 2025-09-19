#!/bin/bash

# CafeSmart ML DocC Setup Verification Script
# This script verifies that the DocC documentation is properly set up

set -e

echo "🔍 Verifying CafeSmart ML DocC Setup..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if file exists
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅${NC} $1"
        return 0
    else
        echo -e "${RED}❌${NC} $1 (missing)"
        return 1
    fi
}

# Function to check if directory exists
check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✅${NC} $1/"
        return 0
    else
        echo -e "${RED}❌${NC} $1/ (missing)"
        return 1
    fi
}

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}❌ Error: Package.swift not found. Please run this script from the CafeSmartMLTutorial.docc directory.${NC}"
    exit 1
fi

echo "📦 Checking Swift Package Structure..."

# Check core package files
check_file "Package.swift"
check_file "README.md"

# Check source files
check_dir "Sources"
check_dir "Sources/CafeSmartMLTutorial"
check_file "Sources/CafeSmartMLTutorial/CafeSmartMLTutorial.swift"

# Check test files
check_dir "Tests"
check_dir "Tests/CafeSmartMLTutorialTests"
check_file "Tests/CafeSmartMLTutorialTests/CafeSmartMLTutorialTests.swift"

echo ""
echo "📚 Checking DocC Documentation Structure..."

# Check DocC files
check_dir "Documentation.docc"
check_file "Documentation.docc/Documentation.md"
check_file "Documentation.docc/MLPredictions.md"
check_file "Documentation.docc/CoreMLIntegration.md"
check_file "Documentation.docc/CafeSmartMLTutorial.docc"

# Check tutorial files
check_dir "Tutorials"
check_file "Tutorials/CafeSmartMLTutorial.md"

echo ""
echo "🔧 Checking Build Tools..."

# Check build script
check_file "build-docs.sh"
check_file "XCODE_GUIDE.md"

echo ""
echo "🧪 Testing Package Build..."

# Test if the package builds
if swift build > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Package builds successfully${NC}"
else
    echo -e "${RED}❌ Package build failed${NC}"
    echo "Running build with verbose output:"
    swift build
    exit 1
fi

echo ""
echo "🧪 Testing Package Tests..."

# Test if the tests pass
if swift test > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Tests pass successfully${NC}"
else
    echo -e "${RED}❌ Tests failed${NC}"
    echo "Running tests with verbose output:"
    swift test
    exit 1
fi

echo ""
echo "📋 Summary:"

# Count files
source_files=$(find Sources -name "*.swift" | wc -l)
test_files=$(find Tests -name "*.swift" | wc -l)
doc_files=$(find Documentation.docc -name "*.md" | wc -l)
tutorial_files=$(find Tutorials -name "*.md" | wc -l)

echo "📁 Source files: $source_files"
echo "🧪 Test files: $test_files"
echo "📖 Documentation files: $doc_files"
echo "📚 Tutorial files: $tutorial_files"

echo ""
echo -e "${GREEN}🎉 CafeSmart ML DocC setup is verified and ready!${NC}"
echo ""
echo "📚 Next Steps:"
echo "1. Open this directory in Xcode: File > Open..."
echo "2. Build documentation: Product > Build Documentation"
echo "3. View in Organizer: Window > Organizer > Documentation tab"
echo ""
echo "📖 For detailed instructions, see XCODE_GUIDE.md"
echo "🔧 For build automation, run: ./build-docs.sh"
