import { required } from "../../shared";
export interface HelmRelease { name: string; namespace: string; revision: number; status: string }
export function parseHelmReleases(text: string): HelmRelease[] {
  const data=JSON.parse(text);
  if(!Array.isArray(data)) throw new Error("Invalid Helm release list");
  return data.map(row=> {
    if(typeof row.name!=="string" || !row.name || row.name.startsWith("-") || typeof row.namespace!=="string" || !row.namespace || !Number.isInteger(Number(row.revision)) || Number(row.revision)<1) throw new Error("Invalid Helm release");
    return {name:row.name,namespace:row.namespace,revision:Number(row.revision),status:String(row.status ?? "unknown")};
  });
}
export function helmArguments(action: string, release: HelmRelease, context: string, production: string[]=[], revision?: number): string[] {
  required(context,"Kubernetes context");
  if(!/^[a-z0-9][a-z0-9.-]*$/.test(release.name)) throw new Error("Invalid Helm release name");
  let args: string[];
  switch(action) {
    case "history": args=["history",release.name,"--output","json"]; break;
    case "values": args=["get","values",release.name,"--output","yaml"]; break;
    case "rollback":
      if(production.includes(context)) throw new Error("Rollback is blocked for production contexts");
      if(!Number.isInteger(revision) || revision!<1 || revision!>=release.revision) throw new Error("Select an earlier positive revision");
      args=["rollback",release.name,String(revision)]; break;
    default: throw new Error("Unsupported Helm action");
  }
  return [...args,"--namespace",required(release.namespace,"namespace"),"--kube-context",context];
}
