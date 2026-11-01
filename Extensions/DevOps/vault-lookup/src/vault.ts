export function vaultArguments(path: string): string[] {
  if(!path || path.startsWith("-") || /[\0\r\n]/.test(path)) throw new Error("Enter a Vault secret path");
  return ["kv","get","-format=json",path];
}
export function vaultData(json: string): Record<string, unknown> {
  let value: any;
  try { value=JSON.parse(json); } catch { throw new Error("Invalid Vault response"); }
  const data=value?.data?.data ?? value?.data;
  if(!data || typeof data!=="object" || Array.isArray(data)) throw new Error("Invalid Vault response");
  return data;
}
export function parseVaultResponse(json: string, keyPath: string): string {
  const keys=keyPath.split(".");
  if(keys.some(key=>!key || ["__proto__","prototype","constructor"].includes(key))) throw new Error("Selected field is unavailable");
  let value: unknown=vaultData(json);
  for(const key of keys) {
    if(!value || typeof value!=="object" || !Object.hasOwn(value,key)) throw new Error("Selected field is unavailable");
    value=(value as any)[key];
  }
  if(!["string","number","boolean"].includes(typeof value)) throw new Error("Select a scalar field");
  return String(value);
}
export function vaultFields(json: string): string[] {
  const result: string[]=[];
  function visit(value: unknown,prefix: string) {
    if(value && typeof value==="object" && !Array.isArray(value)) {
      for(const key of Object.keys(value)) if(!key.includes(".") && !["__proto__","prototype","constructor"].includes(key)) visit((value as any)[key],prefix?`${prefix}.${key}`:key);
    } else if(["string","number","boolean"].includes(typeof value)) result.push(prefix);
  }
  visit(vaultData(json),"");
  return result;
}
