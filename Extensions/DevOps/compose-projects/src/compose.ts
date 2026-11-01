import { required } from "../../shared";
export interface ComposeProject { name: string; directory: string; files?: string[]; status?: string }
export function parseComposeProjects(text: string): ComposeProject[] {
  const rows = text.trim().startsWith("[") ? JSON.parse(text) : text.trim().split("\n").filter(Boolean).map(line=>JSON.parse(line));
  if(!Array.isArray(rows)) throw new Error("Invalid Compose project list");
  const result=new Map<string,ComposeProject>();
  for(const row of rows) {
    const rawLabels=row.Config?.Labels ?? row.Labels;
    const labels=typeof rawLabels === "string" ? Object.fromEntries(rawLabels.split(",").map((part:string)=>{const i=part.indexOf("=");return [part.slice(0,i),part.slice(i+1)];})) : (rawLabels ?? {});
    const name=labels["com.docker.compose.project"];
    const directory=labels["com.docker.compose.project.working_dir"];
    if(typeof name!=="string" || typeof directory!=="string" || !directory.startsWith("/")) continue;
    const files=typeof labels["com.docker.compose.project.config_files"]==="string" ? labels["com.docker.compose.project.config_files"].split(",") : undefined;
    result.set(name,{name,directory,files,status:typeof row.State === "string" ? row.State : row.State?.Status});
  }
  return [...result.values()];
}
export function composeArguments(action: string, context: string, project: ComposeProject): string[] {
  if(!["up","down","restart"].includes(action)) throw new Error("Unsupported Compose action");
  const args=["--context",required(context,"Docker context"),"compose","--project-directory",required(project.directory,"project directory"),"--project-name",required(project.name,"project name")];
  for(const file of project.files ?? []) args.push("--file",required(file,"Compose config file"));
  return [...args,action,...(action==="up"?["--detach"]:[])];
}
