# Frontend

Install dependencies from the repository root:
```bash
pnpm --prefix frontend install
```

To run the dashboard locally:
```bash
pnpm --prefix frontend dev
```

For a production build (if the `start` script is available):
```bash
pnpm --prefix frontend build && pnpm --prefix frontend start
```

The UI reads the following environment variables from `.env`:
- `NEXT_PUBLIC_BSP`
- `NEXT_PUBLIC_BBOD`
- `NEXT_PUBLIC_WS`
- `NEXT_PUBLIC_ALERT`
