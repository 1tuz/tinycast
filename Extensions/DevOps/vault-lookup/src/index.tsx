import React, { useState } from "react";
import { List, Action, ActionPanel, Clipboard, showToast, Toast } from "@raycast/api";
import { run } from "../../shared";
import { action } from "../../ui";
import { vaultArguments, vaultFields, parseVaultResponse } from "./vault";
export default function Command() {
  const [path,setPath]=useState("");const [fields,setFields]=useState<string[]>([]);const [busy,setBusy]=useState(false);
  const load=async()=>{setBusy(true);try{setFields(vaultFields(await run("vault",vaultArguments(path))));}finally{setBusy(false);}};
  const copy=async(field:string)=>{let json="";let value="";try{json=await run("vault",vaultArguments(path));value=parseVaultResponse(json,field);await Clipboard.copy(value,{concealed:true});await showToast({style:Toast.Style.Success,title:"Secret copied"});}finally{json="";value="";}};
  return <List isLoading={busy} searchText={path} onSearchTextChange={value=>{setPath(value);setFields([]);}} filtering={false} searchBarPlaceholder="Vault secret path, for example kv/team/service" actions={<ActionPanel><Action title="Load Field Names" onAction={()=>action(load)}/></ActionPanel>}><List.EmptyView title="Enter a Vault secret path" description="Load field names, then copy a selected scalar. Values never appear in the list."/>{fields.map(field=><List.Item key={field} title={field} actions={<ActionPanel><Action title="Copy Secret" onAction={()=>action(()=>copy(field))}/></ActionPanel>}/>)}</List>;
}
