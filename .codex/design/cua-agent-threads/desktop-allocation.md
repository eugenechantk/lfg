# Desktop allocation and host memory reserve

Design requirement from Eugene: starting another Space must leave at least 4 GiB of available host memory. This is an admission rule to implement, not an existing backend guarantee.

## Allocation flow

1. The agent requests a desktop only when its next action needs one. API, MCP and file work can proceed without a desktop when supported.
2. Atomically acquire a compatible idle desktop if one is available. Compatibility includes host files, account access and runtime requirements. A desktop with a human controller or a pending sign-in is occupied.
3. If every compatible desktop is occupied, check capacity on an eligible host. Never interrupt the current controller to make room.
4. Under one host allocation lock, read available physical memory, memory pressure, VM capacity and pending startup reservations. Do not treat swap or merely unused pages as available RAM. Missing or stale measurements mean queue, not start.
5. Admit a new desktop only if:

   available host memory - pending reservations - estimated additional peak memory >= 4 GiB

   The estimate covers startup peaks and the configured workload budget. Include shared Linux VM startup if it is stopped, or required VM expansion if it is running. Do not charge the existing VM's memory twice. Also enforce the VM's own free capacity, the container budget and the desktop-count limit.
6. Record the reservation before releasing the lock. Start the desktop and wait for health and tool readiness. Recheck before marking it available to the agent. Reconcile the reservation against measured usage; release it on success or failure without double-counting running usage.
7. If admission fails, queue the desktop action. Show an inline message explaining that LFG is keeping 4 GB free on the host. Independent work continues. Retry on desktop release, memory recovery or host availability. Order eligible requests fairly; do not repeatedly bypass an older compatible request.

## Example

With 7 GiB available and an estimated 2 GiB additional peak, a startup leaves 5 GiB and may proceed. With 5 GiB available, the same startup would leave 3 GiB and must wait.

## Runtime boundary

This check cannot guarantee that other host applications will leave 4 GiB free later. Enforce desktop memory limits, monitor host pressure, and stop admitting new desktops when the reserve is breached. Do not kill active desktops or discard work automatically. Resuming a stopped desktop must pass the same admission check.

## UI

Keep the agent thread and composer available while waiting. Explain the reason inline: “Waiting for a desktop. Pro needs to keep 4 GB free.” Do not make users choose or create a Space. The pool view can show the host reserve and the waiting agent, with no new primary navigation.
