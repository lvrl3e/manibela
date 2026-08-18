# ManibelApp Admin

The admin website for [ManibelApp](../README.md) — verifies commuter IDs,
manages driver accounts, reviews flagged trips and complaints, and
monitors live jeepney/passenger activity on the Pasig–Quiapo route.

React 19 + TypeScript, built with Vite, styled with Tailwind CSS 4. Talks
to the shared backend in [`../backend`](../backend) — see the root
[README](../README.md) and [COMMANDS.md](../COMMANDS.md) for how to run
everything together.

## Commands

```bash
npm install
npm run dev      # dev server at http://localhost:5173
npm run build    # typecheck (tsc -b) + production build
npm run lint     # oxlint
npm run preview  # preview a production build locally
```
