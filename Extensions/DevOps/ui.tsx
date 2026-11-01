import { showToast, Toast } from "@raycast/api";
export async function action(task: () => Promise<unknown>) {
  try { await task(); } catch (error) { await showToast({ style: Toast.Style.Failure, title: error instanceof Error ? error.message : "Command failed" }); }
}
