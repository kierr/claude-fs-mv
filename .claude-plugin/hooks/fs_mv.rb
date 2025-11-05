#!/usr/bin/env ruby

require 'json'
require 'fileutils'
require 'pathname'

class FsMvHook
  MAX_LOOPS = 15
  LOOP_DETECTION_KEY = 'fs_mv_loop_detection'

  def initialize(input = nil)
    if input
      @input = input
    else
      begin
        @input = STDIN.tty? ? {} : JSON.parse(STDIN.read)
      rescue JSON::ParserError, EOFError
        @input = {}
      end
    end
    @working_dir = Dir.pwd
    @config_file = get_validated_config_file
    @config = load_config
    @loop_count = get_loop_count
  end

  def main
    return unless should_redirect?

    # Increment loop count at the start to detect actual loops
    increment_loop_count
    return if @loop_count >= MAX_LOOPS

    original_path = @input['tool_input']['file_path']

    # Check file size before redirection
    return unless validate_file_size(original_path)

    redirected_path = find_redirected_path(original_path)

    return unless redirected_path

    # Ensure target directory exists
    ensure_target_directory(redirected_path)

    # Update input with redirected path
    modified_input = @input.dup
    modified_input['tool_input']['file_path'] = redirected_path

    # Include notification if enabled (integrated into main JSON)
    if @config.dig('global_settings', 'notify_on_redirect')
      modified_input['suppressOutput'] = true
      modified_input['systemMessage'] = "File redirected: #{original_path} → #{redirected_path}"
      modified_input['hookSpecificOutput'] = {
        'hookEventName' => 'PreToolUse',
        'additionalContext' => "File automatically redirected by fs-mv plugin",
        'permissionDecision' => 'allow',
        'permissionDecisionReason' => "File pattern matched redirection rule"
      }
    end

    # Pass along the loop detection environment variable
    modified_input['environment'] ||= {}
    modified_input['environment'][LOOP_DETECTION_KEY] = @loop_count.to_s

    # Output modified input
    puts JSON.generate(modified_input)
    exit 0
  end

  private

  def should_redirect?
    tool_name = @input['tool_name']
    file_path = @input['tool_input']&.[]('file_path')

    return false unless tool_name == 'Write'
    return false unless file_path
    return false if @loop_count >= MAX_LOOPS
    return false unless @config && @config['rules']

    true
  end

  def find_redirected_path(original_path)
    absolute_path = File.expand_path(original_path, @working_dir)

    @config['rules'].each do |rule|
      next unless rule['enabled']
      next unless matches_rule?(rule, absolute_path, original_path)

      redirected_path = apply_rule(rule, absolute_path, original_path)
      return redirected_path if redirected_path && safe_destination?(redirected_path)
    end

    nil
  end

  def matches_rule?(rule, absolute_path, original_path)
    pattern = rule['pattern']
    source_location = rule['source_location'] || 'anywhere'

    # Check file pattern
    return false unless matches_pattern?(pattern, File.basename(absolute_path))

    # Check exclusions
    exclude_list = rule['exclude'] || []
    return false if exclude_list.include?(File.basename(absolute_path))

    # Check source location
    case source_location
    when 'root_only'
      File.dirname(absolute_path) == @working_dir
    when 'anywhere'
      true
    else
      true # Default to anywhere
    end
  end

  def matches_pattern?(pattern, filename)
    case pattern
    when /\*/
      # Glob pattern
      File.fnmatch(pattern, filename, File::FNM_EXTGLOB)
    when /^\/.*\/$/
      # Regex pattern (remove surrounding slashes)
      regex = Regexp.new(pattern[1..-2])
      regex.match?(filename)
    else
      # Simple extension or exact match
      if pattern.start_with?('.')
        filename.end_with?(pattern)
      else
        filename == pattern
      end
    end
  end

  def apply_rule(rule, absolute_path, original_path)
    destination = rule['destination']
    filename = File.basename(absolute_path)

    # Construct redirected path
    if destination.start_with?('/')
      # Absolute destination
      redirected_path = File.join(destination, filename)
    else
      # Relative destination from working directory
      redirected_path = File.join(@working_dir, destination, filename)
    end

    redirected_path
  end

  def safe_destination?(path)
    absolute_path = File.expand_path(path)
    blocked = @config.dig('security', 'blocked_destinations') || []

    # Check for path traversal attempts using cleanpath
    normalized = Pathname.new(absolute_path).cleanpath.to_s

    # Additional check: ensure the normalized path doesn't contain dangerous patterns
    # This catches obvious traversal attempts early
    return false if path.include?('../') || path.include?('..\\')

    # Check if normalized path tries to escape working directory
    # This is a critical security check
    return false unless normalized.start_with?(@working_dir) || normalized.start_with?(File.expand_path('~'))

    # Now check against blocked destinations
    blocked.each do |blocked_path|
      blocked_abs = File.expand_path(blocked_path)
      return false if normalized.start_with?(blocked_abs)
    end

    # Additional check for home directory blocked paths
    if normalized.start_with?(File.expand_path('~')) && blocked_path_in_home?(normalized)
      return false
    end

    true
  end

  def blocked_path_in_home?(normalized_path)
    blocked = @config.dig('security', 'blocked_destinations') || []
    home_dir = File.expand_path('~')

    blocked.any? do |blocked_path|
      # Expand blocked path and check if it's a home directory pattern
      blocked_abs = File.expand_path(blocked_path)
      if blocked_abs.start_with?(home_dir)
        # This is a home directory blocked path (like ~/.ssh)
        normalized_path.start_with?(blocked_abs)
      else
        false
      end
    end
  end

  def validate_file_size(file_path)
    max_size_mb = @config.dig('security', 'max_file_size_mb')
    return true if max_size_mb.nil?  # No size limit configured

    # For new files, we can't check size yet, so we allow them
    # This is a limitation since we're in a pre-hook
    absolute_path = File.expand_path(file_path, @working_dir)
    return true unless File.exist?(absolute_path)

    begin
      file_size = File.size(absolute_path)
      max_size_bytes = max_size_mb * 1024 * 1024

      if file_size > max_size_bytes
        warn "File size (#{file_size} bytes) exceeds maximum allowed size (#{max_size_bytes} bytes)"
        return false
      end

      true
    rescue => e
      warn "Error checking file size: #{e.message}"
      # If we can't check size, allow the operation for safety
      true
    end
  end

  def ensure_target_directory(target_path)
    target_dir = File.dirname(target_path)
    return unless @config.dig('global_settings', 'create_directories')

    FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
  rescue => e
    warn "Failed to create directory #{target_dir}: #{e.message}"
  end

  def notify_redirection(original, redirected)
    # Note: Notification is integrated into the main output JSON
    # to avoid multiple JSON objects which would break Claude Code hook parsing
  end

  def get_validated_config_file
    plugin_root = ENV['CLAUDE_PLUGIN_ROOT']

    if plugin_root.nil? || plugin_root.empty?
      warn "Warning: CLAUDE_PLUGIN_ROOT not set, using default config path"
      return File.join(File.expand_path('..', __dir__), 'config', 'redirect-rules.json')
    end

    # Validate the plugin root path
    expanded_root = File.expand_path(plugin_root)

    # Check for path traversal attempts in plugin root
    unless expanded_root.start_with?('/Users') || expanded_root.start_with?(File.expand_path('~'))
      warn "Warning: CLAUDE_PLUGIN_ROOT appears to be outside user directories: #{expanded_root}"
      return File.join(File.expand_path('..', __dir__), 'config', 'redirect-rules.json')
    end

    # Ensure the path exists and is accessible
    unless Dir.exist?(expanded_root)
      warn "Warning: CLAUDE_PLUGIN_ROOT directory does not exist: #{expanded_root}"
      return File.join(File.expand_path('..', __dir__), 'config', 'redirect-rules.json')
    end

    # Construct and return the validated config file path
    File.join(expanded_root, 'config', 'redirect-rules.json')
  end

  def load_config
    return nil unless File.exist?(@config_file)

    begin
      JSON.parse(File.read(@config_file))
    rescue JSON::ParserError => e
      warn "Invalid JSON in config file #{@config_file}: #{e.message}"
      nil
    end
  end

  def get_loop_count
    # Simple loop detection using environment variable
    ENV.fetch(LOOP_DETECTION_KEY, '0').to_i
  end

  def increment_loop_count
    @loop_count += 1
    ENV[LOOP_DETECTION_KEY] = @loop_count.to_s
  end
end

# Main execution
if __FILE__ == $0
  begin
    FsMvHook.new.main
  rescue => e
    warn "File redirect error: #{e.message}"
    warn e.backtrace.join("\n") if ENV['DEBUG']
    exit 0  # Allow original operation to proceed
  end
end