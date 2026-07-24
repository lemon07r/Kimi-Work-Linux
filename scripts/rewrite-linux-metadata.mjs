import fs from "node:fs";
import path from "node:path";

const resourcesRoot = process.argv[2];
if (!resourcesRoot) {
  throw new Error("Usage: rewrite-linux-metadata.mjs <resources-root>");
}

function readJson(relativePath) {
  const filePath = path.join(resourcesRoot, relativePath);
  return [filePath, JSON.parse(fs.readFileSync(filePath, "utf8"))];
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

{
  const [filePath, metadata] = readJson("daimon-bundle/bundle.json");
  metadata.platform = "linux-x64";
  metadata.dependencyBundling.nodePty.targetPlatform = "linux-x64";
  metadata.runtimes.python.asset =
    "cpython-3.12.13+20260718-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz";
  metadata.runtimes.python.sha256 =
    "5854aa6ec71cad00334d5065633c210b2e7feb40956767a59a91791cadcf0b79";
  writeJson(filePath, metadata);
}

{
  const [filePath, metadata] = readJson("gateway/build-info.json");
  metadata.arch = "x64";
  metadata.platform = "linux";
  metadata.portedAt = new Date().toISOString();
  writeJson(filePath, metadata);
}

fs.writeFileSync(
  path.join(resourcesRoot, "daimon-bundle/.daimon-bundle-stamp"),
  "0.5.46|linux-x64|ported|native-linux-x64|prune3\n",
);
fs.writeFileSync(
  path.join(resourcesRoot, "gateway/.gateway-stamp"),
  "linux-x64|ported:openclaw@2026.3.13\n",
);
fs.writeFileSync(
  path.join(resourcesRoot, "runtime/.node-stamp"),
  "24.15.0-linux-x64\n",
);
