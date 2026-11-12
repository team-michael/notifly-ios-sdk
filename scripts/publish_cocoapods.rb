#!/usr/bin/env ruby

require 'json'
require 'open3'
require 'tempfile'

module CocoaPodsPublisher
  class Error < StandardError; end
  RETRY_DELAYS = [30, 60, 120].freeze

  def self.publish(name, version)
    raise Error, 'Invalid pod name or version' unless name&.match?(/\A[A-Za-z0-9_]+\z/) &&
      version&.match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)

    podspec = "#{name}.podspec"
    local = local_spec(podspec)
    raise Error, "#{podspec} does not describe #{name}@#{version}" unless local['name'] == name && local['version'] == version

    (RETRY_DELAYS.length + 1).times do |attempt|
      # A previous timed-out request may finish during the backoff.
      if published?(name, version, local)
        puts "#{name}@#{version} is already published and matches; skipping."
        return
      end

      output, success = push(podspec)
      return if success

      output = output.gsub(/\e\[[0-9;]*m/, '')
      transient = transient_error?(output)
      duplicate = output.match?(/^\[!\] Unable to accept duplicate entry for:/)
      failure = "Publication failed for #{name}@#{version}; see pod output above."
      raise Error, failure unless transient || duplicate

      # Reconcile even on the final attempt: a failed response is not proof of a failed registration.
      if published?(name, version, local)
        puts "#{name}@#{version} was registered despite the push error and matches; continuing."
        return
      end
      # A duplicate response only permits reconciliation, never another upload.
      raise Error, failure unless transient

      delay = RETRY_DELAYS[attempt]
      raise Error, "Publication retries exhausted for #{name}@#{version}; see pod output above." unless delay

      warn "#{name}@#{version} is not registered yet; rechecking in #{delay}s before retry #{attempt + 1}/#{RETRY_DELAYS.length}."
      sleep delay
    end
  end

  def self.local_spec(podspec)
    body, status = Open3.capture2('pod', 'ipc', 'spec', podspec)
    raise Error, "Could not read #{podspec}" unless status.success?

    parse_spec(body)
  end

  def self.published?(name, version, local)
    remote = fetch_spec(name, version)
    return false if remote.nil?

    # Trunk adds publishing-tool metadata; every actual spec field must match.
    unless local.reject { |key, _| key == 'pushed_with_swift_version' } ==
           remote.reject { |key, _| key == 'pushed_with_swift_version' }
      raise Error, "Published #{name}@#{version} differs from this release."
    end
    true
  end

  def self.fetch_spec(name, version)
    Tempfile.create('notifly-published-spec') do |file|
      code, status = Open3.capture2(
        'curl', '--silent', '--show-error', '--location', '--retry', '3', '--retry-max-time', '120',
        '--connect-timeout', '5', '--max-time', '30', '--proto', '=https', '--proto-redir', '=https',
        '--output', file.path, '--write-out', '%{http_code}',
        "https://trunk.cocoapods.org/api/v1/pods/#{name}/specs/#{version}"
      )
      raise Error, "Could not check #{name}@#{version} (curl failed)." unless status.success?

      case code
      when '200' then parse_spec(file.read)
      when '404' then nil
      else raise Error, "Could not check #{name}@#{version} (HTTP #{code})."
      end
    end
  end

  def self.parse_spec(body)
    spec = JSON.parse(body)
    raise Error, 'Invalid podspec response' unless spec.is_a?(Hash)

    spec
  rescue JSON::ParserError
    raise Error, 'Invalid podspec JSON'
  end

  def self.push(podspec)
    output = +''
    status = nil
    Open3.popen2e('pod', 'trunk', 'push', '--allow-warnings', podspec) do |input, stream, process|
      input.close
      stream.each_line do |line|
        $stdout.print(line)
        $stdout.flush
        output << line
      end
      status = process.value
    end
    [output, status.success?]
  end

  def self.transient_error?(output)
    # Match Trunk's known transient errors, not arbitrary build/validation output.
    output.match?(/^\[!\] (?:Calling the GitHub commit API timed out\.|An internal server error occurred\.|An error occurred on GitHub['’]s side\.)/)
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} POD_NAME VERSION" unless ARGV.length == 2
  begin
    CocoaPodsPublisher.publish(*ARGV)
  rescue CocoaPodsPublisher::Error => error
    abort error.message
  end
end
