#!/bin/bash

# CafeSmart ML DocC Tutorial Build Script
# This script helps build the DocC documentation using Xcode

set -e

echo "🏪 Building CafeSmart ML DocC Tutorial..."

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "❌ Error: Package.swift not found. Please run this script from the CafeSmartMLTutorial.docc directory."
    exit 1
fi

# Check if Xcode is available
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode not found. Please install Xcode to build DocC documentation."
    exit 1
fi

# Build the package first
echo "📦 Building Swift package..."
swift build

# Run tests to ensure everything works
echo "🧪 Running tests..."
swift test

echo "✅ Package built and tested successfully!"

echo ""
echo "📚 To view the documentation:"
echo "1. Open this directory in Xcode"
echo "2. Select Product > Build Documentation"
echo "3. View the documentation in Xcode's Documentation tab"
echo ""
echo "🌐 To build for web hosting:"
echo "   xcodebuild docbuild -scheme CafeSmartMLTutorial"
echo ""
echo "📖 Documentation files are located in:"
echo "   - Tutorials/CafeSmartMLTutorial.md"
echo "   - Documentation.docc/Documentation.md"
echo "   - Documentation.docc/MLPredictions.md"
echo "   - Documentation.docc/CoreMLIntegration.md"

echo ""
echo "🎉 CafeSmart ML DocC Tutorial is ready!"
