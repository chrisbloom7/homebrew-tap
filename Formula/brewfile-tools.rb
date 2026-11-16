class BrewfileTools < Formula
  desc "Add, remove and audit entries in Homebrew Brewfiles"
  homepage "https://github.com/chrisbloom7/brewfile-tools"
  url "https://github.com/chrisbloom7/brewfile-tools/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "403136c49a733341d8631e3835ad8556ac5601bf980011cacb5f703cda912400"
  license "MIT"

  depends_on "bash"
  depends_on "fzf"
  depends_on "ruby"

  def install
    # The scripts need bash 4+ (macOS ships 3.2); pin the interpreter.
    inreplace %w[bin/brewfile libexec/brewfile/add libexec/brewfile/remove libexec/brewfile/audit],
              "#!/usr/bin/env bash", "#!#{formula_opt_bin("bash")}/bash"
    libexec.install "bin", "libexec"
    # The helpers need Ruby 2.7+ (macOS ships 2.6), and a shell that re-activates a version
    # manager at start-up can put another ruby first on PATH, so name Homebrew's Ruby directly.
    (bin/"brewfile").write_env_script libexec/"bin/brewfile",
                                      BREWFILE_RUBY: formula_opt_bin("ruby")/"ruby"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/brewfile --help")
    %w[add remove audit].each do |command|
      assert_match "brewfile #{command} [options]", shell_output("#{bin}/brewfile help #{command}")
    end
    assert_match "Unknown command", shell_output("#{bin}/brewfile frobnicate 2>&1", 1)
    assert_match "BREWFILE_RUBY", (bin/"brewfile").read
    # Each subcommand checks that Homebrew's Ruby is 2.7+ before it parses options.
    assert_match "Unknown option", shell_output("#{bin}/brewfile remove --bogus 2>&1", 1)
  end
end
