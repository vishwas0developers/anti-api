import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const repoRoot = process.cwd();
const packageJson = await Bun.file(join(repoRoot, "package.json")).json();
const versionArg = process.argv[2]?.trim();
const version = versionArg && versionArg.length > 0 ? versionArg.replace(/^v/, "") : packageJson.version;
const tag = `v${version}`;
const archiveName = `anti-api-homebrew-darwin-arm64.tar.gz`;
const archiveUrl = `https://github.com/ink1ing/anti-api/releases/download/${tag}/${archiveName}`;

const response = await fetch(archiveUrl, {
    headers: {
        "User-Agent": "anti-api-homebrew-formula",
    },
});

if (!response.ok) {
    throw new Error(`Failed to download ${archiveUrl}: ${response.status} ${response.statusText}`);
}

const buffer = Buffer.from(await response.arrayBuffer());
const sha256 = createHash("sha256").update(buffer).digest("hex");

const formula = `class AntiApi < Formula
  desc "Local OpenAI/Anthropic-compatible proxy for Antigravity, Codex, Copilot, and Zed"
  homepage "https://github.com/ink1ing/anti-api"
  url "${archiveUrl}"
  sha256 "${sha256}"
  license "MIT"
  head "https://github.com/ink1ing/anti-api.git", branch: "main"

  def install
    odie "Anti-API Homebrew packages currently support macOS Apple Silicon only." unless OS.mac? && Hardware::CPU.arm?

    libexec.install Dir["*"]

    (bin/"anti-api").write <<~SH
      #!/bin/bash
      export ANTI_API_PACKAGE_MANAGER=homebrew
      export ANTI_API_NO_SELF_UPDATE=1
      exec "#{libexec}/anti-api" "$@"
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

      This Homebrew package ships prebuilt binaries and disables in-app self-update.
      Use Homebrew to update this install:
        brew upgrade anti-api
    EOS
  end

  test do
    output = shell_output("#{bin}/anti-api --update-only 2>&1")
    assert_match "managed by Homebrew", output
  end
end
`;

await mkdir(join(repoRoot, "Formula"), { recursive: true });
await writeFile(join(repoRoot, "Formula", "anti-api.rb"), formula, "utf8");

console.log(`Updated Formula/anti-api.rb for ${tag}`);
console.log(`sha256: ${sha256}`);
