class CcHarness < Formula
  desc "Multi-session Claude Code launcher backed by tmux"
  homepage "https://github.com/alejandro-soto-franco/cc-harness"
  url "https://github.com/alejandro-soto-franco/cc-harness/releases/download/v0.1.1/cc-harness-0.1.1.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"

  depends_on "pandoc" => :build
  depends_on "tmux"
  depends_on "fzf" => :recommended

  def install
    system "make", "completions"
    system "make", "man"
    system "make", "install", "PREFIX=#{prefix}"

    bash_completion.install "completions/cc-harness.bash" => "cc-harness"
    zsh_completion.install  "completions/cc-harness.zsh"  => "_cc-harness"
    fish_completion.install "completions/cc-harness.fish"
    man1.install            "man/cc-harness.1"
  end

  test do
    assert_match "cc-harness", shell_output("#{bin}/cc-harness --version")
    output = shell_output("#{bin}/cc-harness doctor 2>&1", 0)
    assert_match "tmux installed", output
  end
end
