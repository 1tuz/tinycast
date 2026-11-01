import React, { useState } from "react";
import { List, Form, Action, ActionPanel, confirmAlert, getPreferenceValues, open, useNavigation } from "@raycast/api";
import { configuredRoots, run } from "../../shared";
import { action } from "../../ui";
import { Worktree, createWorktree, discoverRepositories, listWorktrees, removalState } from "./worktrees";
function Create({ root, refresh }: {root:string; refresh:()=>Promise<void>}) {
  const { pop }=useNavigation();
  return <Form actions={<ActionPanel><Action.SubmitForm title="Create Worktree" onSubmit={values=>action(async()=>{await createWorktree(root,String(values.issueKey));await refresh();pop();})}/></ActionPanel>}><Form.Description text={root}/><Form.TextField id="issueKey" title="Jira Key" placeholder="DO-123"/></Form>;
}
export default function Command() {
  const [trees,setTrees]=useState<(Worktree & {root:string})[]>([]);
  const [busy,setBusy]=useState(false); const {push}=useNavigation();
  const prefs=getPreferenceValues<{projectRoots:string;mergeBase:string}>();
  const refresh=async()=>{setBusy(true);try { const repos=await discoverRepositories(configuredRoots(prefs.projectRoots));const result=[];for(const root of repos) result.push(...(await listWorktrees(root)).map(tree=>({...tree,root})));setTrees(result);} finally {setBusy(false);} };
  const load=()=>action(refresh);
  return <List isLoading={busy} searchBarPlaceholder="Search worktrees" actions={<ActionPanel><Action title="Load Configured Projects" onAction={load}/></ActionPanel>}><List.EmptyView title="Load configured project roots" description="Set allowed roots in extension preferences. Discovery checks roots and their direct children."/>{trees.map(tree=><List.Item key={tree.path} title={tree.branch || "Detached HEAD"} subtitle={tree.path} accessories={[{text:`${tree.dirty?"dirty":"clean"} ↑${tree.ahead} ↓${tree.behind}`}]} actions={<ActionPanel>
    <Action title="Open Worktree" onAction={()=>action(()=>open(tree.path))}/>
    <Action title="Create Worktree from Jira Key" onAction={()=>push(<Create root={tree.root} refresh={refresh}/>)}/>
    <Action title="Open Merge Request" onAction={()=>action(()=>run("glab",["mr","view","--web"],tree.path))}/>
    <Action title="Remove Worktree" onAction={()=>action(async()=>{await removalState(tree,prefs.mergeBase);if(!await confirmAlert({title:"Remove worktree?",message:tree.path}))return;await removalState(tree,prefs.mergeBase);await run("git",["-C",tree.root,"worktree","remove","--",tree.path]);await refresh();})}/>
    <Action title="Refresh" onAction={load}/>
  </ActionPanel>}/>)}</List>;
}
