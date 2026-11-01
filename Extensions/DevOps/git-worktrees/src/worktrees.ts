import { existsSync, mkdirSync, readdirSync, lstatSync, realpathSync } from "fs";
import { join } from "path";
import { run } from "../../shared";
import { validateIssueKey } from "../../jira-key-actions/src/jira-key";
export interface Worktree { path: string; branch: string; detached: boolean; bare: boolean; dirty: boolean; ahead: number; behind: number }
export function parseWorktrees(text: string): Worktree[] {
  return text.trim().split(/\n\n+/).filter(Boolean).map(block=> {
    const lines=block.split("\n");
    const path = lines.find(l=>l.startsWith("worktree "))?.slice(9) ?? "";
    if (!path || path.startsWith('"')) throw new Error("Unsupported Git worktree path encoding");
    return {path,branch:lines.find(l=>l.startsWith("branch "))?.slice(7).replace(/^refs\/heads\//, "") ?? "",detached:lines.includes("detached"),bare:lines.includes("bare"),dirty:false,ahead:0,behind:0};
  });
}
export function parseStatus(text: string) {
  const lines=text.trimEnd().split("\n");
  return {dirty:lines.slice(1).some(Boolean),ahead:Number(lines[0]?.match(/ahead (\d+)/)?.[1] ?? 0),behind:Number(lines[0]?.match(/behind (\d+)/)?.[1] ?? 0)};
}
export function createArguments(root: string, issueKey: string, collision: boolean): string[] {
  validateIssueKey(issueKey);
  if(collision) throw new Error("Worktree path already exists");
  return ["-C",root,"worktree","add","-b",issueKey,"--",join(root,".worktrees",issueKey)];
}
export function assertRemovable(state: {dirty: boolean; merged: boolean}) {
  if(state.dirty) throw new Error("Worktree has local changes");
  if(!state.merged) throw new Error("Worktree branch is not merged into the configured base");
}
export async function discoverRepositories(roots: string[]): Promise<string[]> {
  const repos: string[]=[];
  for(const root of roots) {
    if(existsSync(join(root,".git"))) repos.push(root);
    for(const entry of readdirSync(root,{withFileTypes:true})) {
      if(entry.isDirectory() && !entry.name.startsWith(".") && existsSync(join(root,entry.name,".git"))) repos.push(join(root,entry.name));
    }
  }
  return [...new Set(repos)];
}
export async function listWorktrees(root: string): Promise<Worktree[]> {
  const trees=parseWorktrees(await run("git",["-C",root,"-c","core.quotePath=false","worktree","list","--porcelain"]));
  for(const tree of trees) if(!tree.bare) Object.assign(tree,parseStatus(await run("git",["-C",tree.path,"status","--porcelain=v1","--branch"])));
  return trees;
}
export async function createWorktree(root: string, issueKey: string): Promise<Worktree> {
  const target=join(root,".worktrees",validateIssueKey(issueKey));
  const args=createArguments(root,issueKey,existsSync(target));
  const parent=join(root,".worktrees");
  if(existsSync(parent) && (!lstatSync(parent).isDirectory() || lstatSync(parent).isSymbolicLink())) throw new Error("Worktree parent must be a local directory");
  mkdirSync(parent,{recursive:true});
  await run("git",args);
  return (await listWorktrees(root)).find(t=>realpathSync(t.path)===realpathSync(target))!;
}
export async function removalState(tree: Worktree, base: string) {
  if(!/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(base) || tree.detached || tree.bare || !tree.branch) throw new Error("Choose a branch worktree and configure its merge base");
  const status=parseStatus(await run("git",["-C",tree.path,"status","--porcelain=v1","--branch"]));
  let merged=false;
  try { await run("git",["-C",tree.path,"merge-base","--is-ancestor","--",tree.branch,base]); merged=true; } catch {}
  assertRemovable({...status,merged});
}
