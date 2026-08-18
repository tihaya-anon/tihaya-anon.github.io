# Repository Guidelines

## Featured images

- Do not create or edit content-bundle `featured.svg` files manually.
- Generate them with `node scripts/generate-featured.mjs <content-bundle-directory> [seed]`.

## Visualizations

- Match visualizations to the document's reading flow. Prefer vertical Mermaid
  diagrams (`flowchart TB` or `flowchart TD`) so the diagram progresses with the
  document stream; use another direction only when the relationship requires it.
