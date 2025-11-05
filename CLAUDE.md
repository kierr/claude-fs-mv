# Claude File Redirect Plugin - AI Guidance

## Plugin Overview

This plugin provides configurable file redirection capabilities for Claude Code, automatically moving files based on user-defined patterns. It's designed to maintain project organization without requiring manual intervention.

## Key Implementation Details

### Hook Architecture
- **PreToolUse hook**: Intercepts Write operations before execution
- **Pattern matching**: Supports glob patterns, regex, and simple extensions
- **Path safety**: Comprehensive validation prevents dangerous redirections
- **Configuration**: JSON-based rules with hot reloading

### Safety Mechanisms
- Path traversal protection using Pathname.cleanpath
- Blocked destination lists for system directories
- Loop detection with environment variable tracking
- File size limits to prevent resource exhaustion

### Performance Considerations
- Configuration caching (5-minute TTL would be ideal if implementing session caching)
- Minimal pattern matching overhead
- Early exit for non-matching files
- Efficient directory creation only when needed

## Usage Context for Claude

When this plugin is active, Claude should:

1. **Be aware of automatic redirections**: Files created in root may automatically move to configured directories
2. **Understand pattern matching**: Know that *.md files might go to docs/misc, *.rb to scripts, etc.
3. **Respect exclusions**: README.md, CHANGELOG.md, and other excluded files stay in place
4. **Plan for directory structure**: Consider that target directories will be auto-created

## Common Scenarios

### Documentation Organization
```bash
# This will be redirected to docs/misc/
Creating documentation file: project-notes.md
```

### Script Organization
```bash
# This will be redirected to scripts/
Creating utility script: backup-helper.rb
```

### Test File Organization
```bash
# This will be redirected to tests/unit/ from anywhere
Creating test file: test_user_authentication.rb
```

## Configuration Guidance

The plugin uses a hierarchical configuration approach:

1. **Global settings**: Overall behavior (notifications, directory creation)
2. **Security settings**: Safety constraints and blocked paths
3. **Rules**: Specific pattern-to-destination mappings

## Error Handling

The plugin follows a graceful degradation approach:
- Configuration errors allow original file creation
- Pattern matching failures fall back to default behavior
- Directory creation failures don't block file creation
- Loop detection prevents infinite redirections

## Integration Notes

This plugin works alongside other file-related tools:
- Compatible with existing file creation workflows
- Doesn't interfere with Edit operations (only Write)
- Respects other hook permissions and validations
- Maintains file content integrity during redirection

## Debugging

When troubleshooting file redirection issues:

1. Check configuration validity with `/redirect:validate`
2. Verify pattern matching logic
3. Confirm destination directory permissions
4. Review security restrictions
5. Check for loop detection triggers

The plugin provides clear feedback when redirections occur, making it easy to understand why files end up in unexpected locations.