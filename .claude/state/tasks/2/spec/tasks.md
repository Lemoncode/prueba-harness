# Tasks — Monorepo (pnpm + Turborepo)

## Group 1 — Raíz a pnpm workspace y lemony _(aísla la migración de gestor y lockfile, difícil de revertir y con riesgo para front y los hooks del harness; cierra con front funcionando igual)_

- [ ] **T1 — Workspace pnpm en la raíz con lockfile único.**
      Borrar `node_modules` de raíz y de `front/`; `git mv` de `front/pnpm-lock.yaml` y
      `front/pnpm-workspace.yaml` a la raíz; globs `front`, `seed`, `packages/*`;
      `onlyBuiltDependencies` migrado desde `front/package.json` (D5); renombrar el importer
      `.` a `front` en el lockfile (D6); `package.json` raíz con `private`, `packageManager`,
      `engines`, devDep `@lemoncode/lemony` ^0.11.0; borrar `package-lock.json`; `.nvmrc`;
      `pnpm install` y luego `pnpm install --frozen-lockfile` limpio en verde (R1, R2, R3, R4, R5, R6, R7)
- [ ] T2 — Verificar lemony bajo pnpm: `node_modules/.bin/lemony` existe y `.claude/hooks/lib/lemony.sh --version` sale con 0 (R8, R9)
- [ ] T3 — Renombrar front a `@app/front` y comprobar que `build` pasa y `dev` sirve `/` con 200; comparar `pnpm ls --depth 0` de front antes/después (R10, R11, R12)

## Group 2 — TypeScript compartido, Turbo y db-model _(trivial y mecánico; agrupa la base de verificación del monorepo y cierra con `pnpm typecheck` / `pnpm test` ejecutables)_

- [ ] T4 — Crear `tsconfig.base.json`, hacer que `front/tsconfig.json` lo extienda y añadir `typecheck` a front, en verde (R13, R22, R23)
- [ ] T5 — Añadir `turbo` y `turbo.json` (D8), scripts raíz `dev`/`build`/`typecheck`/`test` vía `turbo run`, y `.turbo` en `.gitignore` (R25, R26, R29)
- [ ] T6 — Crear `packages/db-model` como internal package con el placeholder (D1), tsconfig, `typecheck` y smoke test Vitest en verde (R14, R15, R22, R23, R24)

## Group 3 — Integración front/seed con db-model _(nueva costura entre paquetes del workspace: prueba que Vite y tsx resuelven el internal package; cierra con `pnpm seed` y el monorepo completo en verde)_

- [ ] T7 — Front depende de `@app/db-model: workspace:*` y lo re-exporta en `router.tsx` (D4); `typecheck` y `build` en verde (R16, R17)
- [ ] T8 — Crear `seed` (`@app/seed`) con `main()` que importa db-model y loguea el placeholder, tsconfig, `typecheck`, script `seed` con tsx y test Vitest de `main` (R16, R18, R19, R21, R22, R23, R24)
- [ ] T9 — Añadir `run(fn)` y el entry `index.ts`; test Vitest del camino de error (stderr + `process.exitCode` 1) (R20)
- [ ] T10 — Alias raíz `pnpm seed` (D9) y verificación final: instalación limpia `--frozen-lockfile`, `pnpm typecheck`, `pnpm test`, `pnpm build`, `pnpm seed` en verde y prueba negativa temporal de tipos que hace fallar `pnpm typecheck` (R3, R6, R26, R27, R28)
