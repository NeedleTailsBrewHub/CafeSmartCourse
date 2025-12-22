#!/bin/bash

# Standalone script to sanitize sensitive configuration data
# SAFE FOR SKIP PROJECTS - Preserves Skip's required structure and consistency

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Generic values for sanitization
GENERIC_BUNDLE_ID="com.example.app"
GENERIC_ANDROID_PACKAGE="com.example.app"

echo -e "${BLUE}🔒 Configuration Sanitization Script (Skip-Safe)${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to sanitize Skip.env file
# CRITICAL: This must be done first and consistently
sanitize_skip_env() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing Skip.env: $file${NC}"
        
        # Create backup
        cp "$file" "$backup_file"
        echo -e "   💾 Backup created: $backup_file"
        
        # Sanitize bundle identifier and package name
        # IMPORTANT: Keep PRODUCT_NAME and other Skip-required fields intact
        sed -i '' \
            -e "s|PRODUCT_BUNDLE_IDENTIFIER = .*|PRODUCT_BUNDLE_IDENTIFIER = ${GENERIC_BUNDLE_ID}|g" \
            -e "s|ANDROID_PACKAGE_NAME = .*|ANDROID_PACKAGE_NAME = ${GENERIC_ANDROID_PACKAGE}|g" \
            "$file"
        
        echo -e "   ✅ Sanitized bundle identifier and package name"
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize Xcode project file
# NOTE: For Skip projects, we SKIP .pbxproj files entirely because:
# 1. Bundle identifiers come from Skip.env (already sanitized)
# 2. .pbxproj files have complex structure that's easy to break
# 3. Package references and product dependencies are fragile
# 4. Xcode will use Skip.env values automatically
sanitize_pbxproj() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Skipping Xcode project file: $file${NC}"
        echo -e "   ℹ️  Skip projects get bundle ID from Skip.env (already sanitized)"
        echo -e "   ℹ️  Modifying .pbxproj can break package references"
        echo -e "   ✅ No changes needed - Xcode will use Skip.env values"
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize Xcode config file
# NOTE: These include Skip.env, so we mainly check for any hardcoded values
sanitize_xcconfig() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing Xcode config: $file${NC}"
        
        # Check if file has hardcoded bundle ID (shouldn't, but just in case)
        if grep -q "PRODUCT_BUNDLE_IDENTIFIER = " "$file" && ! grep -q "#include.*Skip.env" "$file"; then
            # Create backup
            cp "$file" "$backup_file"
            echo -e "   💾 Backup created: $backup_file"
            
            # Only sanitize if there's a hardcoded value
            sed -i '' \
                -e "s|PRODUCT_BUNDLE_IDENTIFIER = [^;]*|PRODUCT_BUNDLE_IDENTIFIER = ${GENERIC_BUNDLE_ID}|g" \
                -e "s|DEVELOPMENT_TEAM = [^;]*|DEVELOPMENT_TEAM = |g" \
                "$file"
            
            echo -e "   ✅ Sanitized hardcoded values"
        else
            echo -e "   ℹ️  File uses Skip.env (no changes needed)"
        fi
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize Android build file
# NOTE: Skip projects use Skip.env automatically, but check for hardcoded values
sanitize_android_build() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing Android build: $file${NC}"
        
        # Check if file has hardcoded applicationId
        if grep -q 'applicationId\s*=' "$file"; then
            # Create backup
            cp "$file" "$backup_file"
            echo -e "   💾 Backup created: $backup_file"
            
            sed -i '' \
                -e "s|applicationId = \"[^\"]*\"|applicationId = \"${GENERIC_BUNDLE_ID}\"|g" \
                -e "s|applicationId = '[^']*'|applicationId = \"${GENERIC_BUNDLE_ID}\"|g" \
                "$file"
            
            echo -e "   ✅ Sanitized hardcoded applicationId"
        else
            echo -e "   ℹ️  File uses Skip.env automatically (no changes needed)"
        fi
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize Fastlane files
sanitize_fastlane() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing Fastlane: $file${NC}"
        
        # Check if file has hardcoded values (Skip projects use Skip.env)
        if grep -qE '(app_identifier|itunes_connect_team_id|itc_team_id|team_id)\s*=\s*"[^"]*"' "$file" && ! grep -q "ENV\['PRODUCT_BUNDLE_IDENTIFIER'\]" "$file"; then
            # Create backup
            cp "$file" "$backup_file"
            echo -e "   💾 Backup created: $backup_file"
            
            sed -i '' \
                -e "s|app_identifier = \"[^\"]*\"|app_identifier = \"${GENERIC_BUNDLE_ID}\"|g" \
                -e "s|itunes_connect_team_id = \"[^\"]*\"|itunes_connect_team_id = \"\"|g" \
                -e "s|itc_team_id = \"[^\"]*\"|itc_team_id = \"\"|g" \
                -e "s|team_id = \"[^\"]*\"|team_id = \"\"|g" \
                "$file"
            
            echo -e "   ✅ Sanitized hardcoded Fastlane values"
        else
            echo -e "   ℹ️  File uses Skip.env (no changes needed)"
        fi
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize Swift Constants file (if it has hardcoded hosts)
sanitize_constants() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        # Check if file has non-localhost hardcoded hosts
        if grep -qE 'wsHost.*String.*=.*"[^"]*"' "$file" && ! grep -q 'wsHost.*String.*=.*"localhost"' "$file"; then
            echo -e "${YELLOW}📝 Processing Constants: $file${NC}"
            
            # Create backup
            cp "$file" "$backup_file"
            echo -e "   💾 Backup created: $backup_file"
            
            # Sanitize host values to localhost
            sed -i '' \
                -e 's|wsHost: String = "[^"]*"|wsHost: String = "localhost"|g' \
                -e 's|httpHost: String = "http://[^"]*"|httpHost: String = "http://localhost:8080/"|g' \
                -e 's|httpHost: String = "https://[^"]*"|httpHost: String = "https://localhost:8080/"|g' \
                "$file"
            
            echo -e "   ✅ Sanitized host values"
            return 0
        else
            return 0  # Already safe or doesn't need changes
        fi
    else
        return 1
    fi
}

# Counter for processed files
processed_count=0

echo -e "${BLUE}🔍 Scanning Skip projects for configuration files...${NC}"
echo ""

# Define Skip project paths
SKIP_PROJECTS=(
    "Course Final Project/cafe-smart-app"
    "Course Production Project/cafe-smart"
)

# Process each Skip project
for project_path in "${SKIP_PROJECTS[@]}"; do
    if [[ ! -d "$project_path" ]]; then
        echo -e "${RED}⚠️  Skip project not found: $project_path${NC}"
        continue
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📦 Processing: $project_path${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # STEP 1: Sanitize Skip.env FIRST (this is the source of truth)
    echo -e "${YELLOW}📋 Step 1: Skip.env (Source of Truth)${NC}"
    if sanitize_skip_env "${project_path}/Skip.env"; then
        ((processed_count++))
    fi
    echo ""
    
    # STEP 2: Sanitize Xcode project file (must match Skip.env)
    echo -e "${YELLOW}📱 Step 2: Xcode Project${NC}"
    pbxproj_file=$(find "$project_path/Darwin" -name "*.pbxproj" -not -path "*/.build/*" 2>/dev/null | head -1)
    if [[ -n "$pbxproj_file" ]]; then
        if sanitize_pbxproj "$pbxproj_file"; then
            ((processed_count++))
        fi
    else
        echo -e "   ⚠️  No .pbxproj file found"
    fi
    echo ""
    
    # STEP 3: Sanitize Xcode config (usually just includes Skip.env)
    echo -e "${YELLOW}⚙️  Step 3: Xcode Config${NC}"
    xcconfig_file=$(find "$project_path/Darwin" -name "*.xcconfig" -not -path "*/.build/*" 2>/dev/null | head -1)
    if [[ -n "$xcconfig_file" ]]; then
        if sanitize_xcconfig "$xcconfig_file"; then
            ((processed_count++))
        fi
    else
        echo -e "   ⚠️  No .xcconfig file found"
    fi
    echo ""
    
    # STEP 4: Check Android build (usually uses Skip.env automatically)
    echo -e "${YELLOW}🤖 Step 4: Android Build${NC}"
    android_build_file="${project_path}/Android/app/build.gradle.kts"
    if [[ -f "$android_build_file" ]]; then
        if sanitize_android_build "$android_build_file"; then
            ((processed_count++))
        fi
    else
        echo -e "   ⚠️  No build.gradle.kts file found"
    fi
    echo ""
    
    # STEP 5: Sanitize Fastlane files
    echo -e "${YELLOW}🚀 Step 5: Fastlane${NC}"
    fastlane_appfile="${project_path}/Darwin/fastlane/Appfile"
    if [[ -f "$fastlane_appfile" ]]; then
        if sanitize_fastlane "$fastlane_appfile"; then
            ((processed_count++))
        fi
    fi
    
    fastlane_xcconfig=$(find "$project_path/Darwin/fastlane" -name "*.xcconfig" 2>/dev/null | head -1)
    if [[ -n "$fastlane_xcconfig" ]]; then
        if sanitize_fastlane "$fastlane_xcconfig"; then
            ((processed_count++))
        fi
    fi
    echo ""
    
    # STEP 6: Sanitize Swift Constants (if needed)
    echo -e "${YELLOW}🔧 Step 6: Swift Constants${NC}"
    constants_file=$(find "$project_path/Sources" -name "Constants.swift" 2>/dev/null | head -1)
    if [[ -n "$constants_file" ]]; then
        if sanitize_constants "$constants_file"; then
            ((processed_count++))
        else
            echo -e "   ℹ️  Constants already safe (using localhost)"
        fi
    else
        echo -e "   ℹ️  No Constants.swift found"
    fi
    echo ""
done

# Clean up backup files
echo ""
echo -e "${BLUE}🧹 Cleaning up backup files...${NC}"
backup_count=0
while IFS= read -r -d '' file; do
    echo -e "   🗑️  Removing: $file"
    rm "$file"
    ((backup_count++))
done < <(find . -name "*.backup.*" -not -path "./.git/*" -not -path "*/.build/*" -print0 2>/dev/null || true)

if [[ $backup_count -gt 0 ]]; then
    echo -e "${GREEN}✅ Removed $backup_count backup files${NC}"
else
    echo -e "${YELLOW}ℹ️  No backup files found to remove${NC}"
fi

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✅ Sanitization Complete!${NC}"
echo -e "${GREEN}📊 Processed $processed_count files${NC}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo -e "   1. Review the changes: git diff"
echo -e "   2. Verify Skip projects still work: skip verify"
echo -e "   3. Stage the sanitized files: git add ."
echo -e "   4. Commit your changes: git commit -m 'Sanitize sensitive configuration'"
echo ""
echo -e "${BLUE}🔒 Your sensitive data is now protected!${NC}"
echo -e "${GREEN}✅ Skip projects should remain functional${NC}"
