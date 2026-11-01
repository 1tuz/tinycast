import React, { useState } from "react";
import { List, Detail, Form, Action, ActionPanel, confirmAlert, getPreferenceValues, useNavigation } from "@raycast/api";
import { run, required } from "../../shared";
import { action } from "../../ui";
import { HelmRelease, parseHelmReleases, helmArguments } from "./helm";
function production(): string[] { return getPreferenceValues<{productionContexts:string}>().productionContexts.split("\n").map(s=>s.trim()).filter(Boolean); }
function Rollback({ release, context, refresh }: {release:HelmRelease;context:string;refresh:()=>Promise<void>}) {
  const {pop}=useNavigation();
  return <Form actions={<ActionPanel><Action.SubmitForm title="Rollback Release" onSubmit={values=>action(async()=>{const revision=Number(values.revision);helmArguments("rollback",release,context,production(),revision);if(!await confirmAlert({title:"Rollback Helm release?",message:`${release.name} · ${context} · revision ${revision}`}))return;await run("helm",helmArguments("rollback",release,context,production(),revision));await refresh();pop();})}/></ActionPanel>}><Form.Description text={`${release.namespace}/${release.name} · ${context}`}/><Form.TextField id="revision" title="Target Revision"/></Form>;
}
export default function Command() {
  const context=getPreferenceValues<{kubeContext:string}>().kubeContext;
  const [releases,setReleases]=useState<HelmRelease[]>([]);const [busy,setBusy]=useState(false);const {push}=useNavigation();
  const refresh=async()=>{setBusy(true);try{setReleases(parseHelmReleases(await run("helm",["list","--all-namespaces","--output","json","--kube-context",required(context,"Kubernetes context")])));}finally{setBusy(false);}};
  const detail=async(name:string,release:HelmRelease)=>{const value=await run("helm",helmArguments(name,release,context));push(<Detail markdown={`\`\`\`\n${value}\n\`\`\``}/>);};
  return <List isLoading={busy} actions={<ActionPanel><Action title="Load Releases" onAction={()=>action(refresh)}/></ActionPanel>}><List.EmptyView title="Load Helm releases" description="Configure an explicit Kubernetes context and production context names in preferences."/>{releases.map(release=><List.Item key={`${release.namespace}/${release.name}`} title={release.name} subtitle={release.namespace} accessories={[{text:`${release.status} · revision ${release.revision}`}]} actions={<ActionPanel><Action title="Show History" onAction={()=>action(()=>detail("history",release))}/><Action title="Show Values" onAction={()=>action(()=>detail("values",release))}/>{!production().includes(context) && <Action title="Rollback" onAction={()=>push(<Rollback release={release} context={context} refresh={refresh}/>)}/>}<Action title="Refresh" onAction={()=>action(refresh)}/></ActionPanel>}/>)}</List>;
}
