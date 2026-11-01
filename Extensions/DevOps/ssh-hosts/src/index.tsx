import React, { useState } from "react";
import { List, Detail, Action, ActionPanel, getPreferenceValues, openTerminal, useNavigation } from "@raycast/api";
import { run } from "../../shared";
import { action } from "../../ui";
import { readSSHHostAliases, sshArguments, sshConfigArguments, parseInventoryAliases } from "./ssh-config";
function sshConfigMarkdown(output:string): string {
  let fence="```";
  for(const match of output.matchAll(/`+/g)) if(match[0].length>=fence.length) fence="`".repeat(match[0].length+1);
  return `${fence}text\n${output}\n${fence}`;
}
export default function Command() {
  const [hosts,setHosts]=useState<string[]>([]);const [busy,setBusy]=useState(false);
  const {push}=useNavigation();
  const load=async()=>{setBusy(true);try{const aliases=readSSHHostAliases();const inventory=getPreferenceValues<{inventoryPath:string}>().inventoryPath;if(inventory)aliases.push(...parseInventoryAliases(await run("ansible-inventory",["--inventory",inventory,"--list"])));setHosts([...new Set(aliases)]);}finally{setBusy(false);}};
  const showConfig=async(host:string)=>{const output=await run("ssh",sshConfigArguments(host));push(<Detail markdown={sshConfigMarkdown(output)}/>);};
  return <List isLoading={busy} actions={<ActionPanel><Action title="Load Host Aliases" onAction={()=>action(load)}/></ActionPanel>}><List.EmptyView title="Load SSH host aliases" description="Reads ~/.ssh/config and confined config includes. Optional Ansible inventory comes from preferences. Match commands are not evaluated during discovery."/>{hosts.map(host=><List.Item key={host} title={host} actions={<ActionPanel><Action title="Show Effective Configuration" onAction={()=>action(()=>showConfig(host))}/><Action title="Open SSH in Terminal" onAction={()=>action(()=>openTerminal("ssh",sshArguments(host)))}/><Action title="Refresh" onAction={()=>action(load)}/></ActionPanel>}/>)}</List>;
}
