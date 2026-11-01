export const issuePattern = /^[A-Z][A-Z0-9]+-[0-9]+$/;
export function validateIssueKey(key: string): string {
  if (!issuePattern.test(key)) throw new Error("Enter a Jira key such as DO-123");
  return key;
}
export function parseIssueKey(text: string): string | null {
  const keys = text.match(/(?<![A-Za-z0-9_-])[A-Z][A-Z0-9]+-[0-9]+(?![A-Za-z0-9_-])/g) ?? [];
  if (keys.length !== 1 || /[;`$\\]/.test(text)) return null;
  return keys[0];
}
export function jiraIssueURL(baseURL: string, key: string): string {
  validateIssueKey(key);
  const url = new URL(baseURL);
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error("Configure an HTTP or HTTPS Jira base URL");
  return `${url.toString().replace(/\/+$/, "")}/browse/${key}`;
}
