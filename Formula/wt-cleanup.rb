class WtCleanup < Formula
  desc "Interactive fzf cleanup for Worktrunk worktrees and branches"
  homepage "https://github.com/chrisbloom7/wt-cleanup"
  url "https://github.com/chrisbloom7/wt-cleanup/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "3f1721c5c102ce6cf6330dfb89405d97e454f8c5ce00650f2a990f201f0c805f"
  license "MIT"

  depends_on "bash"
  depends_on "fzf"
  depends_on "worktrunk"
  uses_from_macos "ruby"

  def install
    # The script needs bash 4+ (macOS ships 3.2); pin the interpreter.
    inreplace "bin/wt-cleanup", "#!/usr/bin/env bash", "#!#{formula_opt_bin("bash")}/bash"
    libexec.install "bin", "libexec"
    bin.write_exec_script libexec/"bin/wt-cleanup"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/wt-cleanup --help")
    assert_match "Unknown option", shell_output("#{bin}/wt-cleanup --bogus 2>&1", 1)
  end
end
