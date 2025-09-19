#!/bin/bash

# Standalone script to sanitize sensitive configuration data
# Run this script manually to clean up bundle identifiers and development teams

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Configuration Sanitization Script${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Function to sanitize a file
sanitize_file() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing: $file${NC}"
        
        # Create backup
        cp "$file" "$backup_file"
        echo -e "   💾 Backup created: $backup_file"
        
        # Remove bundle identifiers and development teams
        sed -i '' \
            -e 's/PRODUCT_BUNDLE_IDENTIFIER = [^;]*/PRODUCT_BUNDLE_IDENTIFIER = com.example.app/g' \
            -e 's/DEVELOPMENT_TEAM = [^;]*/DEVELOPMENT_TEAM = /g' \
            -e 's/CFBundleIdentifier = [^;]*/CFBundleIdentifier = com.example.app/g' \
            -e 's/applicationId = "[^"]*"/applicationId = "com.example.app"/g' \
            -e 's/teamId = "[^"]*"/teamId = ""/g' \
            -e 's/app_identifier = "[^"]*"/app_identifier = "com.example.app"/g' \
            -e 's/itunes_connect_team_id = "[^"]*"/itunes_connect_team_id = ""/g' \
            -e 's/itc_team_id = "[^"]*"/itc_team_id = ""/g' \
            -e 's/team_id = "[^"]*"/team_id = ""/g' \
            -e 's/MONGO_URL=[^[:space:]]*/MONGO_URL=mongodb:\/\/localhost:27017\/example/g' \
            -e 's/HMAC_SECRET=[^[:space:]]*/HMAC_SECRET=example-secret-key/g' \
            -e 's/ADMIN_USERNAMES=[^[:space:]]*/ADMIN_USERNAMES=admin@example.com/g' \
            -e 's/wsHost: String = "[^"]*"/wsHost: String = "example.local"/g' \
            -e 's/httpHost: String = "http:\/\/[^"]*"/httpHost: String = "http:\/\/example.local:8080\/"/g' \
            -e 's/httpHost: String = "https:\/\/[^"]*"/httpHost: String = "https:\/\/example.local:8080\/"/g' \
            "$file"
        
        echo -e "   ✅ Sanitized bundle identifiers and development teams"
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Function to sanitize environment files
sanitize_env_file() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}📝 Processing: $file${NC}"
        
        # Create backup
        cp "$file" "$backup_file"
        echo -e "   💾 Backup created: $backup_file"
        
        # Remove sensitive environment variables
        sed -i '' \
            -e 's/APPLE_TEAM_ID=[^[:space:]]*/APPLE_TEAM_ID=/g' \
            -e 's/BUNDLE_IDENTIFIER=[^[:space:]]*/BUNDLE_IDENTIFIER=com.example.app/g' \
            -e 's/APPLICATION_ID=[^[:space:]]*/APPLICATION_ID=com.example.app/g' \
            -e 's/MONGO_URL=[^[:space:]]*/MONGO_URL=mongodb:\/\/localhost:27017\/example/g' \
            -e 's/HMAC_SECRET=[^[:space:]]*/HMAC_SECRET=example-secret-key/g' \
            -e 's/ADMIN_USERNAMES=[^[:space:]]*/ADMIN_USERNAMES=admin@example.com/g' \
            "$file"
        
        echo -e "   ✅ Sanitized environment variables"
        return 0
    else
        echo -e "   ⚠️  File not found: $file"
        return 1
    fi
}

# Counter for processed files
processed_count=0

echo -e "${BLUE}🔍 Scanning for configuration files...${NC}"
echo ""

# Process Xcode project files
echo -e "${YELLOW}📱 Xcode Project Files:${NC}"
while IFS= read -r -d '' file; do
    if sanitize_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "*.pbxproj" -not -path "./.git/*" -not -path "*/.build/*" -print0)

# Process Android build files
echo -e "${YELLOW}🤖 Android Build Files:${NC}"
while IFS= read -r -d '' file; do
    if sanitize_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "build.gradle.kts" -not -path "./.git/*" -not -path "*/.build/*" -print0)

# Process Xcode config files
echo -e "${YELLOW}⚙️  Xcode Config Files:${NC}"
while IFS= read -r -d '' file; do
    if sanitize_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "*.xcconfig" -not -path "./.git/*" -not -path "*/.build/*" -print0)

# Process Fastlane files
echo -e "${YELLOW}🚀 Fastlane Files:${NC}"
while IFS= read -r -d '' file; do
    if sanitize_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "Appfile" -not -path "./.git/*" -not -path "*/.build/*" -print0)

while IFS= read -r -d '' file; do
    if sanitize_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "*.xcconfig" -path "*/fastlane/*" -not -path "./.git/*" -not -path "*/.build/*" -print0)

# Process environment files
echo -e "${YELLOW}🌍 Environment Files:${NC}"
while IFS= read -r -d '' file; do
    if sanitize_env_file "$file"; then
        ((processed_count++))
    fi
    echo ""
done < <(find . -name "Skip.env" -not -path "./.git/*" -not -path "*/.build/*" -print0)

echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}✅ Sanitization Complete!${NC}"
echo -e "${GREEN}📊 Processed $processed_count files${NC}"
echo ""
echo -e "${YELLOW}💡 Next steps:${NC}"
echo -e "   1. Review the changes: git diff"
echo -e "   2. Stage the sanitized files: git add ."
echo -e "   3. Commit your changes: git commit -m 'Sanitize sensitive configuration'"
echo ""
echo -e "${BLUE}🔒 Your sensitive data is now protected!${NC}"
