import React, { useState } from "react";
import { List, Action, ActionPanel, Clipboard, getSelectedText, getPreferenceValues, open } from "@raycast/api";
import { parseIssueKey, jiraIssueURL } from "./jira-key";
import { configuredRoots, run } from "../../shared";
import { action } from "../../ui";
import { discoverRepositories, listWorktrees } from "../../git-worktrees/src/worktrees";
export default function Command() {
  const [text,setText]=useState("");
  const prefs=getPreferenceValues<{jiraURL:string;projectRoots:string}>();
  const key=parseIssueKey(text);
  const local=async(mr:boolean)=> {
    if(!key)return;
    for(const repo of await discoverRepositories(configuredRoots(prefs.projectRoots))) {
      const tree=(await listWorktrees(repo)).find(t=>t.branch===key || t.branch.endsWith(`/${key}`));
      if(tree) {if(mr) await run("glab",["mr","view","--web"],tree.path);else await open(tree.path);return;}
    }
    throw new Error("No worktree for this Jira key in configured roots");
  };
  return <List searchText={text} onSearchTextChange={setText} filtering={false} searchBarPlaceholder="Enter or paste DO-123" actions={<ActionPanel><Action title="Read Selected Text" onAction={()=>action(async()=>{try {const selected=await getSelectedText();const parsed=parseIssueKey(selected);if(parsed)setText(parsed);else throw new Error();}catch {throw new Error("Selection unavailable. Enter a Jira key in the search field.");}})}/></ActionPanel>}>
    <List.EmptyView title="Enter a Jira key" description="Use Read Selected Text with Accessibility permission, or type the key here."/>
    {key && <List.Item title={key} subtitle="Jira issue actions" actions={<ActionPanel>
      <Action title="Open Jira Issue" onAction={()=>action(()=>open(jiraIssueURL(prefs.jiraURL,key)))}/>
      <Action title="Copy Branch Name" onAction={()=>action(()=>Clipboard.copy(key))}/>
      <Action title="Open Local Worktree" onAction={()=>action(()=>local(false))}/>
      <Action title="Open Merge Request" onAction={()=>action(()=>local(true))}/>
    </ActionPanel>}/>}
  </List>;
}
