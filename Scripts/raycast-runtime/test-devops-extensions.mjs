import assert from "node:assert/strict";
import { test, after } from "node:test";
import { mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { createRequire } from "node:module";
import { build } from "esbuild";
import { execFileSync } from "node:child_process";
const root = resolve(import.meta.dirname, "../..");
const scratch = mkdtempSync(join(tmpdir(), "tinycast-devops-tests-"));
const require = createRequire(import.meta.url);
async function source(name, file) {
  const output = join(scratch, `${name}-${file}.cjs`);
  await build({entryPoints:[join(root, "Extensions/DevOps", name, "src", `${file}.ts`)],bundle:true,platform:"node",format:"cjs",outfile:output});
  return require(output);
}
after(() => rmSync(scratch,{recursive:true,force:true}));
{
  const git = await source("git-worktrees", "worktrees");
  const jira = await source("jira-key-actions", "jira-key");
  const compose = await source("compose-projects", "compose");
  const helm = await source("helm-releases", "helm");
  const vault = await source("vault-lookup", "vault");
  const ssh = await source("ssh-hosts", "ssh-config");
  const kubeLens = await source("kube-lens", "kube-lens");
  const catalog = await import("./build-devops-extensions.mjs");
  test("catalog has seven stable packages and validates manifests", () => {
    assert.deepEqual(catalog.packageIDs,["git-worktrees","jira-key-actions","compose-projects","helm-releases","vault-lookup","ssh-hosts","kube-lens"]);
    assert.throws(()=>catalog.validateManifest({name:"../bad",commands:[]},"../bad"));
    assert.throws(()=>catalog.validateManifest({name:"git-worktrees",commands:[{name:"../escape"}]},"git-worktrees"));
    assert.equal(catalog.commandOutputPath("/out","git-worktrees","index"),"/out/git-worktrees/index.js");
    assert.throws(()=>catalog.verifyPackage(scratch,"git-worktrees"));
    const manifest={name:"git-worktrees",title:"Worktrees",commands:[{name:"index",title:"Worktrees",mode:"view"}]};
    mkdirSync(join(scratch,"git-worktrees"));
    writeFileSync(join(scratch,"git-worktrees/package.json"),JSON.stringify(manifest));
    assert.throws(()=>catalog.verifyPackage(scratch,"git-worktrees"),/Missing bundle/);
    writeFileSync(join(scratch,"git-worktrees/index.js"),"module.exports={};");
    assert.equal(catalog.verifyPackage(scratch,"git-worktrees").name,"git-worktrees");
  });
  test("Jira accepts one bounded key and preserves a configured URL prefix", () => {
    assert.equal(jira.parseIssueKey("Issue DO-123 in text"),"DO-123");
    for(const value of ["do-12","X-12","DO-1;rm -rf /","DO-12 DO-13","XDO-12bad"]) assert.equal(jira.parseIssueKey(value),null);
    assert.equal(jira.jiraIssueURL("https://jira.example/jira///","DO-12"),"https://jira.example/jira/browse/DO-12");
    assert.throws(()=>jira.jiraIssueURL("javascript:alert(1)","DO-12"));
    assert.throws(()=>jira.jiraIssueURL("https://jira.example","../DO-12"));
  });
  test("git porcelain retains paths, branch and dirty divergence", () => {
    const [worktree]=git.parseWorktrees("worktree /tmp/project with spaces\nHEAD abc\nbranch refs/heads/DO-12\n\n");
    assert.equal(worktree.path,"/tmp/project with spaces"); assert.equal(worktree.branch,"DO-12");
    assert.deepEqual(git.parseStatus("## DO-12...origin/DO-12 [ahead 2, behind 1]\n M a\n"),{dirty:true,ahead:2,behind:1});
    assert.deepEqual(git.parseStatus("## main\n"),{dirty:false,ahead:0,behind:0});
    assert.throws(()=>git.createArguments("/root","DO-12",true));
    assert.throws(()=>git.createArguments("/root","DO-12;touch /tmp/bad",false));
    assert.throws(()=>git.createArguments("/root","../DO-12",false));
    assert.deepEqual(git.createArguments("/root","DO-12",false),["-C","/root","worktree","add","-b","DO-12","--","/root/.worktrees/DO-12"]);
    assert.throws(()=>git.assertRemovable({dirty:true,merged:true}));
    assert.throws(()=>git.assertRemovable({dirty:false,merged:false}));
  });
  test("Git creates an isolated worktree and refuses collisions or dirty removal", async () => {
    const repo=join(scratch,"repo with spaces");mkdirSync(repo);
    const command=args=>execFileSync("git",["-C",repo,...args],{encoding:"utf8",stdio:"pipe"});
    command(["init","--initial-branch=main"]);
    command(["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","commit","--allow-empty","-m","Fixture"]);
    const created=await git.createWorktree(repo,"DO-120");
    assert.equal(created.branch,"DO-120");assert.equal(realpathSync(created.path),realpathSync(join(repo,".worktrees","DO-120")));
    await assert.rejects(()=>git.createWorktree(repo,"DO-120"),/already exists/);
    await git.removalState(created,"main");
    writeFileSync(join(created.path,"untracked"),"fixture");
    await assert.rejects(()=>git.removalState(created,"main"),/local changes/);
  });
  test("bundler emits only one manifest and CommonJS command per package", async () => {
    const output=join(scratch,"bundles");await catalog.buildDevOpsExtensions(output);
    assert.deepEqual(readdirSync(output).sort(),[...catalog.packageIDs].sort());
    for(const id of catalog.packageIDs) {
      assert.deepEqual(readdirSync(join(output,id)).sort(),["index.js","package.json"]);
      assert.equal(catalog.verifyPackage(output,id).name,id);
    }
  });
  test("Compose reads labels, requires exact context, and never deletes volumes", () => {
    const data='{"Labels":"com.docker.compose.project=demo,com.docker.compose.project.working_dir=/tmp/demo","State":"running"}';
    assert.equal(compose.parseComposeProjects(data)[0].directory,"/tmp/demo");
    assert.deepEqual(compose.composeArguments("down","remote prod",{name:"demo",directory:"/tmp/demo"}),["--context","remote prod","compose","--project-directory","/tmp/demo","--project-name","demo","down"]);
    assert.throws(()=>compose.composeArguments("down","",{name:"demo",directory:"/tmp/demo"}));
    assert.throws(()=>compose.composeArguments("down -v","remote",{name:"demo",directory:"/tmp/demo"}));
    assert.equal(compose.parseComposeProjects('{"Labels":"unrelated=value"}').length,0);
    const inspected=compose.parseComposeProjects(JSON.stringify([{Config:{Labels:{"com.docker.compose.project":"app","com.docker.compose.project.working_dir":"/tmp/app","com.docker.compose.project.config_files":"/tmp/app/compose.yml,/tmp/app/override.yml"}},State:{Status:"running"}}]));
    assert.deepEqual(inspected[0].files,["/tmp/app/compose.yml","/tmp/app/override.yml"]);
    assert.equal(inspected[0].status,"running");
  });
  test("Helm retains revision and rejects production rollback at command construction", () => {
    const [release]=helm.parseHelmReleases('[{"name":"api","namespace":"team","revision":"3","status":"deployed"}]');
    assert.equal(release.revision,3);
    assert.deepEqual(helm.helmArguments("rollback",release,"dev",["prod"],2),["rollback","api","2","--namespace","team","--kube-context","dev"]);
    assert.throws(()=>helm.helmArguments("rollback",release,"prod",["prod"],2));
    assert.throws(()=>helm.helmArguments("rollback",release,"dev",[],0));
    assert.throws(()=>helm.parseHelmReleases('{}'));
  });
  test("Vault selects a scalar without leaking malformed data", () => {
    assert.equal(vault.parseVaultResponse('{"data":{"data":{"password":"secret","nested":{"id":7}}}}',"nested.id"),"7");
    assert.equal(vault.parseVaultResponse('{"data":{"password":"secret"}}',"password"),"secret");
    assert.throws(()=>vault.parseVaultResponse('{"data":{"password":"secret"}}',"missing"),/Selected field is unavailable/);
    assert.throws(()=>vault.parseVaultResponse('secret-not-json',"password"),/Invalid Vault response/);
    assert.throws(()=>vault.parseVaultResponse('{"data":{}}',"__proto__.bad"));
    assert.deepEqual(vault.vaultArguments("kv/path"),["kv","get","-format=json","kv/path"]);
    assert.throws(()=>vault.vaultArguments("-output-curl-string"));
  });
  test("SSH extracts aliases and confines includes without evaluating Match during discovery", () => {
    assert.deepEqual(ssh.parseSSHHostAliases('Host alpha beta *.example !bad\n IdentityFile ~/.ssh/id_ed25519\nMatch exec "touch /tmp/bad"\n HostName ignored\nHost gamma\n'),["alpha","beta","gamma"]);
    const files={"/home/me/.ssh/config":'Include conf.d/hosts\nHost root\n',"/home/me/.ssh/conf.d/hosts":'Host nested\nInclude ../config\n'};
    assert.deepEqual(ssh.discoverSSHHostAliases("/home/me/.ssh",p=>files[p]),["nested","root"]);
    assert.throws(()=>ssh.resolveSSHInclude("../../outside","/home/me/.ssh/config","/home/me/.ssh"));
    assert.throws(()=>ssh.resolveSSHInclude("~/.ssh/id_rsa","/home/me/.ssh/config","/home/me/.ssh"));
    assert.throws(()=>ssh.sshArguments("-ProxyCommand=bad"));
    assert.throws(()=>ssh.resolveSSHInclude("/outside/config","/home/me/.ssh/config","/home/me/.ssh"));
    assert.throws(()=>ssh.resolveSSHInclude("keys/key.pem","/home/me/.ssh/config","/home/me/.ssh"));
    assert.deepEqual(ssh.parseInventoryAliases('{"_meta":{"hostvars":{"private":"not-an-alias"}},"web":{"hosts":["app","-bad","app"]}}'),["app"]);
    assert.deepEqual(ssh.parseSSHHostAliases('Host alpha # comment\n'),["alpha"]);
    assert.deepEqual(ssh.sshArguments("alpha"),["--","alpha"]);
    assert.deepEqual(ssh.sshConfigArguments("alpha"),["-G","alpha"]);
    assert.throws(()=>ssh.sshConfigArguments("-G"));
  });
  test("KubeLens preserves full contexts and uses read-only explicit argv", () => {
    const context="arn:aws:eks:us-east-1:123456789012:cluster/prod";
    assert.deepEqual(kubeLens.kubeLensArguments("pods",context,"team-a"),["get","pods","--output","json","--context",context,"--namespace","team-a"]);
    assert.deepEqual(kubeLens.kubeLensArguments("events",context,"team-a"),["get","events","--output","json","--context",context,"--namespace","team-a"]);
    assert.deepEqual(kubeLens.kubeLensArguments("logs",context,"team-a","api-0"),["logs","api-0","--context",context,"--namespace","team-a","--tail","100"]);
    assert.throws(()=>kubeLens.kubeLensArguments("restart",context,"team-a","api-0"));
    assert.throws(()=>kubeLens.kubeLensArguments("pods",context,"team;bad"));
    const pods=kubeLens.parsePods(JSON.stringify({items:[{metadata:{name:"api-0"},status:{phase:"Running",containerStatuses:[{name:"api",ready:false,state:{waiting:{reason:"CrashLoopBackOff"}}}]},spec:{containers:[{name:"api"}]}}]}));
    assert.equal(pods[0].diagnostic,"CrashLoopBackOff");assert.equal(pods[0].healthy,false);
    assert.deepEqual(kubeLens.parseEvents(JSON.stringify({items:[{type:"Warning",reason:"BackOff",message:"restarting",involvedObject:{name:"api-0"},eventTime:"2026-01-01T00:00:00Z"}]})),[{type:"Warning",reason:"BackOff",message:"restarting",object:"api-0",timestamp:"2026-01-01T00:00:00Z"}]);
    assert.throws(()=>kubeLens.parsePods('{"items":{}}'));
  });
}
