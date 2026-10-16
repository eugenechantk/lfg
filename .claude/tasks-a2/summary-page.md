---
title: Tasks A2 redesign, built and verified
subtitle: Phone and Mac, each screen checked against its design board by an independent verifier
lang: en
cols: 3
---
The phone and the Mac now have the whole task flow: list, task view, edit form, and edit with chat. Every screen passed an independent design check. The code is committed, both servers run it, and TestFlight build 202610151935 is in beta testing.

## A Verdicts by screen {span=2}
| Screen | Boards | Rounds | Verdict |
|---|---|---|---|
| Phone list | tA2d-list | 4 | ok PASS |
| Phone task view (6 states) | tA2d-detail, -failed, -input | 4 | ok PASS |
| Phone edit form (14 variants) | tA2d-edit* | 4 | ok PASS |
| Phone chat sheet | tA2d-chat | 4 | ok PASS |
| Mac list, task view, edit (14 variants) | dA2-* | 7 | ok PASS |
| Phone final regression | all phone boards | 2 | ok PASS |

## B Needs you {meta="3 items"}
```callout info Left for you
- Click Deny on the "lfg would like to record this computer's screen" prompt on the Pro.
- Install TestFlight build 202610151935 when it reaches your phone.
```
## C How each round worked {span=2}
```flow LR
(Build) -> Verifier: app + board
Verifier -> {Deltas?}
{Deltas?} -> Fix: yes
Fix -> (Build)
{Deltas?} -> *PASS: no
```
The verifier rendered each board in Chrome, drove the app on its own simulator, and measured both. It never saw what I had changed.

## D Behaviour checked live
| Check | Result |
|---|---|
| Answer a waiting run in place | ok card reads "Running again" |
| Retry now after a failure | ok card reads "Retrying now" |
| Pause and Resume | ok |
| Chat change saves and shows a card | ok "Saved · 3 changes" |
| Ask to fix sends its question | ok model switched by the agent |
| Edit chats stay out of Sessions | ok phone and Mac |
| Existing schedules reopen unchanged | ok 16 round-trip cases |
| Mac opens chat and answers in iTerm | warn needs the new server |

## E Bugs found and fixed
- An existing "every day, 5 times" task opened as Daily. Saving would have turned it into cron and reset its run count.
- A chat-saved Tue–Fri schedule opened as Custom instead of Weekly.
- The chat's Saved card landed above the agent's reply.
- Failed runs said "no session started" twice.
- A closed edit chat came back under closed Sessions. The server now tags it from the task's chat history.

## F Decisions made on the way
- **Mac toolbar** follows the board between 360 and 499 pt: a badged switcher, plus search and + buttons. Other widths keep the earlier fold.
- **No mic** in the chat composer. iOS cannot start keyboard dictation from a button.
- **Model row** kept in the phone form, beyond the board.
- **Task chips** keep raw model ids, as on the boards; the change card shows names ("GPT-6 Astra").

## G Follow-ups {span=2}
| Item | Why it waits |
|---|---|
| lfg does not show background agents | warn sessions look idle while a verifier runs |
| Keyboard-up chat layout | warn the simulator has no on-screen keyboard |

## H Tests
```kv cols=2
Server: 111 pass
Swift (LFGCore): 969 pass
Desktop checks: 183 pass
Toolbar fit 180–1200 pt: no item dropped
```
