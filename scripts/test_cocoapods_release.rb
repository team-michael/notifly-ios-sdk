#!/usr/bin/env ruby

require 'minitest/autorun'
require 'yaml'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative 'wait_for_cocoapods'

class CocoaPodsReleaseTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  # Removing the CDN guard, or moving it after Full publication, must fail.
  def test_full_publication_waits_for_core_index_and_spec
    workflow = YAML.load_file(File.join(ROOT, '.github/workflows/release.yml'))
    step = workflow.fetch('jobs').fetch('release').fetch('steps').find do |item|
      item['name'] == 'Release to CocoaPods'
    end.fetch('run')

    Dir.mktmpdir('notifly-cocoapods-release-test') do |dir|
      write_command(dir, 'curl', <<~'RUBY')
        require 'json'
        url = ARGV.last
        state = ENV.fetch('RELEASE_TEST_STATE')
        case url
        when 'https://trunk.cocoapods.org/api/v1/pods/notifly_core/specs/2.8.0-alpha.1'
          File.write(ARGV[ARGV.index('--output') + 1], JSON.generate(name: 'notifly_core', version: '2.8.0-alpha.1'))
          print '200'
        when %r{\Ahttps://trunk.cocoapods.org/api/v1/pods/(notifly_sdk|notifly_sdk_push_extension)/specs/2.8.0-alpha.1\z}
          File.write(ARGV[ARGV.index('--output') + 1], '{}')
          print '404'
        when 'https://cdn.cocoapods.org/all_pods_versions_6_f_2.txt'
          File.write(File.join(state, 'index-read'), '')
          puts 'notifly_core/2.8.0-alpha.1'
        when 'https://cdn.cocoapods.org/Specs/6/f/2/notifly_core/2.8.0-alpha.1/notifly_core.podspec.json'
          abort 'Spec requested before version index' unless File.exist?(File.join(state, 'index-read'))
          File.write(File.join(state, 'core-ready'), '')
          puts JSON.generate(name: 'notifly_core', version: '2.8.0-alpha.1')
        else
          abort "Unexpected network request: #{url}"
        end
      RUBY
      write_command(dir, 'pod', <<~'RUBY')
        require 'json'
        if ARGV == ['ipc', 'spec', 'notifly_core.podspec']
          puts JSON.generate(name: 'notifly_core', version: '2.8.0-alpha.1')
        elsif ARGV[0, 2] == ['trunk', 'push']
          if ARGV.last == 'notifly_sdk.podspec'
            abort 'Full publication attempted before Core CDN readiness' unless File.exist?(File.join(ENV.fetch('RELEASE_TEST_STATE'), 'core-ready'))
          end
          puts "PUBLISHED #{ARGV.last}"
        else
          abort "Unexpected pod command: #{ARGV.inspect}"
        end
      RUBY
      output, status = Open3.capture2e(
        { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'VERSION' => '2.8.0-alpha.1', 'RELEASE_TEST_STATE' => dir },
        'bash', '-e', '-c', step, chdir: ROOT
      )
      assert status.success?, output
      assert_includes output, 'PUBLISHED notifly_sdk.podspec'
      assert_includes output, 'PUBLISHED notifly_sdk_push_extension.podspec'
    end
  end

  private

  def write_command(dir, name, body)
    path = File.join(dir, name)
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0700, path)
  end
end

class CocoaPodsCDNTest < Minitest::Test
  INDEX_URL = 'https://cdn.cocoapods.org/all_pods_versions_6_f_2.txt'
  SPEC_URL = 'https://cdn.cocoapods.org/Specs/6/f/2/notifly_core/2.8.0-alpha.1/notifly_core.podspec.json'
  INDEX = "notifly_core/2.8.0-alpha.1\n"
  SPEC = '{"name":"notifly_core","version":"2.8.0-alpha.1"}'

  def test_does_not_use_spec_until_exact_version_is_in_index
    responses = [
      [INDEX_URL, nil],
      [INDEX_URL, "notifly_core/2.8.0-alpha.10\n"],
      [INDEX_URL, INDEX],
      [SPEC_URL, SPEC]
    ]
    run_responses(responses)
  end

  def test_retries_unavailable_malformed_and_wrong_spec
    responses = [nil, '<html>not ready</html>', '[]',
                 '{"name":"another_pod","version":"2.8.0-alpha.1"}',
                 '{"name":"notifly_core","version":"2.8.0-alpha.10"}', SPEC].flat_map do |spec|
      [[INDEX_URL, INDEX], [SPEC_URL, spec]]
    end
    run_responses(responses)
  end

  def test_timeout_stops_without_signalling_readiness
    output, = capture_io do
      CocoaPodsCDN.stub(:fetch, nil) do
        assert_raises(CocoaPodsCDN::Timeout) do
          CocoaPodsCDN.wait_for('notifly_core', '2.8.0-alpha.1', timeout: 0.01, interval: 0.001)
        end
      end
    end
    assert_empty output
  end

  def test_invalid_arguments_never_request_a_url
    fetch = ->(*) { flunk 'Invalid arguments caused a network request' }
    CocoaPodsCDN.stub(:fetch, fetch) do
      [['../notifly_core', '2.8.0-alpha.1'], ['notifly_core', '2.8.0-alpha.1?x=1']].each do |name, version|
        assert_raises(ArgumentError) { CocoaPodsCDN.wait_for(name, version) }
      end
      assert_raises(ArgumentError) { CocoaPodsCDN.wait_for('notifly_core', '2.8.0-alpha.1', timeout: 0) }
      assert_raises(ArgumentError) { CocoaPodsCDN.wait_for('notifly_core', '2.8.0-alpha.1', interval: 0) }
    end
  end

  private

  def run_responses(responses)
    fetch = lambda do |url, _deadline|
      expected = responses.shift
      refute_nil expected, "Unexpected request: #{url}"
      assert_equal expected[0], url
      expected[1]
    end
    capture_io do
      CocoaPodsCDN.stub(:fetch, fetch) do
        CocoaPodsCDN.wait_for('notifly_core', '2.8.0-alpha.1', timeout: 2, interval: 0.001)
      end
    end
    assert_empty responses, 'Readiness was reported before the matching podspec was available'
  end
end
