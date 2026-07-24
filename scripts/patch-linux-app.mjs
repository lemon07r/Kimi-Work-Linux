import fs from "node:fs";
import path from "node:path";

const appRoot = process.argv[2];
if (!appRoot) {
  throw new Error("Usage: patch-linux-app.mjs <app-root>");
}

const mainPath = path.join(appRoot, "out/main/index.js");
let source = fs.readFileSync(mainPath, "utf8");

const urlsBefore = `const PPT_TOOLS_SCRIPT_URLS = {
  posix: "https://www.kimi.com/neo-ppt/cli-install/install.sh",
  windows: "https://www.kimi.com/neo-ppt/cli-install/install.ps1"
};`;
const urlsAfter = `const PPT_TOOLS_SCRIPT_URLS = {
  posix: "https://www.kimi.com/neo-ppt/cli-install/install.sh",
  linux: "https://www.kimi.com/neo-ppt/cli-install/inside_install.sh",
  windows: "https://www.kimi.com/neo-ppt/cli-install/install.ps1"
};`;
const requestBefore = `  return {
    url: PPT_TOOLS_SCRIPT_URLS.posix,
    sourcePolicy: PPT_TOOLS_SOURCE_POLICY,
    scriptArgs: [installDir]
  };`;
const requestAfter = `  return {
    url: platform === "linux" ? PPT_TOOLS_SCRIPT_URLS.linux : PPT_TOOLS_SCRIPT_URLS.posix,
    sourcePolicy: PPT_TOOLS_SOURCE_POLICY,
    scriptArgs: [installDir]
  };`;

if (!source.includes(urlsBefore) || !source.includes(requestBefore)) {
  throw new Error(
    "The expected Kimi PPT installer code was not found; refusing an unsafe partial patch.",
  );
}

source = source.replace(urlsBefore, urlsAfter).replace(requestBefore, requestAfter);
fs.writeFileSync(mainPath, source);
