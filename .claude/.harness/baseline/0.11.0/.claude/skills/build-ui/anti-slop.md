# Anti-slop — building the design's point of view into the code

Load this before generating any visual UI. The `ui-handoff.md` already chose the
**direction** (the dials, the tone, the brand references); this resource is about
**executing** that direction in code without collapsing back to the generic defaults a
model reaches for unprompted.

## The failure mode to avoid

"AI slop" is what UI looks like when no decision was made: the safe system font, the
predictable purple-to-blue gradient, the evenly-spaced card grid with no focal point, the
centred hero with a heading and two buttons, borders and shadows on everything. None of it
is _wrong_ — it is just **average**, and average reads as nobody-cared. The handoff set a
point of view; your job is to make every screen carry it. When you catch yourself
reaching for the obvious default, stop and ask what the dials in §2 actually asked for.

Match the **variance dial**: at low variance, restraint and convention are correct — do
not manufacture flair the handoff didn't ask for. At medium/high, the generic default is
a failure. Calibrate to the dial, don't apply maximum expression everywhere.

## Typography

- **Establish a real scale, not ad-hoc sizes.** Sizes, weights and line-heights come from
  the token scale; a screen using five arbitrary pixel sizes has no hierarchy.
- **Hierarchy through contrast, not just size.** Weight, colour, letter-spacing and space
  separate levels — a heading is not merely "bigger body text".
- **Line length and leading are deliberate.** Long-form text wants ~60–75 characters and
  generous line-height; dense UI labels want tight leading. One global line-height for
  everything is a tell.
- **Type carries the brand.** If the direction is expressive, the typeface and its
  treatment are where it shows first — not a decorative afterthought bolted on at the end.

## Colour

- **Drive colour from semantic tokens, always.** No raw hex in components. Reach for the
  intent (`color.surface`, `color.text.muted`), so a theme change is a token change.
- **Restraint reads as intentional.** A tight, deliberate palette with one confident
  accent beats a rainbow. Most of a good UI is neutrals; colour earns attention where it
  carries meaning (state, emphasis, brand).
- **Contrast is a design tool, not only an a11y gate.** Use it to direct the eye — but the
  floor is the a11y requirement (see [accessibility.md](./accessibility.md)).
- **The gradient/glow reflex.** A gradient is a choice, not a default. If you add one, it
  should be motivated by the direction, not reflexively dropped behind every hero.

## Space, layout and hierarchy

- **Spacing comes from the scale and creates rhythm.** Consistent, intentional spacing is
  most of what makes a UI feel designed. Uniform padding everywhere flattens hierarchy;
  vary space to group and separate.
- **Every screen has a focal point.** Decide what the eye hits first and build the layout
  to deliver it. A grid of equal-weight cards with no anchor is the canonical slop layout.
- **Use alignment and an underlying grid.** Things line up on purpose; deliberate
  asymmetry is a choice, accidental misalignment is noise.
- **Density follows the dial.** Airy vs compact is a decision in §2 — honour it. Don't
  pad an expert, data-dense tool into a marketing page or cram a spacious landing page.
- **Whitespace is structure, not leftover.** Generous space around a focal element is how
  you signal importance; reaching to fill every region is a reflex to resist.

## Depth, borders and surface

- **Don't outline everything.** Borders-and-shadow on every element is slop. Separate with
  space and surface colour first; reach for a border or elevation only where it carries
  meaning (an interactive boundary, a raised layer).
- **Elevation is a system, not per-component guesswork.** Shadows come from the token
  scale and map to a consistent sense of layering, not random blur values.
- **Radius and stroke are part of the voice.** Sharp vs soft corners, hairline vs heavy
  strokes — keep them consistent and aligned to the direction, from tokens.

## Motion as craft

Motion appetite is the **motion dial** in §2 — respect it; do not animate a low-motion
brief, and don't leave a high-motion one static.

- **Motion has a job.** Animate to show a relationship — where a thing came from, what
  changed, what is loading. Decoration-only motion is noise.
- **Fast and eased.** UI transitions are short (typically ~150–250ms) with easing that
  matches the feel; linear, slow, or bouncy-by-default reads as amateur.
- **Animate cheap properties.** Prefer transform and opacity; animating layout-affecting
  properties janks.
- **Respect `prefers-reduced-motion`.** Provide a reduced or no-motion path — this is both
  craft and an accessibility requirement (see [accessibility.md](./accessibility.md)).

## Responsive as craft

- **Design the breakpoints, don't just let things reflow.** Decide what actually changes
  per the handoff's §7 — a layout shift, a nav pattern, a density change — rather than
  shrinking the desktop layout until it breaks.
- **Touch and pointer differ.** Targets, hover affordances and spacing adapt to the input,
  not just the viewport width.
- **No horizontal scroll, no clipped content.** The small-screen state is a first-class
  design, including the empty/loading/error states from §6.

## Component and state completeness

- **Build every state the handoff names.** Empty, loading, error, success and edge content
  (§6) are part of the design — a component that only renders the happy path is unfinished.
- **Reuse the design system; don't reinvent primitives.** Match existing components and
  their variants. A bespoke one-off button next to the system button is slop.
- **Microcopy is the words in the handoff (§10), verbatim and in voice.** Don't substitute
  generic "Submit" / "Something went wrong" when the handoff specified the real copy.

## The point-of-view test

Before you call a screen done, ask: **could this have been generated for any product?** If
yes, it has no point of view — return to the dials and the brand references in §2 and make
the deliberate choice the handoff asked for. A design that someone could not have
articulated alone is the bar; the average is the failure.
