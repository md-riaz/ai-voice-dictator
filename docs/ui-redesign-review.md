# UI redesign review: AI Voice Dictator

Reviewed commit: `468af43`

## Product and surface

AI Voice Dictator is a Windows utility, not a dashboard. Its primary surface is **Operate**: the user needs to know whether dictation is ready, trigger or practise it, and understand where the words will go. Settings, history, and statistics are secondary surfaces.

The concept used for the redesign is **Signal Desk**. Dictation passes through a small, calm chain: input, listen, interpret, deliver. The visual anchor is a recording cue and keyboard-command treatment, not an abstract AI sparkle or a fake analytics dashboard.

## Current UI audit

The current product is technically clear and has solid foundations: an obvious left rail, readable labels, a real playground, useful setup, semantic live regions, and contrast-tested theme colors. Its visual problem is composition, not implementation quality.

- Home splits the one task into four equal white cards: playground, paste switch, shortcuts, language.
- The central action, dictating, has less visual weight than configuration.
- Repeated icon + title + description cards create a standard component-library cadence.
- The light blue palette and Material defaults make the app look competent but interchangeable.
- Stats has a three-card KPI row. It is useful data, but it reads as a generic SaaS dashboard before it reads as a personal speech tool.
- The floating HUD uses blurred, 28px-rounded glass with neon state colors. It is legible, but the effect is visually disconnected from the desktop app.

### Anti-slop score, before: 4/10

1. Tech gradient: no.
2. Generic tech hue: **yes**. Blue is the default app accent rather than a product-specific choice.
3. Feature-tile grid: **yes**. The stats KPI row and Home’s equal card sequence trigger it.
4. Accent rail: no.
5. Unearned blur: **yes**, in the floating HUD.
6. Monument stat: no.
7. Icon topper: no.
8. Center stack: no.
9. Default type: **yes**. Typography is inherited Material/system type without an intentional role.
10. Wrong surface: no, but Home weakens its Operate purpose by leading with settings-like cards.

## Three directions explored

### 1. Signal Desk — selected

A compact desktop console for moving speech into text. One large workspace is structured as a signal path: current state, keyboard trigger, editable transcript, delivery choice. A deep ink and paper palette, a restrained recording red, rectangular keycaps, and a thin signal rule create recognition without decoration.

Why it fits: the core interaction is a global shortcut and a live status transition. This direction gives that transition a physical, intelligible place in the interface.

Risk: too technical if every page adopts control-room decoration. Keep History and Setup calm and utilitarian.

### 2. Margin Notes

A writing-tool direction: warm paper, editorial type, and transcript history treated as a notebook margin. The playground is a sheet of text, while controls are annotation tools.

Why it fits: output is language, not audio. It would make reviewing transcripts unusually good.

Why not selected: it understates microphone state and global-keyboard behavior, which are the first-run risks in this product.

### 3. Shortcut Atlas

A keyboard-native direction: high-contrast command chips, a spatial map of shortcut combinations, and a compact activity ledger. It treats the app as a launcher for work happening elsewhere.

Why it fits: the product mostly lives outside its own window.

Why not selected: the keyboard concept risks becoming decorative and less welcoming for people who first need to configure audio and an API key.

## Applied change

The primary Home screen uses Signal Desk:

- A distinct ready/listening/writing state is placed before secondary controls.
- The trigger is rendered as keycaps rather than buried in prose.
- The transcript field becomes the main work area, not one card among many.
- Delivery mode is attached to the transcript, where its consequence is clear.
- Configuration continues below in a collapsed "Voice setup" section, preserving all existing controls.
- Theme colors shift from generic product blue to ink, paper, signal red, and warm brass. No gradients or blur.
- The floating overlay is a crisp status strip, visually part of the same system.

### Anti-slop score, after: 1/10

The remaining point is inherited system typography on platforms without Segoe UI. The composition-specific tells are removed from Home: no equal card sequence, no generic blue, no blur, and the primary Operate surface leads with its operation.

## Verdict

The workflow produces a better result when it changes the composition before decorating components. Here, the useful part was not a prettier color palette. It identified that a dictation utility should lead with operational state and delivery, while the original Home treated configuration blocks as peers.

The workflow is less useful when used as a fixed ritual. Three directions and a critique pass are worth the time for a primary product surface or a redesign. Applying all of it to a small settings form would be ceremony, not value.
