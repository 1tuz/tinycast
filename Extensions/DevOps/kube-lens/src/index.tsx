import React, { useState } from "react";
import { Action, ActionPanel, Detail, List, getPreferenceValues, useNavigation } from "@raycast/api";
import { run } from "../../shared";
import { action } from "../../ui";
import { KubeLensEvent, KubeLensPod, kubeLensArguments, parseEvents, parsePods } from "./kube-lens";

export default function Command() {
  const preferences = getPreferenceValues<{context:string;namespace:string}>();
  const [pods, setPods] = useState<KubeLensPod[]>([]);
  const [events, setEvents] = useState<KubeLensEvent[]>([]);
  const [busy, setBusy] = useState(false);
  const { push } = useNavigation();
  const refresh = async () => {
    setBusy(true);
    try {
      const [podData, eventData] = await Promise.all([
        run("kubectl", kubeLensArguments("pods", preferences.context, preferences.namespace)),
        run("kubectl", kubeLensArguments("events", preferences.context, preferences.namespace)),
      ]);
      setPods(parsePods(podData));
      setEvents(parseEvents(eventData));
    } finally { setBusy(false); }
  };
  const detail = async (title: string, args: string[]) => {
    const text = await run("kubectl", args);
    push(<Detail markdown={`## ${title}\n\n\`\`\`text\n${text}\n\`\`\``} />);
  };
  const warnings = events.filter(event => event.type === "Warning");
  return <List isLoading={busy} searchBarPlaceholder={`Pods in ${preferences.namespace}`}>
    <List.EmptyView title="Load cluster diagnostics" description="Configure an exact Kubernetes context and namespace, then refresh." actions={<ActionPanel><Action title="Refresh" onAction={()=>action(refresh)}/></ActionPanel>} />
    <List.Section title="Pods">
      {pods.map(pod=><List.Item key={pod.name} title={pod.name} subtitle={pod.diagnostic} accessories={[{text:pod.phase},{text:pod.containers.join(", ")}]} actions={<ActionPanel>
        <Action title="Show Logs" onAction={()=>action(()=>detail(`${pod.name} logs`,kubeLensArguments("logs",preferences.context,preferences.namespace,pod.name)))}/>
        <Action title="Describe Pod" onAction={()=>action(()=>detail(`${pod.name} details`,kubeLensArguments("describe",preferences.context,preferences.namespace,pod.name)))}/>
        <Action title="Refresh" onAction={()=>action(refresh)}/>
      </ActionPanel>}/>) }
    </List.Section>
    <List.Section title={`Warning Events (${warnings.length})`}>
      {warnings.map((event,index)=><List.Item key={`${event.timestamp}/${event.object}/${index}`} title={event.reason} subtitle={event.object} accessories={[{text:event.timestamp}]} detail={<List.Item.Detail markdown={event.message}/>}/>) }
    </List.Section>
    <List.Item title="Refresh diagnostics" actions={<ActionPanel><Action title="Refresh" onAction={()=>action(refresh)}/></ActionPanel>}/>
  </List>;
}
