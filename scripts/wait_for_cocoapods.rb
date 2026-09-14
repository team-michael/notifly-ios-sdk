#!/usr/bin/env ruby

require 'digest'
require 'json'
require 'open3'

module CocoaPodsCDN
  class Timeout < StandardError; end

  def self.wait_for(name, version, timeout: 600, interval: 10)
    raise ArgumentError, 'Invalid pod name' unless name&.match?(/\A[A-Za-z0-9_]+\z/)
    raise ArgumentError, 'Invalid pod version' unless version&.match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
    raise ArgumentError, 'Timeout and interval must be positive' unless timeout > 0 && interval > 0

    shard = Digest::MD5.hexdigest(name)[0, 3].chars
    index_url = "https://cdn.cocoapods.org/all_pods_versions_#{shard.join('_')}.txt"
    spec_url = "https://cdn.cocoapods.org/Specs/#{shard.join('/')}/#{name}/#{version}/#{name}.podspec.json"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      index = fetch(index_url, deadline)
      versions = index.to_s.lines.find { |line| line.start_with?("#{name}/") }.to_s.strip.split('/').drop(1)
      if versions.include?(version)
        begin
          spec = JSON.parse(fetch(spec_url, deadline) || 'null')
        rescue JSON::ParserError
          spec = nil
        end
        if spec.is_a?(Hash) && spec['name'] == name && spec['version'] == version
          puts "#{name}@#{version} is available in the CocoaPods CDN index and podspec."
          return
        end
      end

      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raise Timeout, "Timed out waiting for #{name}@#{version} on CocoaPods CDN; downstream publication was not attempted." if remaining <= 0

      warn "Waiting for #{name}@#{version} on CocoaPods CDN (#{remaining.ceil}s remaining)..."
      sleep [interval, remaining].min
    end
  end

  def self.fetch(url, deadline)
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return nil if remaining <= 0

    body, status = Open3.capture2(
      'curl', '--silent', '--show-error', '--fail', '--location', '--max-redirs', '5',
      '--connect-timeout', '5', '--max-time', [15, remaining].min.to_s,
      '--proto', '=https', '--proto-redir', '=https', url
    )
    status.success? ? body : nil
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: #{$PROGRAM_NAME} POD_NAME VERSION" unless ARGV.length == 2
  begin
    CocoaPodsCDN.wait_for(*ARGV)
  rescue ArgumentError, CocoaPodsCDN::Timeout => error
    abort error.message
  end
end
