#!/usr/bin/env ruby

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'digest'

class PackageKMPCoreReleaseTest < Minitest::Test
  SCRIPT = File.expand_path('package_kmp_core_release.sh', __dir__)
  LICENSE_TEXT = "MIT License\nCopyright (c) Packaging test fixture\n".freeze
  FRAMEWORK_CONTENT = 'core framework fixture'.freeze

  # Omitting LICENSE, nesting the framework, or hashing before adding LICENSE must fail.
  def test_archive_contains_license_and_framework_with_final_checksum
    with_fixture do |root|
      output_file = File.join(root, 'github-output')
      output, status = package(root, output_file)
      assert status.success?, output

      archive = File.join(root, 'build/release/NotiflyCore.xcframework.zip')
      Dir.mktmpdir('notifly-core-unpacked') do |unpacked|
        extract_output, extract_status = Open3.capture2e('ditto', '-x', '-k', archive, unpacked)
        assert extract_status.success?, extract_output
        license = File.join(unpacked, 'LICENSE')
        assert File.file?(license), 'Core archive must include LICENSE at its root'
        assert_equal LICENSE_TEXT, File.read(license)
        assert_equal FRAMEWORK_CONTENT, File.read(File.join(unpacked, 'NotiflyCore.xcframework/Info.plist'))
      end

      checksum = Digest::SHA256.file(archive).hexdigest
      expected = "archive=#{archive}\nchecksum=#{checksum}\n"
      assert_includes output, expected
      assert_equal expected, File.read(output_file)
    end
  end

  # Missing license input must stop packaging before any release outputs are emitted.
  def test_missing_license_fails_without_release_outputs
    with_fixture(include_license: false) do |root|
      output_file = File.join(root, 'github-output')
      output, status = package(root, output_file)
      refute status.success?, 'Packaging unexpectedly succeeded without LICENSE'
      assert_includes output, 'LICENSE'
      refute File.exist?(File.join(root, 'build/release/NotiflyCore.xcframework.zip'))
      refute File.exist?(output_file)
    end
  end

  private

  def with_fixture(include_license: true)
    Dir.mktmpdir('notifly-core-package-test') do |root|
      FileUtils.mkdir_p(File.join(root, 'scripts'))
      FileUtils.cp(SCRIPT, File.join(root, 'scripts/package_kmp_core_release.sh'))
      framework = File.join(root, 'build/NotiflyCore.xcframework')
      FileUtils.mkdir_p(framework)
      File.write(File.join(framework, 'Info.plist'), FRAMEWORK_CONTENT)
      File.write(File.join(root, 'LICENSE'), LICENSE_TEXT) if include_license
      yield root
    end
  end

  def package(root, output_file)
    Open3.capture2e(
      { 'GITHUB_OUTPUT' => output_file },
      'bash', File.join(root, 'scripts/package_kmp_core_release.sh'), chdir: root
    )
  end
end
