/** Only the current status footer is authoritative; historical headers/turns
 * may name older models. The rollout catches up on the next submitted turn. */
export function codexModelFromPane(pane: string | null): string | null {
  const footer = pane?.split("\n").filter(line => line.trim()).at(-1)?.trim() ?? "";
  return footer.match(/^(gpt-[\w.-]+)(?:\s+[^·]*)?\s+·\s/i)?.[1]?.toLowerCase() ?? null;
}
