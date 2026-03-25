class AntiApi < Formula
  desc "Local OpenAI/Anthropic-compatible proxy for Antigravity, Codex, Copilot, and Zed"
  homepage "https://github.com/ink1ing/anti-api"
  url "https://github.com/ink1ing/anti-api/archive/refs/tags/v2.8.0.tar.gz"
  sha256 "61ee7bbc27a9610e78021a2a570cb7b28ad9398a8e9a182ca8beeaceb7e33008"
  license "MIT"
  head "https://github.com/ink1ing/anti-api.git", branch: "main"

  depends_on "bun"
  depends_on "rust" => :build

  def install
    entries = Dir["*"] - %w[anti-api-test-bundle anti-api-v2.6.0 dist]
    libexec.install entries

    cd libexec do
      inreplace "start.command", "do_update() {\n", <<~SH
        do_update() {
            if [ "${ANTI_API_NO_SELF_UPDATE:-0}" = "1" ] || [ "${ANTI_API_PACKAGE_MANAGER:-}" = "homebrew" ]; then
                if [ "${ANTI_API_PACKAGE_MANAGER:-}" = "homebrew" ]; then
                    echo "This installation is managed by Homebrew. Run: brew upgrade anti-api"
                else
                    echo "Self-update is disabled for this installation."
                fi
                return 0
            fi

      SH
      chmod 0755, "start.command"
      chmod 0755, "a"
      system Formula["bun"].opt_bin/"bun", "install", "--frozen-lockfile"
      system "cargo", "build", "--release", "--manifest-path", "rust-proxy/Cargo.toml"
    end

    (bin/"anti-api").write <<~SH
      #!/bin/bash
      export ANTI_API_PACKAGE_MANAGER=homebrew
      export ANTI_API_NO_SELF_UPDATE=1
      exec "#{libexec}/start.command" "$@"
    SH
    chmod 0755, bin/"anti-api"

    (bin/"a").write <<~SH
      #!/bin/bash
      exec "#{bin}/anti-api" "$@"
    SH
    chmod 0755, bin/"a"
  end

  def caveats
    <<~EOS
      Start Anti-API with:
        anti-api

      This Homebrew package disables in-app self-update.
      Use Homebrew to update this install.
      If you use a private tap or a local formula file, update that formula first,
      then run brew upgrade or brew reinstall.
    EOS
  end

  test do
    output = shell_output("#{bin}/anti-api --update-only 2>&1")
    assert_match "managed by Homebrew", output
  end
end
