#!/usr/bin/env ruby

require 'minitest/autorun'
require 'yaml'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative 'wait_for_cocoapods'
require_relative 'publish_cocoapods'

class CocoaPodsReleaseTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  # Removing the CDN guard, or moving it after Full publication, must fail.
  def test_full_publication_waits_for_core_index_and_spec
    run_release
  end

  def test_continues_after_trunk_registers_the_spec_but_returns_an_error
    run_release(fail_after_registration: true)
  end

  def test_stops_downstream_publication_after_a_permanent_push_error
    run_release(reject_push: true)
  end

  private

  def run_release(fail_after_registration: false, reject_push: false)
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
        when %r{\Ahttps://trunk.cocoapods.org/api/v1/pods/(notifly_core|notifly_sdk|notifly_sdk_push_extension)/specs/2.8.0-alpha.1\z}
          name = url.split('/')[-3]
          registered = File.exist?(File.join(state, name))
          registered ||= name == 'notifly_core' && ENV['RELEASE_TEST_FAIL_AFTER_REGISTRATION'] != 'true'
          spec = { name: name, version: '2.8.0-alpha.1', pushed_with_swift_version: '6.0' }
          File.write(ARGV[ARGV.index('--output') + 1], JSON.generate(registered ? spec : {}))
          print registered ? '200' : '404'
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
        if ARGV[0, 2] == ['ipc', 'spec']
          puts JSON.generate(name: File.basename(ARGV.last, '.podspec'), version: '2.8.0-alpha.1')
        elsif ARGV[0, 2] == ['trunk', 'push']
          puts "ATTEMPT #{ARGV.last}"
          abort '[!] Authentication token is invalid.' if ENV['RELEASE_TEST_REJECT_PUSH'] == 'true'
          if ARGV.last == 'notifly_sdk.podspec'
            abort 'Full publication attempted before Core CDN readiness' unless File.exist?(File.join(ENV.fetch('RELEASE_TEST_STATE'), 'core-ready'))
          end
          puts "PUBLISHED #{ARGV.last}"
          if ENV['RELEASE_TEST_FAIL_AFTER_REGISTRATION'] == 'true'
            marker = File.join(ENV.fetch('RELEASE_TEST_STATE'), File.basename(ARGV.last, '.podspec'))
            abort 'Duplicate push after registration' if File.exist?(marker)
            File.write(marker, '')
            if ARGV.last == 'notifly_sdk_push_extension.podspec'
              abort '[!] An internal server error occurred. Please try again later.'
            end
            abort '[!] Calling the GitHub commit API timed out. Please try again later.'
          end
        else
          abort "Unexpected pod command: #{ARGV.inspect}"
        end
      RUBY
      output, status = Open3.capture2e(
        { 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'VERSION' => '2.8.0-alpha.1', 'RELEASE_TEST_STATE' => dir,
          'RELEASE_TEST_FAIL_AFTER_REGISTRATION' => fail_after_registration.to_s,
          'RELEASE_TEST_REJECT_PUSH' => reject_push.to_s },
        'bash', '-e', '-c', step, chdir: ROOT
      )
      if reject_push
        refute status.success?, output
        assert_includes output, 'Authentication token is invalid.'
        refute_includes output, 'ATTEMPT notifly_sdk_push_extension.podspec'
      else
        assert status.success?, output
        assert_includes output, 'PUBLISHED notifly_sdk.podspec'
        assert_includes output, 'PUBLISHED notifly_sdk_push_extension.podspec'
      end
    end
  end

  def write_command(dir, name, body)
    path = File.join(dir, name)
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0700, path)
  end
end

class CocoaPodsPublisherTest < Minitest::Test
  SPEC = { 'name' => 'notifly_sdk', 'version' => '2.8.2', 'dependencies' => { 'notifly_core' => ['= 2.8.2'] } }.freeze
  TIMEOUT = '[!] Calling the GitHub commit API timed out. Please try again later.'.freeze

  def test_waits_and_rechecks_before_retrying_a_push
    run_publication(lookups: [nil, nil, SPEC], pushes: [[TIMEOUT, false]], waits: [30])
  end

  def test_retries_a_transient_failure_when_still_unpublished
    run_publication(lookups: [nil, nil, nil], pushes: [[TIMEOUT, false], ['', true]], waits: [30])
  end

  def test_recovers_each_known_trunk_error_without_a_duplicate_push
    [TIMEOUT, '[!] An internal server error occurred.', '[!] An error occurred on GitHub’s side.',
     "\e[31m#{TIMEOUT}\e[0m"].each do |message|
      run_publication(lookups: [nil, SPEC], pushes: [[message, false]])
    end
  end

  def test_stops_after_three_retries
    run_publication(lookups: [nil] * 8, pushes: [[TIMEOUT, false]] * 4,
                    waits: [30, 60, 120], error: /failed|exhausted/i)
  end

  def test_reconciles_registration_even_after_the_last_push_fails
    run_publication(lookups: [nil] * 7 + [SPEC], pushes: [[TIMEOUT, false]] * 4, waits: [30, 60, 120])
  end

  def test_reconciles_a_duplicate_when_the_previous_push_finishes_during_retry
    duplicate = '[!] Unable to accept duplicate entry for: notifly_sdk (2.8.2)'
    run_publication(lookups: [nil, nil, nil, SPEC], pushes: [[TIMEOUT, false], [duplicate, false]], waits: [30])
  end

  def test_duplicate_response_requires_a_matching_spec_and_is_not_retried
    duplicate = '[!] Unable to accept duplicate entry for: notifly_sdk (2.8.2)'
    different = SPEC.merge('dependencies' => { 'notifly_core' => ['= 2.8.1'] })
    [[nil, /failed/i], [different, /differs/],
     [CocoaPodsPublisher::Error.new('Could not check publication'), /Could not check/]].each do |remote, error|
      run_publication(lookups: [nil, remote], pushes: [[duplicate, false]], error: error)
    end
  end

  def test_authentication_validation_and_unknown_errors_are_not_retried
    ['[!] Authentication token is invalid.', '[!] The spec did not pass validation.',
     '[!] Build timed out.', '[!] Unexpected failure.'].each do |message|
      run_publication(lookups: [nil], pushes: [[message, false]], error: /failed/i)
    end
  end

  def test_refuses_a_different_published_spec_before_or_after_push
    different = SPEC.merge('dependencies' => { 'notifly_core' => ['= 2.8.1'] })
    run_publication(lookups: [different], pushes: [], error: /differs/)
    run_publication(lookups: [nil, different], pushes: [[TIMEOUT, false]], error: /differs/)
  end

  def test_an_unavailable_lookup_never_causes_a_push
    unavailable = CocoaPodsPublisher::Error.new('Could not check publication')
    run_publication(lookups: [unavailable], pushes: [], error: /Could not check/)
    run_publication(lookups: [nil, unavailable], pushes: [[TIMEOUT, false]], error: /Could not check/)
  end

  def test_invalid_arguments_and_wrong_local_versions_never_reach_the_network
    unexpected = ->(*) { flunk 'Invalid release input reached the network' }
    CocoaPodsPublisher.stub(:fetch_spec, unexpected) do
      [[nil, '2.8.2'], ['../notifly_sdk', '2.8.2'], ['notifly_sdk', '2.8.2?x=1']].each do |name, version|
        assert_raises(CocoaPodsPublisher::Error) { CocoaPodsPublisher.publish(name, version) }
      end
      CocoaPodsPublisher.stub(:local_spec, SPEC.merge('version' => '2.8.1')) do
        assert_raises(CocoaPodsPublisher::Error) { CocoaPodsPublisher.publish('notifly_sdk', '2.8.2') }
      end
    end
  end

  def test_fetch_only_treats_a_successful_404_as_unpublished
    [[true, '401', '{}'], [true, '500', '{}'], [false, '404', '{}'],
     [true, '200', '<html>Unavailable</html>'], [true, '200', '[]']].each do |success, code, body|
      with_fetch_response(success, code, body) do
        assert_raises(CocoaPodsPublisher::Error) { CocoaPodsPublisher.fetch_spec('notifly_sdk', '2.8.2') }
      end
    end
    with_fetch_response(true, '404', '{}') do
      assert_nil CocoaPodsPublisher.fetch_spec('notifly_sdk', '2.8.2')
    end
    with_fetch_response(true, '200', JSON.generate(SPEC)) do
      assert_equal SPEC, CocoaPodsPublisher.fetch_spec('notifly_sdk', '2.8.2')
    end
  end

  private

  def run_publication(lookups:, pushes:, waits: [], error: nil)
    lookup = lambda do |name, version|
      assert_equal ['notifly_sdk', '2.8.2'], [name, version]
      refute_empty lookups, 'Unexpected registration lookup'
      result = lookups.shift
      raise result if result.is_a?(Exception)

      result
    end
    push = lambda do |podspec|
      assert_equal 'notifly_sdk.podspec', podspec
      refute_empty pushes, 'Unexpected or duplicate publication'
      pushes.shift
    end
    pause = lambda do |seconds|
      refute_empty waits, 'Unexpected retry'
      assert_equal waits.shift, seconds
    end
    capture_io do
      CocoaPodsPublisher.stub(:local_spec, SPEC) do
        CocoaPodsPublisher.stub(:fetch_spec, lookup) do
          CocoaPodsPublisher.stub(:push, push) do
            CocoaPodsPublisher.stub(:sleep, pause) do
              if error
                failure = assert_raises(CocoaPodsPublisher::Error) { CocoaPodsPublisher.publish('notifly_sdk', '2.8.2') }
                assert_match error, failure.message
              else
                CocoaPodsPublisher.publish('notifly_sdk', '2.8.2')
              end
            end
          end
        end
      end
    end
    assert_empty lookups, 'Stopped before verifying registration'
    assert_empty pushes, 'Stopped before publication completed'
    assert_empty waits, 'Did not perform the expected retries'
  end

  def with_fetch_response(success, code, body)
    capture = lambda do |*args|
      File.write(args.fetch(args.index('--output') + 1), body)
      [code, Struct.new(:success?).new(success)]
    end
    Open3.stub(:capture2, capture) { yield }
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
