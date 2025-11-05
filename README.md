# FS-MV Plugin

A configurable Claude Code plugin that automatically redirects files based on patterns to keep your project organized.

## Features

- **Pattern-based redirection**: Support for glob patterns, regex, and simple extensions
- **Flexible configuration**: JSON-based configuration with rule management
- **Safety features**: Path traversal protection and system directory guards
- **Auto-directory creation**: Automatically creates target directories when needed
- **Exclude patterns**: Keep specific files in place with exclusion lists
- **Loop detection**: Prevents infinite redirection loops

## Installation

```bash
# Add the marketplace
/plugin marketplace add https://github.com/kierr/claude

# Install the plugin
/plugin install fs-mv@kierr
```

## Configuration

Edit the configuration file at `.claude-plugin/config/redirect-rules.json` in the plugin directory:

### Example Configuration

```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "markdown-docs",
      "pattern": "*.md",
      "source_location": "root_only",
      "destination": "docs/misc",
      "exclude": ["README.md", "CHANGELOG.md"],
      "enabled": true
    },
    {
      "name": "ruby-scripts",
      "pattern": "*.rb",
      "source_location": "root_only",
      "destination": "scripts",
      "exclude": ["Rakefile", "Gemfile"],
      "enabled": true
    },
    {
      "name": "test-files",
      "pattern": "test_*.rb",
      "source_location": "anywhere",
      "destination": "tests/unit",
      "enabled": true
    }
  ]
}
```

### Rule Properties

- **name**: Descriptive name for the rule
- **pattern**: File pattern to match (glob, regex, or extension)
- **source_location**: Where files can be redirected from (`root_only` or `anywhere`)
- **destination**: Target directory for redirected files
- **exclude**: Array of filenames to exclude from redirection
- **enabled**: Whether the rule is active

### Pattern Types

1. **Glob patterns**: `*.md`, `test_*.rb`, `*.config.*`
2. **Regex patterns**: `/.*\.test\.js/` (surrounded by slashes)
3. **Extensions**: `.js`, `.py`, `.json`
4. **Exact matches**: `package.json`, `Dockerfile`

### Global Settings

```json
{
  "global_settings": {
    "create_directories": true,
    "notify_on_redirect": true,
    "backup_original": false,
    "case_sensitive": true,
    "max_redirect_depth": 5
  }
}
```

### Security Settings

```json
{
  "security": {
    "blocked_destinations": [
      "/etc",
      "/usr",
      "/bin",
      "/~/.ssh"
    ],
    "allowed_extensions": ["*"],
    "max_file_size_mb": 100
  }
}
```

## Usage Examples

### Markdown Organization
Automatically redirect markdown files from project root to documentation folders:

```json
{
  "name": "docs",
  "pattern": "*.md",
  "source_location": "root_only",
  "destination": "docs/articles",
  "exclude": ["README.md"]
}
```

### Script Organization
Redirect all Ruby scripts to a scripts directory:

```json
{
  "name": "scripts",
  "pattern": "*.rb",
  "source_location": "root_only",
  "destination": "scripts"
}
```

### Test File Organization
Redirect test files anywhere in the project to test directories:

```json
{
  "name": "tests",
  "pattern": "test_*.rb",
  "source_location": "anywhere",
  "destination": "tests/unit"
}
```

## Commands

The plugin provides these slash commands:

- `/redirect:config` - View current configuration
- `/redirect:validate` - Validate configuration and test patterns

## Safety Features

- **Path traversal protection**: Prevents redirection to system directories
- **Loop detection**: Stops infinite redirection chains
- **Configuration validation**: Ensures rules are properly formatted
- **Blocked destinations**: List of protected system paths
- **File size limits**: Prevents redirection of extremely large files

## Plugin Management

```bash
# Disable temporarily
/plugin disable fs-mv

# Re-enable
/plugin enable fs-mv

# Uninstall
/plugin uninstall fs-mv

# List installed plugins
/plugin list
```

## Development

### Testing

```bash
# Run tests
ruby tests/test_fs_mv.rb

# Validate configuration
ruby scripts/config_validator.rb
```

### File Structure

```
fs-mv/
├── .claude-plugin/
│   ├── plugin.json                  # Plugin manifest
│   └── config/redirect-rules.json   # Configuration file
├── hooks/
│   ├── hooks.json                  # Hook registration
│   └── fs_mv.rb                  # Main redirection logic
├── scripts/config_validator.rb     # Configuration validation
├── tests/test_fs_mv.rb            # Unit tests
└── README.md                       # This file
```

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Support

For issues and questions:
- GitHub Issues: https://github.com/kierr/fs-mv/issues
- Documentation: Check this README and inline code comments