#!/usr/bin/env ruby

version, checksum = ARGV
abort "Usage: #{$PROGRAM_NAME} VERSION CHECKSUM" unless version && checksum
abort "Invalid release version: #{version}" unless version.match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
abort "Invalid SwiftPM checksum" unless checksum.match?(/\A[0-9a-f]{64}\z/)

root = File.expand_path("..", __dir__)
package_path = File.join(root, "Package.swift")
core_podspec_path = File.join(root, "notifly_core.podspec")

platform_podspecs = %w[notifly_sdk.podspec notifly_sdk_push_extension.podspec]
platform_podspecs.each do |filename|
  contents = File.read(File.join(root, filename))
  declared_version = contents[/s\.version\s*=\s*['\"]([^'\"]+)['\"]/, 1]
  abort "#{filename} version #{declared_version.inspect} does not match #{version}" unless declared_version == version
end

package = File.read(package_path)
package.sub!(/let releasedCoreVersion = "[^"]+"/, "let releasedCoreVersion = \"#{version}\"") or
  abort "releasedCoreVersion marker was not found"
package.sub!(/let releasedCoreChecksum = "[0-9a-f]{64}"/, "let releasedCoreChecksum = \"#{checksum}\"") or
  abort "releasedCoreChecksum marker was not found"
core_podspec = File.read(core_podspec_path)
core_podspec.sub!(/s\.version\s*=\s*'[^']+'/, "s.version          = '#{version}'") or
  abort "notifly_core.podspec version was not found"
core_podspec.sub!(/:sha256\s*=>\s*'[0-9a-f]{64}'/, ":sha256 => '#{checksum}'") or
  abort "notifly_core.podspec checksum marker was not found"

File.write(package_path, package)
File.write(core_podspec_path, core_podspec)
