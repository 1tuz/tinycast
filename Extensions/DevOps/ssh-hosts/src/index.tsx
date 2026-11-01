import React, { useState } from "react";
import { List, Action, ActionPanel, getPreferenceValues, openTerminal } from "@raycast/api";
import { run } from "../../shared";
import { action } from "../../ui";
import { readSSHHostAliases, sshArguments, parseInventoryAliases } from "./ssh-config";
export default function Command() {
  const [hosts,setHosts]=useState<string[]>([]);const [busy,setBusy]=useState(false);
  const load=async()=>{setBusy(true);try{const aliases=readSSHHostAliases();const inventory=getPreferenceValues<{inventoryPath:string}>().inventoryPath;if(inventory)aliases.push(...parseInventoryAliases(await run("ansible-inventory",["--inventory",inventory,"--list"])));setHosts([...new Set(aliases)]);}finally{setBusy(false);}};
  return <List isLoading={busy} actions={<ActionPanel><Action title="Load Host Aliases" onAction={()=>action(load)}/></ActionPanel>}><List.EmptyView title="Load SSH host aliases" description="Reads ~/.ssh/config and confined config includes. Optional Ansible inventory comes from preferences. Match commands are never evaluated during discovery."/>{hosts.map(host=><List.Item key={host} title={host} actions={<ActionPanel><Action title="Open SSH in Terminal" onAction={()=>action(()=>openTerminal("ssh",sshArguments(host)))}/><Action title="Refresh" onAction={()=>action(load)}/></ActionPanel>}/>)}</List>;
}
