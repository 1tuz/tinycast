import { build } from "esbuild";
import { mkdirSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
export const packageIDs = ["git-worktrees", "jira-key-actions", "compose-projects", "helm-releases", "vault-lookup", "ssh-hosts"];
const root = resolve(import.meta.dirname, "../..");
const safeName = /^[a-z][a-z0-9-]*$/;
export function validateManifest(manifest, id) {
  if(!packageIDs.includes(id) || manifest?.name!==id || !manifest.title || !Array.isArray(manifest.commands) || !manifest.commands.length) throw new Error(`Invalid DevOps package: ${id}`);
  const names=new Set();
  for(const command of manifest.commands) {
    if(!safeName.test(command.name) || names.has(command.name) || !command.title || command.mode!=="view") throw new Error(`Invalid command in ${id}`);
    names.add(command.name);
  }
  return manifest;
}
export function commandOutputPath(out, id, command) {
  if(!packageIDs.includes(id) || !safeName.test(command)) throw new Error("Invalid package output path");
  return join(out,id,`${command}.js`);
}
export function verifyPackage(out,id) {
  const dir=join(out,id);
  const manifest=validateManifest(JSON.parse(readFileSync(join(dir,"package.json"),"utf8")),id);
  for(const command of manifest.commands) {
    const file=commandOutputPath(out,id,command.name);
    if(!existsSync(file) || !statSync(file).isFile() || statSync(file).size===0) throw new Error(`Missing bundle: ${id}/${command.name}`);
  }
  return manifest;
}
export async function buildDevOpsExtensions(out=join(root,"Tinycast/Resources/DevOpsExtensions")) {
  for(const id of packageIDs) {
    const source=join(root,"Extensions/DevOps",id);
    const manifest=validateManifest(JSON.parse(readFileSync(join(source,"package.json"),"utf8")),id);
    mkdirSync(join(out,id),{recursive:true});
    for(const command of manifest.commands) {
      await build({entryPoints:[join(source,"src",`${command.name}.tsx`)],outfile:commandOutputPath(out,id,command.name),bundle:true,platform:"node",format:"cjs",target:"es2022",jsx:"automatic",external:["@raycast/api","react","react/jsx-runtime"],legalComments:"none",minify:false});
    }
    writeFileSync(join(out,id,"package.json"),JSON.stringify(manifest,null,2)+"\n");
    verifyPackage(out,id);
  }
  return packageIDs;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const out=process.argv.indexOf("--out");
  await buildDevOpsExtensions(out<0?undefined:resolve(process.argv[out+1]));
  console.log(`Built ${packageIDs.length} DevOps extension packages`);
}
