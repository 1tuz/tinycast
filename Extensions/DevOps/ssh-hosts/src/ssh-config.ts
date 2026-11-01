import { resolve, dirname, relative, sep, basename } from "path";
import { existsSync, readFileSync, realpathSync, lstatSync } from "fs";
import { homedir } from "os";
const aliasPattern=/^[A-Za-z0-9][A-Za-z0-9_.-]*$/;
export function parseSSHHostAliases(config: string): string[] {
  const result: string[]=[];
  for(const line of config.split(/\r?\n/)) {
    const match=line.split("#",1)[0].match(/^\s*Host(?:\s+|=)(.*)$/i);
    if(match) for(const alias of match[1].split(/\s+/)) if(aliasPattern.test(alias)) result.push(alias);
  }
  return [...new Set(result)];
}
export function resolveSSHInclude(include: string,current: string,sshRoot: string): string {
  const root=resolve(sshRoot);
  const expanded=include.startsWith("~/.ssh/") ? resolve(root,include.slice(7)) : include;
  const path=resolve(dirname(current),expanded);
  const rel=relative(root,path);
  if(!rel || rel===".." || rel.startsWith(`..${sep}`) || rel.startsWith(sep) || /[?*%~\0]/.test(include) || /^(id_|authorized_keys|known_hosts)/i.test(basename(path)) || /\.(pem|key|pub)$/i.test(path)) throw new Error("SSH Include must reference a config file within ~/.ssh");
  return path;
}
export function discoverSSHHostAliases(sshRoot: string, read: (path:string)=>string|undefined): string[] {
  const seen=new Set<string>(); const aliases: string[]=[];
  function visit(path: string,depth: number) {
    if(seen.has(path)) return;
    if(depth>16 || seen.size>=128) throw new Error("SSH Include limit exceeded");
    seen.add(path); const config=read(path); if(config===undefined) return;
    if(config.length>1024*1024 || /-----BEGIN .*PRIVATE KEY-----/.test(config)) throw new Error("SSH config is invalid");
    for(const line of config.split(/\r?\n/)) {
      const include=line.split("#",1)[0].match(/^\s*Include(?:\s+|=)(.*)$/i);
      if(include) {
        for(const part of include[1].split(/\s+/).filter(Boolean)) visit(resolveSSHInclude(part,path,sshRoot),depth+1);
      } else aliases.push(...parseSSHHostAliases(line));
    }
  }
  visit(resolve(sshRoot,"config"),0); return [...new Set(aliases)];
}
export function readSSHHostAliases(): string[] {
  const root=resolve(homedir(),".ssh");
  return discoverSSHHostAliases(root,path=> {
    if(!existsSync(path)) return undefined;
    const actual=realpathSync(path); const rel=relative(root,actual);
    if(rel.startsWith("..") || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile() || lstatSync(path).size>1024*1024) throw new Error("SSH Include must be a local config file within ~/.ssh");
    return readFileSync(path,"utf8");
  });
}
export function sshArguments(alias: string): string[] {
  if(!aliasPattern.test(alias)) throw new Error("Choose a valid SSH host alias");
  return ["--",alias];
}
export function parseInventoryAliases(text: string): string[] {
  const data=JSON.parse(text); const result: string[]=[];
  for(const [name,group] of Object.entries(data)) if(name!=="_meta" && group && typeof group==="object") for(const host of (group as any).hosts ?? []) if(typeof host==="string" && aliasPattern.test(host)) result.push(host);
  return [...new Set(result)];
}
