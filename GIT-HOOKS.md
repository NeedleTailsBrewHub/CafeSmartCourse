# Git Hooks for Security

This repository includes Git hooks to automatically sanitize sensitive configuration data before commits.

## 🔒 Security Features

### Pre-commit Hook
The pre-commit hook automatically removes sensitive data from configuration files:

- **Bundle Identifiers**: Replaces with `com.example.app`
- **Development Teams**: Removes team IDs
- **Application IDs**: Replaces with `com.example.app`
- **Environment Variables**: Sanitizes sensitive env vars
- **Database URLs**: Replaces MongoDB URLs with example values
- **HMAC Secrets**: Replaces with example secret
- **Admin Usernames**: Replaces with example email
- **Host Configurations**: Replaces hardcoded hosts with example values

### Files Protected
- Xcode project files (`*.pbxproj`)
- Android build files (`build.gradle.kts`)
- Xcode config files (`*.xcconfig`)
- Fastlane files (`Appfile`, `*.xcconfig`)
- Environment files (`Skip.env`)

## 🚀 Usage

### Automatic (Recommended)
The pre-commit hook runs automatically on every commit attempt:

```bash
git add .
git commit -m "Your commit message"
# Hook runs automatically and sanitizes files
```

### Manual Sanitization
Run the standalone sanitization script:

```bash
./sanitize-config.sh
```

This will:
1. Create backups of all configuration files
2. Sanitize sensitive data
3. Show you what was changed

## 📁 Files Created

### Git Hook
- `.git/hooks/pre-commit` - Automatic pre-commit sanitization

### Standalone Script
- `sanitize-config.sh` - Manual sanitization script

### Backup Files
When sanitizing, backup files are created with timestamps:
- `project.pbxproj.backup.20250919_192843`
- `build.gradle.kts.backup.20250919_192845`
- etc.

## ⚙️ Configuration

### Customizing Sanitization
Edit the sanitization patterns in both files:

```bash
# In .git/hooks/pre-commit or sanitize-config.sh
sed -i '' \
    -e 's/PRODUCT_BUNDLE_IDENTIFIER = [^;]*/PRODUCT_BUNDLE_IDENTIFIER = com.example.app/g' \
    -e 's/DEVELOPMENT_TEAM = [^;]*/DEVELOPMENT_TEAM = /g' \
    # Add more patterns here
    "$file"
```

### Disabling the Hook
To temporarily disable the pre-commit hook:

```bash
mv .git/hooks/pre-commit .git/hooks/pre-commit.disabled
```

To re-enable:

```bash
mv .git/hooks/pre-commit.disabled .git/hooks/pre-commit
```

## 🔍 What Gets Sanitized

### Xcode Files
- `PRODUCT_BUNDLE_IDENTIFIER = com.yourcompany.yourapp` → `PRODUCT_BUNDLE_IDENTIFIER = com.example.app`
- `DEVELOPMENT_TEAM = ABC123DEF4` → `DEVELOPMENT_TEAM = `
- `CFBundleIdentifier = com.yourcompany.yourapp` → `CFBundleIdentifier = com.example.app`

### Android Files
- `applicationId = "com.yourcompany.yourapp"` → `applicationId = "com.example.app"`
- `teamId = "ABC123DEF4"` → `teamId = ""`

### Fastlane Files
- `app_identifier = "com.yourcompany.yourapp"` → `app_identifier = "com.example.app"`
- `itunes_connect_team_id = "ABC123DEF4"` → `itunes_connect_team_id = ""`
- `itc_team_id = "ABC123DEF4"` → `itc_team_id = ""`

### Environment Files
- `APPLE_TEAM_ID=ABC123DEF4` → `APPLE_TEAM_ID=`
- `BUNDLE_IDENTIFIER=com.yourcompany.yourapp` → `BUNDLE_IDENTIFIER=com.example.app`
- `APPLICATION_ID=com.yourcompany.yourapp` → `APPLICATION_ID=com.example.app`
- `MONGO_URL=mongodb://user:pass@host:port/db` → `MONGO_URL=mongodb://localhost:27017/example`
- `HMAC_SECRET=your-secret-key` → `HMAC_SECRET=example-secret-key`
- `ADMIN_USERNAMES=admin@yourcompany.com` → `ADMIN_USERNAMES=admin@example.com`

### Host Configurations
- `wsHost: String = "YourHost.local"` → `wsHost: String = "localhost"`
- `httpHost: String = "http://YourHost.local:8080/"` → `httpHost: String = "http://localhost:8080/"`
- `httpHost: String = "https://YourHost.local:8080/"` → `httpHost: String = "https://localhost:8080/"`

## 🛡️ Security Benefits

1. **Prevents Accidental Exposure**: Sensitive data is automatically removed before commits
2. **Consistent Sanitization**: Same patterns applied across all projects
3. **Backup Safety**: Original files are backed up before modification
4. **Manual Override**: Can run sanitization manually when needed
5. **Comprehensive Coverage**: Handles all common configuration file types

## 🚨 Important Notes

- **Backup Files**: Always review backup files before deleting them
- **Team Coordination**: Inform team members about the sanitization process
- **Local Development**: You'll need to restore real values for local development
- **CI/CD**: Ensure your CI/CD pipeline handles sanitized configuration appropriately

## 🔧 Troubleshooting

### Hook Not Running
Check if the hook is executable:
```bash
ls -la .git/hooks/pre-commit
# Should show: -rwxr-xr-x
```

### Files Not Being Sanitized
Check if files are in the correct locations:
```bash
find . -name "*.pbxproj" -not -path "./.git/*" -not -path "*/.build/*"
```

### Manual Restoration
To restore from backup:
```bash
cp project.pbxproj.backup.20250919_192843 project.pbxproj
```

## 📝 Contributing

When adding new file types or patterns:

1. Update both `.git/hooks/pre-commit` and `sanitize-config.sh`
2. Test with the manual script first
3. Update this documentation
4. Test the pre-commit hook

---

**Remember**: This system protects your sensitive data but requires team coordination for local development workflows.
