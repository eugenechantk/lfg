// One emoji per alert status, at the start of every alert title, so a glance at
// the lock screen says what happened before the words do. Every sender goes
// through `alertTitle`: the push watcher, agent `lfg notify`, scheduled-task
// results. The Mac app and the Shortcuts confirmation use the same table in
// ios/LFGCore/Sources/LFGCore/AlertStatus.swift — keep the two identical.

export const ALERT_EMOJI = {
  completed: "✅",
  "needs-input": "🙋",
  blocked: "⚠️",
  working: "⏳",
  reminder: "🔔",
  job: "📅",
  started: "🚀",
} as const;

export type AlertStatus = keyof typeof ALERT_EMOJI;

// Base code points of the table's emoji. A leading run of these (with or
// without the U+FE0F presentation selector) is dropped before the right one is
// added, so an agent that writes "✅ Done" for a reminder gets "🔔 Done", not
// "🔔 ✅ Done".
const STATUS_SCALARS = new Set(
  Object.values(ALERT_EMOJI).map((e) => e.codePointAt(0)!),
);

/** `title` with exactly one status emoji in front: the one for `status`. */
export function alertTitle(status: AlertStatus, title: string): string {
  const chars = [...title];
  let i = 0;
  while (i < chars.length) {
    const cp = chars[i]!.codePointAt(0)!;
    if (STATUS_SCALARS.has(cp) || cp === 0xfe0f || /\s/u.test(chars[i]!)) i += 1;
    else break;
  }
  const rest = chars.slice(i).join("");
  return rest ? `${ALERT_EMOJI[status]} ${rest}` : ALERT_EMOJI[status];
}

