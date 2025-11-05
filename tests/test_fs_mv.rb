#!/usr/bin/env ruby

require 'test/unit'
require 'json'
require 'tempfile'
require 'fileutils'

# Add the plugin root to the load path
PLUGIN_ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(PLUGIN_ROOT, '.claude-plugin', 'hooks'))

require 'fs_mv'

class TestFsMv < Test::Unit::TestCase
  def setup
    @temp_dir = Dir.mktmpdir
    @config_file = File.join(@temp_dir, 'config.json')
    @working_dir = File.join(@temp_dir, 'project')
    Dir.mkdir(@working_dir)

    # Create test config
    @test_config = {
      "version" => "1.0",
      "rules" => [
        {
          "name" => "test-markdown",
          "pattern" => "*.md",
          "source_location" => "root_only",
          "destination" => "docs",
          "exclude" => ["README.md"],
          "enabled" => true
        },
        {
          "name" => "test-ruby",
          "pattern" => "*.rb",
          "source_location" => "root_only",
          "destination" => "scripts",
          "enabled" => true
        }
      ],
      "global_settings" => {
        "create_directories" => true,
        "notify_on_redirect" => false
      },
      "security" => {
        "blocked_destinations" => ["/etc", "/usr"],
        "max_file_size_mb" => 100
      }
    }

    File.write(@config_file, JSON.generate(@test_config))
    ENV['CLAUDE_PLUGIN_ROOT'] = PLUGIN_ROOT
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
    ENV.delete('CLAUDE_PLUGIN_ROOT')
  end

  def test_creates_repository_structure
    # Test that required directories exist
    assert Dir.exist?(File.join(PLUGIN_ROOT, '.claude-plugin'))
    assert Dir.exist?(File.join(PLUGIN_ROOT, '.claude-plugin', 'config'))
    assert Dir.exist?(File.join(PLUGIN_ROOT, '.claude-plugin', 'hooks'))
    assert Dir.exist?(File.join(PLUGIN_ROOT, 'scripts'))
    assert Dir.exist?(File.join(PLUGIN_ROOT, 'tests'))
  end

  def test_plugin_manifest_exists
    plugin_json = File.join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json')
    assert File.exist?(plugin_json)

    manifest = JSON.parse(File.read(plugin_json))
    assert_equal 'fs-mv', manifest['name']
    assert manifest['description']
    assert manifest['version']
    assert manifest['hooks']
  end

  def test_configuration_file_exists
    config_file = File.join(PLUGIN_ROOT, '.claude-plugin', 'config', 'redirect-rules.json')
    assert File.exist?(config_file)

    config = JSON.parse(File.read(config_file))
    assert config['rules']
    assert config['global_settings']
    assert config['security']
  end

  def test_hook_file_exists_and_executable
    hook_file = File.join(PLUGIN_ROOT, '.claude-plugin', 'hooks', 'fs_mv.rb')
    assert File.exist?(hook_file)
    assert File.executable?(hook_file)
  end

  def test_matches_pattern_with_glob
    hook = FsMvHook.new

    # Test glob patterns
    assert hook.send(:matches_pattern?, '*.md', 'test.md')
    assert hook.send(:matches_pattern?, '*.md', 'README.md')
    assert hook.send(:matches_pattern?, 'test_*.rb', 'test_helper.rb')
    refute hook.send(:matches_pattern?, '*.md', 'test.txt')
  end

  def test_matches_pattern_with_extension
    hook = FsMvHook.new

    # Test extension patterns
    assert hook.send(:matches_pattern?, '.md', 'test.md')
    assert hook.send(:matches_pattern?, '.rb', 'script.rb')
    refute hook.send(:matches_pattern?, '.js', 'test.rb')
  end

  def test_matches_pattern_with_exact_match
    hook = FsMvHook.new

    # Test exact matches
    assert hook.send(:matches_pattern?, 'package.json', 'package.json')
    refute hook.send(:matches_pattern?, 'package.json', 'requirements.txt')
  end

  def test_matches_rule_with_root_only
    hook = FsMvHook.new

    # Test root_only source location
    root_file = File.join(@working_dir, 'test.md')
    sub_file = File.join(@working_dir, 'subdir', 'test.md')

    rule = {
      'pattern' => '*.md',
      'source_location' => 'root_only',
      'enabled' => true
    }

    # Mock config for the test
    hook.instance_variable_set(:@config, @test_config)
    # Set working directory for the test
    hook.instance_variable_set(:@working_dir, @working_dir)

    assert hook.send(:matches_rule?, rule, root_file, 'test.md')
    refute hook.send(:matches_rule?, rule, sub_file, 'test.md')
  end

  def test_matches_rule_with_anywhere
    hook = FsMvHook.new
    Dir.chdir(@working_dir) do
      # Test anywhere source location
      root_file = File.join(@working_dir, 'test.md')
      sub_file = File.join(@working_dir, 'subdir', 'test.md')

      rule = {
        'pattern' => '*.md',
        'source_location' => 'anywhere',
        'enabled' => true
      }

      # Mock config for the test
      hook.instance_variable_set(:@config, @test_config)

      assert hook.send(:matches_rule?, rule, root_file, 'test.md')
      assert hook.send(:matches_rule?, rule, sub_file, 'test.md')
    end
  end

  def test_exclusion_list
    hook = FsMvHook.new
    Dir.chdir(@working_dir) do
      file = File.join(@working_dir, 'README.md')

      rule = {
        'pattern' => '*.md',
        'source_location' => 'root_only',
        'exclude' => ['README.md'],
        'enabled' => true
      }

      # Mock config for the test
      hook.instance_variable_set(:@config, @test_config)

      refute hook.send(:matches_rule?, rule, file, 'README.md')
    end
  end

  def test_safe_destination_check
    hook = FsMvHook.new

    # Mock config with blocked destinations
    hook.instance_variable_set(:@config, {
      'security' => {
        'blocked_destinations' => ['/etc', '/usr']
      }
    })

    # Set working directory for the test
    hook.instance_variable_set(:@working_dir, @working_dir)

    assert hook.send(:safe_destination?, File.join(@working_dir, 'docs', 'test.md'))
    refute hook.send(:safe_destination?, '/etc/passwd')
    refute hook.send(:safe_destination?, '/usr/bin/script')
  end

  def test_path_traversal_protection
    hook = FsMvHook.new

    # Mock config with blocked destinations including SSH
    hook.instance_variable_set(:@config, {
      'security' => {
        'blocked_destinations' => ['/etc', '/usr', '/bin', '/sbin', '~/.ssh']
      }
    })

    # Set working directory for the test
    hook.instance_variable_set(:@working_dir, @working_dir)

    # Test path traversal attempts
    dangerous_paths = [
      '../../../etc/passwd',
      '/etc/shadow',
      File.expand_path('~/.ssh/id_rsa')
    ]

    dangerous_paths.each do |path|
      refute hook.send(:safe_destination?, path), "Should reject dangerous path: #{path}"
    end
  end

  def test_ensure_target_directory
    hook = FsMvHook.new
    target_dir = File.join(@working_dir, 'docs', 'articles')
    target_file = File.join(target_dir, 'test.md')

    # Mock config to enable directory creation
    hook.instance_variable_set(:@config, {
      'global_settings' => {
        'create_directories' => true
      }
    })

    # Set working directory for the test
    hook.instance_variable_set(:@working_dir, @working_dir)

    refute Dir.exist?(target_dir)
    hook.send(:ensure_target_directory, target_file)
    assert Dir.exist?(target_dir)
  end

  def test_apply_rule_relative_destination
    hook = FsMvHook.new
    Dir.chdir(@working_dir) do
      rule = {
        'destination' => 'docs'
      }

      # Set working directory for the test
      hook.instance_variable_set(:@working_dir, @working_dir)

      original_path = File.join(@working_dir, 'test.md')
      result = hook.send(:apply_rule, rule, original_path, 'test.md')

      expected = File.join(@working_dir, 'docs', 'test.md')
      assert_equal expected, result
    end
  end

  def test_apply_rule_absolute_destination
    hook = FsMvHook.new
    Dir.chdir(@working_dir) do
      absolute_dest = '/tmp/test-docs'
      rule = {
        'destination' => absolute_dest
      }

      # Set working directory for the test
      hook.instance_variable_set(:@working_dir, @working_dir)

      original_path = File.join(@working_dir, 'test.md')
      result = hook.send(:apply_rule, rule, original_path, 'test.md')

      expected = File.join(absolute_dest, 'test.md')
      assert_equal expected, result
    end
  end

  def test_configuration_validation
    # Test the configuration validator script
    validator_script = File.join(PLUGIN_ROOT, 'scripts', 'config_validator.rb')

    # Should exit with 0 for valid config
    system("ruby #{validator_script} #{@config_file}")
    assert $?.success?, "Config validator should pass for valid config"

    # Test invalid config
    invalid_config = File.join(@temp_dir, 'invalid.json')
    File.write(invalid_config, '{"invalid": json}')

    system("ruby #{validator_script} #{invalid_config}")
    refute $?.success?, "Config validator should fail for invalid JSON"
  end

  def test_disabled_rules
    hook = FsMvHook.new
    Dir.chdir(@working_dir) do
      file = File.join(@working_dir, 'test.md')

      disabled_rule = {
        'pattern' => '*.md',
        'source_location' => 'root_only',
        'enabled' => false
      }

      # Mock config for the test
      hook.instance_variable_set(:@config, @test_config)

      refute hook.send(:matches_rule?, disabled_rule, file, 'test.md')
    end
  end
end