import React, { useState } from "react";
import { List, Action, ActionPanel, confirmAlert, getPreferenceValues } from "@raycast/api";
import { run } from "../../shared";
import { action } from "../../ui";
import { ComposeProject, parseComposeProjects, composeArguments } from "./compose";
export default function Command() {
  const prefs=getPreferenceValues<{dockerContext:string}>();
  const [context,setContext]=useState(prefs.dockerContext || "default");
  const [contexts,setContexts]=useState<string[]>([context]);
  const [projects,setProjects]=useState<ComposeProject[]>([]);const [busy,setBusy]=useState(false);
  const refresh=async()=>{setBusy(true);try{const rows=await run("docker",["context","ls","--format","{{.Name}}"]);setContexts(rows.trim().split("\n").filter(Boolean));const ids=(await run("docker",["--context",context,"ps","--all","--filter","label=com.docker.compose.project","--format","{{.ID}}"])).trim().split("\n").filter(Boolean);if(ids.length>200)throw new Error("Too many Compose containers; narrow the Docker context");setProjects(ids.length?parseComposeProjects(await run("docker",["--context",context,"inspect",...ids])):[]);}finally{setBusy(false);}};
  const mutate=async(name:string,project:ComposeProject)=>{if(name!=="up" && !await confirmAlert({title:`${name} Compose project?`,message:`${project.name} · ${context}`}))return;await run("docker",composeArguments(name,context,project));await refresh();};
  return <List isLoading={busy} searchBarAccessory={<List.Dropdown tooltip="Docker Context" value={context} onChange={value=>{setContext(value);setProjects([]);}}>{contexts.map(c=><List.Dropdown.Item key={c} title={c} value={c}/>)}</List.Dropdown>} actions={<ActionPanel><Action title="Load Projects and Contexts" onAction={()=>action(refresh)}/></ActionPanel>}><List.EmptyView title="Load Compose projects" description="Projects come from container Compose labels. The selected Docker context stays local to Tinycast."/>{projects.map(project=><List.Item key={project.name} title={project.name} subtitle={project.directory} accessories={[{text:project.status ?? ""}]} actions={<ActionPanel>{["up","down","restart"].map(name=><Action key={name} title={`${name[0].toUpperCase()+name.slice(1)} Project`} onAction={()=>action(()=>mutate(name,project))}/>)}<Action title="Refresh" onAction={()=>action(refresh)}/></ActionPanel>}/>)}</List>;
}
