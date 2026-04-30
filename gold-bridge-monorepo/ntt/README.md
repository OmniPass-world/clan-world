# NTT deployment directory

This directory is where `ntt new` and `ntt init` create `deployment.json`.

`deployment.json` is ignored by git because it is deployment-specific.

Run:

1. `pnpm ntt:init`
2. `pnpm ntt:overrides`
3. `pnpm ntt:add-solana`
4. `pnpm ntt:add-base`
5. Edit rate limits.
6. `pnpm ntt:push`
