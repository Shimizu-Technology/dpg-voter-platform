# Shimizu Frontend Design Skill

> **Purpose:** AI steering document for generating distinctive, production-grade frontend interfaces.
> **Use:** Load this into context when doing frontend/UI work with Claude, Cursor, or other AI tools.
> **Companion:** See `FRONTEND_DESIGN_GUIDE.md` for detailed implementation patterns and code examples.

---

## Design Thinking (Before Coding)

Before writing ANY frontend code, answer these questions:

1. **Purpose:** What problem does this interface solve? Who uses it?
2. **Tone:** Pick ONE aesthetic and commit fully:
   - Brutally minimal, maximalist chaos, retro-futuristic, organic/natural
   - Luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw
   - Art deco/geometric, soft/pastel, industrial/utilitarian
3. **Constraints:** Framework, performance targets, accessibility requirements
4. **Differentiation:** What makes this UNFORGETTABLE? What's the ONE thing someone will remember?

**CRITICAL:** Choose a clear direction and execute with precision. Bold maximalism and refined minimalism both work — **the key is intentionality, not intensity.** Mediocre design hedges. Great design commits.

---

## Shimizu Hard Rules

### No Emojis — SVGs Only
**NEVER use emoji characters in UI.** They render inconsistently across platforms.
- ✅ Use: `lucide-react`, `heroicons`, or custom SVG icons
- ❌ Never: `<span>🎉</span>` or emoji in buttons, labels, headings, nav

### Dark Mode Done Right
- Background: NEVER pure `#000000` — use `#0a0a0b` or `#09090b`
- Text: NEVER pure `#ffffff` — use `#ececec` or `#e5e5e5`
- Elevation = lighter surfaces (opposite of light mode)

---

## The Blacklist (NEVER Use)

**Fonts:**
- ❌ Inter, Roboto, Arial, system-ui — generic, overused
- ✅ Instead: Satoshi, Cabinet Grotesk, Clash Display, Geist, Space Grotesk, Sora

**Colors:**
- ❌ Purple-to-blue gradients on white — the #1 AI slop signal
- ❌ Tailwind's default `blue-500` as primary color
- ✅ Instead: Custom brand palette with intentional accent color

**Layouts:**
- ❌ Hero → 3-column features → testimonials → CTA (every template ever)
- ✅ Instead: Bento grid, asymmetric splits, editorial layouts, overlapping elements

**Components:**
- ❌ `rounded-lg` on literally everything
- ❌ Default Tailwind shadows unchanged
- ✅ Instead: Vary radius intentionally, use tinted shadows or none

**Patterns:**
- ❌ Cookie-cutter card grids with identical sizing
- ❌ Generic hero with centered text and two buttons
- ✅ Instead: Unexpected layouts, asymmetry, grid-breaking elements

---

## What TO Do

### Typography
- Choose fonts that are **distinctive and characterful**
- Pair a bold display font with a refined body font
- Use a consistent type scale (not random sizes)
- Generous line-height for body text (1.6-1.75)
- Constrain paragraph width (~65-75 characters)

### Color & Theme
- Commit to ONE cohesive aesthetic
- Use CSS variables for consistency
- Dominant color with sharp accents > timid, evenly-distributed palettes
- Add warmth to neutrals (never pure gray)

### Motion & Animation
- Every animation needs a PURPOSE (guide attention, show relationships, add delight)
- Fast is better than slow (200-400ms for most interactions)
- Always use easing — never linear
- One orchestrated entrance > scattered micro-interactions
- High-impact moments: page load reveals, hover states that surprise

### Spatial Composition
- Unexpected layouts, asymmetry, overlap
- Diagonal flow, grid-breaking elements
- Generous negative space OR controlled density (not in-between)
- Sections should BREATHE

### Atmosphere & Texture
- Add depth: gradient meshes, noise textures, geometric patterns
- Layered transparencies, dramatic shadows, decorative elements
- Grain overlays for photography
- Custom cursor effects for special interactions

---

## The 5 Variations Technique

When generating designs, create **5 distinct variations** in one pass:

```
Create 5 different [component/page] designs. Each should be:
- Creative and unique from all the others
- Following a different aesthetic direction
- Hosted on /1, /2, /3, /4, and /5 respectively
```

This forces creativity because you're aware of all 5 and must make each genuinely different.

**After generating:** Pick the 1-2 best, explain WHAT you liked about them, then iterate with 5 more variations based on that feedback.

---

## Quality Bar

The output should be:
- **Production-grade:** Real, working code — not pseudocode
- **Visually striking:** Someone should pause and notice
- **Cohesive:** Clear aesthetic point-of-view throughout
- **Meticulous:** Every detail considered — spacing, alignment, transitions

---

## Final Reminder

> **Interpret creatively. Make unexpected choices. No design should be the same.**
> 
> Vary between light and dark themes, different fonts, different aesthetics.
> NEVER converge on common, safe choices.
> 
> Claude is capable of extraordinary creative work. Don't hold back.
> Show what can truly be created when committing fully to a distinctive vision.
