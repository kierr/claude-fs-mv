#!/usr/bin/env ruby

require 'json'
require 'fileutils'

class ConfigValidator
  REQUIRED_FIELDS = %w[name pattern destination]
  VALID_SOURCE_LOCATIONS = %w[root_only anywhere]
  MAX_RULES = 50

  def initialize(config_path = nil)
    @config_path = config_path || get_default_config_file
    @errors = []
    @warnings = []
  end

  def validate
    return validation_result unless File.exist?(@config_path)

    begin
      @config = JSON.parse(File.read(@config_path))
      validate_structure
      validate_rules
      validate_global_settings
      validate_security_settings
    rescue JSON::ParserError => e
      @errors << "Invalid JSON: #{e.message}"
    end

    validation_result
  end

  private

  def get_default_config_file
    plugin_root = ENV['CLAUDE_PLUGIN_ROOT']

    if plugin_root.nil? || plugin_root.empty?
      return File.join(File.expand_path('..', __dir__), '.claude-plugin', 'config', 'redirect-rules.json')
    end

    # Validate the plugin root path
    expanded_root = File.expand_path(plugin_root)

    # Check for path traversal attempts in plugin root
    unless expanded_root.start_with?('/Users') || expanded_root.start_with?(File.expand_path('~'))
      warn "Warning: CLAUDE_PLUGIN_ROOT appears to be outside user directories: #{expanded_root}"
      return File.join(File.expand_path('..', __dir__), '.claude-plugin', 'config', 'redirect-rules.json')
    end

    # Ensure the path exists and is accessible
    unless Dir.exist?(expanded_root)
      warn "Warning: CLAUDE_PLUGIN_ROOT directory does not exist: #{expanded_root}"
      return File.join(File.expand_path('..', __dir__), '.claude-plugin', 'config', 'redirect-rules.json')
    end

    # Construct and return the validated config file path
    File.join(expanded_root, 'config', 'redirect-rules.json')
  end

  def validate_structure
    unless @config.is_a?(Hash)
      @errors << "Root configuration must be an object"
      return
    end

    unless @config.key?('rules')
      @errors << "Missing required 'rules' section"
      return
    end

    unless @config['rules'].is_a?(Array)
      @errors << "'rules' must be an array"
    end

    if @config['rules'].length > MAX_RULES
      @warnings << "Too many rules (#{@config['rules'].length} > #{MAX_RULES}). Consider simplifying."
    end
  end

  def validate_rules
    @config['rules'].each_with_index do |rule, index|
      validate_rule(rule, index)
    end
  end

  def validate_rule(rule, index)
    unless rule.is_a?(Hash)
      @errors << "Rule #{index}: Must be an object"
      return
    end

    # Check required fields
    REQUIRED_FIELDS.each do |field|
      unless rule.key?(field) && !rule[field].nil? && !rule[field].to_s.empty?
        @errors << "Rule #{index} (#{rule['name'] || 'unnamed'}): Missing required field '#{field}'"
      end
    end

    # Validate name
    if rule['name'] && rule['name'].to_s.empty?
      @errors << "Rule #{index}: Name cannot be empty"
    end

    # Validate pattern
    if rule['pattern']
      validate_pattern(rule['pattern'], index, rule['name'])
    end

    # Validate source_location
    if rule['source_location']
      unless VALID_SOURCE_LOCATIONS.include?(rule['source_location'])
        @errors << "Rule #{index} (#{rule['name']}): Invalid source_location '#{rule['source_location']}'. Must be one of: #{VALID_SOURCE_LOCATIONS.join(', ')}"
      end
    end

    # Validate destination
    if rule['destination']
      validate_destination(rule['destination'], index, rule['name'])
    end

    # Validate exclude list
    if rule['exclude'] && !rule['exclude'].is_a?(Array)
      @errors << "Rule #{index} (#{rule['name']}): 'exclude' must be an array"
    end

    # Validate enabled field
    if rule.key?('enabled') && ![true, false].include?(rule['enabled'])
      @errors << "Rule #{index} (#{rule['name']}): 'enabled' must be true or false"
    end
  end

  def validate_pattern(pattern, index, rule_name)
    case pattern
    when String
      if pattern.empty?
        @errors << "Rule #{index} (#{rule_name}): Pattern cannot be empty"
      elsif pattern.length > 100
        @warnings << "Rule #{index} (#{rule_name}): Pattern is very long (#{pattern.length} chars)"
      end
    else
      @errors << "Rule #{index} (#{rule_name}): Pattern must be a string"
    end
  end

  def validate_destination(destination, index, rule_name)
    unless destination.is_a?(String) && !destination.empty?
      @errors << "Rule #{index} (#{rule_name}): Destination must be a non-empty string"
      return
    end

    # Check for dangerous patterns
    dangerous_patterns = ['..', '~/', '/etc', '/usr', '/bin', '/sbin']
    dangerous_patterns.each do |dangerous|
      if destination.include?(dangerous)
        @errors << "Rule #{index} (#{rule_name}): Destination contains potentially dangerous path '#{dangerous}'"
      end
    end

    # Check length
    if destination.length > 200
      @warnings << "Rule #{index} (#{rule_name}): Destination path is very long (#{destination.length} chars)"
    end
  end

  def validate_global_settings
    return unless @config['global_settings']

    settings = @config['global_settings']

    unless settings.is_a?(Hash)
      @errors << "global_settings must be an object"
      return
    end

    # Validate boolean settings
    %w[create_directories notify_on_redirect backup_original case_sensitive].each do |setting|
      if settings.key?(setting) && ![true, false].include?(settings[setting])
        @errors << "global_settings.#{setting} must be true or false"
      end
    end

    # Validate numeric settings
    if settings.key?('max_redirect_depth')
      depth = settings['max_redirect_depth']
      unless depth.is_a?(Integer) && depth >= 1 && depth <= 20
        @errors << "global_settings.max_redirect_depth must be an integer between 1 and 20"
      end
    end
  end

  def validate_security_settings
    return unless @config['security']

    security = @config['security']

    unless security.is_a?(Hash)
      @errors << "security must be an object"
      return
    end

    # Validate blocked_destinations
    if security.key?('blocked_destinations')
      unless security['blocked_destinations'].is_a?(Array)
        @errors << "security.blocked_destinations must be an array"
      else
        security['blocked_destinations'].each_with_index do |dest, i|
          unless dest.is_a?(String) && !dest.empty?
            @errors << "security.blocked_destinations[#{i}] must be a non-empty string"
          end
        end
      end
    end

    # Validate allowed_extensions
    if security.key?('allowed_extensions')
      unless security['allowed_extensions'].is_a?(Array)
        @errors << "security.allowed_extensions must be an array"
      end
    end

    # Validate max_file_size_mb
    if security.key?('max_file_size_mb')
      size = security['max_file_size_mb']
      unless size.is_a?(Integer) && size >= 1 && size <= 1000
        @errors << "security.max_file_size_mb must be an integer between 1 and 1000"
      end
    end
  end

  def validation_result
    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings,
      config_file: @config_path,
      rules_count: @config&.dig('rules')&.length || 0
    }
  end
end

# Command line execution
if __FILE__ == $0
  config_path = ARGV[0]  # Let constructor handle nil
  validator = ConfigValidator.new(config_path)
  result = validator.validate

  puts "Configuration validation for: #{result[:config_file]}"
  puts "=" * 50

  if result[:valid]
    puts "✅ Configuration is valid"
    puts "📊 Rules loaded: #{result[:rules_count]}"
  else
    puts "❌ Configuration has errors"
  end

  if result[:errors].any?
    puts "\n🚨 Errors:"
    result[:errors].each { |error| puts "  • #{error}" }
  end

  if result[:warnings].any?
    puts "\n⚠️  Warnings:"
    result[:warnings].each { |warning| puts "  • #{warning}" }
  end

  exit(result[:valid] ? 0 : 1)
end