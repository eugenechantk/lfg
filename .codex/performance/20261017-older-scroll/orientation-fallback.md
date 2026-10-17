# Simulator orientation fallback

FlowDeck exposes a two-finger content-rotation gesture, but no device-orientation command. The macOS Accessibility menu provided the missing operation. All app navigation, screenshots, and recordings remain with the independent FlowDeck auditor.

`axdriver doctor` reported Accessibility and Screen Recording granted. The Mac began locked. Password-free `lfg-unlock unlock` completed; protected data stayed sealed.

Before rotation, the Simulator main window belonged to another simulator. AXPress selected the exact Window menu item `cc-901ded2b-ipad-mini5 – iOS 26.3`. A new window inventory confirmed that exact window was main. AXPress on `Rotate Left` matched one enabled menu item and returned `pressed: true`. The mini5 outer window changed from 882×1261 to 1208×935. Other simulators were not rotated.

The auditor records and independently checks the resulting app dimensions, rich-text layout, and reverse rotation. No mouse movement or global keyboard input is used.

Cleanup completed: AXPress Rotate Right restored mini5 portrait. The auditor independently confirmed 768×1024 app dimensions and correct scrolling after rotation. AXPress restored the original Simulator main window, `cc-75bfba6d – iOS 26.3`; the window inventory confirmed it was main. `lfg-unlock lock` returned exit 0 and locked the Mac.
