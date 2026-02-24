---
name: impeccable
description: |
  Design skills for AI coding tools. Create distinctive, production-grade frontend interfaces
  that avoid generic "AI slop" aesthetics. Includes 7 reference guides and 17 design commands.
  Use when building web components, pages, artifacts, posters, or applications.
  Keywords: frontend, design, UI, UX, typography, color, motion, interaction, responsive, audit, polish
tags: [design, frontend, ui, ux, typography, color, motion, accessibility]
allowed-tools:
  - Bash(npx:*)
  - Read
  - Write
---

# Impeccable - Design Skills for AI Coding Tools

The vocabulary you didn't know you needed. 1 skill, 17 commands, and curated anti-patterns for impeccable frontend design.

Based on [Impeccable](https://impeccable.style) by Paul Bakaus, building on Anthropic's frontend-design skill.

## Quick Reference

### Commands (prefix with /i- to avoid conflicts)

| Command | What it does |
|---------|--------------|
| `/i-teach-impeccable` | One-time setup: gather design context, save to config |
| `/i-audit` | Technical quality checks (a11y, performance, responsive) |
| `/i-critique` | UX design review: hierarchy, clarity, emotional resonance |
| `/i-normalize` | Align with design system standards |
| `/i-polish` | Final pass before shipping |
| `/i-simplify` | Strip to essence |
| `/i-clarify` | Improve unclear UX copy |
| `/i-optimize` | Performance improvements |
| `/i-harden` | Error handling, i18n, edge cases |
| `/i-animate` | Add purposeful motion |
| `/i-colorize` | Introduce strategic color |
| `/i-bolder` | Amplify boring designs |
| `/i-quieter` | Tone down overly bold designs |
| `/i-delight` | Add moments of joy |
| `/i-extract` | Pull into reusable components |
| `/i-adapt` | Adapt for different devices |
| `/i-onboard` | Design onboarding flows |

## Design Direction Framework

Commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian
- **Constraints**: Technical requirements (framework, performance, accessibility)
- **Differentiation**: What makes this UNFORGETTABLE?

## Reference Guides

→ [typography.md](reference/typography.md) - Type systems, font pairing, modular scales
→ [color-and-contrast.md](reference/color-and-contrast.md) - OKLCH, tinted neutrals, dark mode
→ [spatial-design.md](reference/spatial-design.md) - Spacing systems, grids, visual hierarchy
→ [motion-design.md](reference/motion-design.md) - Easing curves, staggering, reduced motion
→ [interaction-design.md](reference/interaction-design.md) - Forms, focus states, loading patterns
→ [responsive-design.md](reference/responsive-design.md) - Mobile-first, fluid design, container queries
→ [ux-writing.md](reference/ux-writing.md) - Button labels, error messages, empty states

## Anti-Patterns: The AI Slop Test

**Critical quality check**: If you showed this interface to someone and said "AI made this," would they believe you immediately?

### Typography DON'Ts
- ❌ Use overused fonts: Inter, Roboto, Arial, Open Sans, system defaults
- ❌ Use monospace as lazy shorthand for "technical/developer" vibes
- ❌ Put large icons with rounded corners above every heading

### Color DON'Ts
- ❌ Use gray text on colored backgrounds (use shade of the background)
- ❌ Use pure black (#000) or pure white (#fff) — always tint
- ❌ Use the AI color palette: cyan-on-dark, purple-to-blue gradients, neon accents
- ❌ Use gradient text for "impact" on metrics or headings

### Layout DON'Ts
- ❌ Wrap everything in cards — not everything needs a container
- ❌ Nest cards inside cards — flatten the hierarchy
- ❌ Use identical card grids — same-sized cards repeated endlessly
- ❌ Use the hero metric layout template — big number + small label + gradient
- ❌ Center everything — left-aligned text with asymmetry feels more designed
- ❌ Use the same spacing everywhere — variety creates rhythm

### Visual DON'Ts
- ❌ Use glassmorphism everywhere — blur effects used decoratively
- ❌ Use rounded elements with thick colored border on one side
- ❌ Use sparklines as decoration — tiny charts conveying nothing
- ❌ Use generic drop shadows on rounded rectangles

### Motion DON'Ts
- ❌ Animate layout properties (width, height, padding, margin)
- ❌ Use bounce or elastic easing — feels dated and tacky

### Interaction DON'Ts
- ❌ Repeat the same information — redundant headers, intros
- ❌ Make every button primary — use hierarchy

## Quick Guidelines

### Typography
- ✅ Use modular type scale with fluid sizing (clamp)
- ✅ Vary font weights and sizes for visual hierarchy
- ✅ Use 4-5 sizes max with strong contrast

### Color
- ✅ Use OKLCH for perceptually uniform palettes
- ✅ Tint neutrals toward brand hue (even 0.01 chroma)
- ✅ 60% neutral / 30% secondary / 10% accent

### Layout
- ✅ Create rhythm through varied spacing
- ✅ Use asymmetry and unexpected compositions
- ✅ Break the grid intentionally for emphasis

### Motion
- ✅ Use ease-out-quart/quint/expo for natural deceleration
- ✅ Focus on high-impact moments (page load, reveals)
- ✅ Animate transform and opacity only

### Accessibility
- ✅ 4.5:1 contrast minimum for text
- ✅ 44x44px minimum touch targets
- ✅ Never remove focus ring without replacement
- ✅ Respect prefers-reduced-motion

## Workflow Integration

### With DX Worktrees
1. Create worktree for design exploration
2. Run `/i-audit` on existing components
3. Apply `/i-normalize` to align with system
4. Use `/i-polish` before shipping
5. Merge to main

### With Parallel Agents (dmux)
- Agent A: `/i-audit` → document issues
- Agent B: `/i-critique` → UX review
- Agent C: `/i-simplify` → strip to essence
- Merge findings, apply systematically

## Installation in Projects

```bash
# For Claude Code projects
cp -r ~/agent-skills/extended/impeccable/.claude/* ~/.claude/

# Or project-specific
cp -r ~/agent-skills/extended/impeccable/.claude/* your-project/.claude/
```

## Resources

- Website: https://impeccable.style
- GitHub: https://github.com/pbakaus/impeccable
- Cheatsheet: https://impeccable.style/cheatsheet
- License: Apache 2.0
