class Towit < Formula
  desc "Searchable archive of your Claude Code conversations"
  homepage "https://github.com/chrisbloom7/to-wit"
  url "https://github.com/chrisbloom7/to-wit/archive/refs/tags/v0.10.0.tar.gz"
  sha256 "3e9aa23a56edda8ac7783b15e7e768562dd2ef7e49715f7b651d35321748daac"
  license "GPL-3.0-only"

  depends_on "python@3.15"

  def install
    libexec.install "bin", "libexec"
    (bin/"towit").write_env_script libexec/"bin/towit",
                                   TOWIT_PYTHON: formula_opt_bin("python@3.15")/"python3.15"
  end

  def caveats
    <<~EOS
      Set up the database and the Claude Code hooks with:
        towit setup --hook

      Claude Code is optional: without it, To Wit archives and searches
      conversations but cannot generate titles, summaries, or topics. Install it with:
        brew install --cask claude-code
    EOS
  end

  test do
    ENV["HOME"] = testpath
    assert_match "To Wit", shell_output("#{bin}/towit help")
    system bin/"towit", "setup"
    assert_match "SQLite FTS5 is available", shell_output("#{bin}/towit doctor 2>&1; true")
    assert_match "Total conversations", shell_output("#{bin}/towit stats")
  end
end
