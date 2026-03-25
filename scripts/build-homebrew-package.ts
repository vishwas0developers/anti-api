import { cp, mkdir, rm } from "node:fs/promises"
import { existsSync } from "node:fs"
import { basename, join, resolve } from "node:path"

const repoRoot = process.cwd()
const packageJson = await Bun.file(join(repoRoot, "package.json")).json()
const version = (process.argv[2]?.trim() || packageJson.version).replace(/^v/, "")
const archArg = (process.argv[3]?.trim() || process.arch).toLowerCase()
const arch = archArg === "arm64" || archArg === "x64" ? archArg : process.arch

if (arch !== process.arch) {
    throw new Error(`Cross-arch Homebrew packaging is not supported on this host. Requested ${arch}, current ${process.arch}.`)
}

if (process.platform !== "darwin") {
    throw new Error("Homebrew package bundling is currently supported on macOS only.")
}

const compileTarget = arch === "arm64" ? "bun-darwin-arm64" : "bun-darwin-x64"
const bundleRoot = resolve(repoRoot, "dist", `homebrew-${arch}`)
const bundleDir = join(bundleRoot, "anti-api")
const binaryPath = join(bundleDir, "anti-api")
const proxyPath = join(repoRoot, "rust-proxy", "target", "release", "anti-proxy")
const archivePath = resolve(repoRoot, "dist", `anti-api-homebrew-darwin-${arch}.tar.gz`)

await rm(bundleRoot, { recursive: true, force: true })
await rm(archivePath, { force: true })
await mkdir(join(bundleDir, "public"), { recursive: true })

const cargo = Bun.spawn([
    "cargo",
    "build",
    "--release",
    "--manifest-path",
    "rust-proxy/Cargo.toml",
], {
    cwd: repoRoot,
    stdout: "inherit",
    stderr: "inherit",
})

const cargoExit = await cargo.exited
if (cargoExit !== 0) {
    throw new Error(`cargo build failed with exit code ${cargoExit}`)
}

const compile = Bun.spawn([
    "bun",
    "build",
    "--compile",
    "--outfile",
    binaryPath,
    "--target",
    compileTarget,
    "src/packaged-main.ts",
], {
    cwd: repoRoot,
    stdout: "inherit",
    stderr: "inherit",
})

const compileExit = await compile.exited
if (compileExit !== 0) {
    throw new Error(`bun build failed with exit code ${compileExit}`)
}

if (!existsSync(proxyPath)) {
    throw new Error(`Missing anti-proxy at ${proxyPath}`)
}

await cp(join(repoRoot, "public"), join(bundleDir, "public"), { recursive: true })
await cp(proxyPath, join(bundleDir, "anti-proxy"))
await cp(join(repoRoot, "LICENSE"), join(bundleDir, "LICENSE"))
await cp(join(repoRoot, "README.md"), join(bundleDir, "README.md"))

const tar = Bun.spawn([
    "tar",
    "-czf",
    archivePath,
    "-C",
    bundleRoot,
    "anti-api",
], {
    cwd: repoRoot,
    stdout: "inherit",
    stderr: "inherit",
})

const tarExit = await tar.exited
if (tarExit !== 0) {
    throw new Error(`tar failed with exit code ${tarExit}`)
}

console.log(`Built Homebrew bundle for ${version} (${arch})`)
console.log(`Bundle directory: ${bundleDir}`)
console.log(`Executable: ${basename(binaryPath)}`)
console.log(`Archive: ${archivePath}`)
