# Design — Monorepo (pnpm + Turborepo)

> Part 1 of #1. La Parte 2 (docker compose, `.env.example`, `infra:up`/`infra:down`) queda
> fuera; sus decisiones del PRD son restricciones, no alcance.

## Approach

Se convierte la raíz en un workspace pnpm orquestado por Turborepo sin mover `front/`: el
lockfile y `pnpm-workspace.yaml` de `front/` suben a la raíz (único lockfile), la raíz pasa
de npm a pnpm (lemony incluido, se borra `package-lock.json`), y se añaden dos proyectos
hermanos: `packages/db-model` como *internal package* JIT (exporta `./src/index.ts`, sin
build) y `seed/` ejecutado con `tsx`. Un `tsconfig.base.json` raíz concentra las opciones
comunes que hoy viven en `front/tsconfig.json`; cada proyecto lo extiende y expone
`typecheck`; `seed` y `db-model` añaden Vitest. La integración se demuestra con un
placeholder exportado por db-model e importado (como valor) por front y seed. Se verifica
explícitamente que el lanzador de lemony sigue resolviendo el CLI desde
`node_modules/.bin` de la raíz.

## Spec gate decisions

- **D1 — Placeholder de db-model: `export const DB_MODEL_PLACEHOLDER = '@app/db-model' as const` y `export type DbModelPlaceholder = typeof DB_MODEL_PLACEHOLDER`.** [preference]
  El PRD solo pide "una constante o tipo". Se exportan ambos: la constante es un valor (lo
  que necesita front para que Vite tenga que resolver el paquete) y el tipo cubre el caso
  "tipo". El nombre deja claro que es temporal; se sustituirá en la fase de modelado.
- **D2 — Versiones del tooling nuevo: `turbo` ^2, `vitest` ^4, `tsx` ^4, `typescript` alineado con front (^6.0.2), `@types/node` ^24 en seed.** [preference]
  El PRD no fija versiones. Se toma la última mayor estable de cada una; `@types/node` ^24
  casa con Node 24 (front conserva su `^22` para no tocar lo que ya funciona). Si alguna
  mayor no soporta Node 24 / pnpm 10.19 al implementar, es una discovery (T5).
- **D3 — `seed` se parte en `main()` (lógica) y `run(fn)` (manejo de errores y código de salida), y se añade el camino de error R20.** [open]
  El PRD solo exige "importa db-model, imprime un log y sale con 0". Para que el smoke test
  pueda llamar a la función principal sin efectos de proceso, y para que un fallo futuro de
  la semilla no termine con 0 en silencio, `index.ts` solo hace `run(main)`. Alternativa
  descartada: lógica top-level en `index.ts` (no testeable sin lanzar un proceso).
- **D4 — Front importa el placeholder con un re-export de valor en `front/src/router.tsx`: `export { DB_MODEL_PLACEHOLDER } from '@app/db-model'`.** [open]
  Un `import type` lo borra `verbatimModuleSyntax` y Vite nunca resolvería el paquete, así
  que el `build` no probaría nada; un import de valor sin uso choca con `noUnusedLocals`.
  Un re-export en un módulo que siempre está en el grafo (cliente y SSR) obliga a Vite a
  resolver y transpilar el paquete sin cambiar el comportamiento ni la UI. Alternativas:
  usarlo en `__root.tsx` (visible) o en el contexto del router (cambia runtime). Se
  retirará cuando front consuma el modelo real.
- **D5 — `onlyBuiltDependencies` se migra a `pnpm-workspace.yaml` de la raíz (junto a `allowBuilds`), no a un campo `pnpm` del `package.json` raíz.** [open]
  El PRD dice "a la configuración raíz" sin precisar fichero. pnpm 10 lee ambos; se elige
  un único sitio para toda la configuración de pnpm.
- **D6 — El lockfile se migra conservando resoluciones: `git mv front/pnpm-lock.yaml pnpm-lock.yaml`, renombrar el importer `.` a `front` y luego `pnpm install`.** [open]
  Mover y regenerar desde cero podría subir versiones de front dentro de sus rangos (riesgo
  señalado en el PRD). Renombrar el importer hace que pnpm reutilice las resoluciones
  existentes de front; se comprueba comparando `pnpm ls --depth 0` de front antes y
  después. Si pnpm aun así cambia versiones directas de front, se documenta en el PR.
- **D7 — `tsconfig.base.json` contiene las opciones no específicas de entorno de `front/tsconfig.json` (incluido `allowImportingTsExtensions` y `noEmit`); cada proyecto añade `include`, `lib` y `types`; front conserva `jsx`, libs DOM, `vite/client` y paths `#/*`, `@/*`.** [open]
  Concreta el "etc." del PRD. `front` gana un script `typecheck` (`tsc --noEmit`) que hoy
  no tiene (hoy pasa en verde).
- **D8 — `turbo.json`: `build` con `dependsOn: ["^build"]` y `outputs: [".output/**", "dist/**"]`; `typecheck` y `test` sin dependencias; `dev` con `cache: false` y `persistent: true`.** [open]
  db-model es JIT (sin build), así que `typecheck`/`test` no necesitan `^`. `.output/**`
  es la salida de nitro en front; `dist/**` queda para paquetes futuros.
- **D9 — El alias raíz `seed` es `pnpm --filter @app/seed seed`, no una tarea de Turbo.** [open]
  La semilla tendrá efectos laterales (escribir en BBDD); cachearla con Turbo sería
  incorrecto. Los scripts `dev`/`build`/`typecheck`/`test` sí van por `turbo run`.
- **D10 — Se añaden `"private": true` (raíz y los tres paquetes), `"type": "module"` en seed y db-model, y `.turbo` al `.gitignore` raíz.** [open]
  Higiene de monorepo no mencionada en el PRD: evita publicaciones accidentales y que la
  caché de Turbo entre en git.
- **D11 — Verificación de lemony = `test -x node_modules/.bin/lemony` + `.claude/hooks/lib/lemony.sh --version` con código 0.** [open]
  El PRD pide "verificar que hooks y CLI siguen funcionando" sin criterio. El lanzador
  (vendor-owned, no se modifica) resuelve primero `node_modules/.bin/lemony` de la raíz,
  que pnpm crea para devDependencies directas; ese es el camino que usan todos los hooks.

## Files

- `package.json` (raíz) — modified — `private`, `packageManager: pnpm@10.19.0`, `engines.node: ">=24"`, scripts `dev`/`build`/`typecheck`/`test` (`turbo run …`) y `seed`; devDeps `@lemoncode/lemony` ^0.11.0, `turbo`.
- `package-lock.json` — deleted.
- `pnpm-workspace.yaml` — moved desde `front/` — `packages: [front, seed, packages/*]`, `allowBuilds` (esbuild, lightningcss), `onlyBuiltDependencies` (esbuild, lightningcss).
- `pnpm-lock.yaml` — moved desde `front/` y regenerado — único lockfile.
- `.nvmrc` — created — `24`.
- `.gitignore` — modified — añade `.turbo` (fuera del bloque `# BEGIN lemony … # END lemony`).
- `turbo.json` — created — tareas según D8.
- `tsconfig.base.json` — created — opciones comunes (R22, D7).
- `front/package.json` — modified — `name: @app/front`, script `typecheck`, dep `@app/db-model: workspace:*`, sin bloque `pnpm`.
- `front/tsconfig.json` — modified — `extends: ../tsconfig.base.json` + lo propio de front.
- `front/src/router.tsx` — modified — re-export del placeholder (D4).
- `packages/db-model/package.json` — created — `@app/db-model`, `private`, `type: module`, `exports: ./src/index.ts`, scripts `typecheck`, `test`; devDeps `typescript`, `vitest`.
- `packages/db-model/tsconfig.json` — created — extiende la base; `include: ["src"]`, `lib: ["ES2022"]`.
- `packages/db-model/src/index.ts` — created — placeholder (D1).
- `packages/db-model/src/index.test.ts` — created — smoke test.
- `seed/package.json` — created — `@app/seed`, `private`, `type: module`, scripts `seed` (`tsx src/index.ts`), `typecheck`, `test`; dep `@app/db-model: workspace:*`; devDeps `tsx`, `typescript`, `vitest`, `@types/node`.
- `seed/tsconfig.json` — created — extiende la base; `include: ["src"]`, `lib: ["ES2022"]`, `types: ["node"]`.
- `seed/src/main.ts` — created — `main()`.
- `seed/src/run.ts` — created — `run(fn)`.
- `seed/src/index.ts` — created — entry: `run(main)`.
- `seed/src/main.test.ts`, `seed/src/run.test.ts` — created — smoke tests.

## Functions / interfaces

- `DB_MODEL_PLACEHOLDER: '@app/db-model'` y `type DbModelPlaceholder` (`@app/db-model`) — placeholder exportado; serve R15, R17, R19.
- `main(log?: (line: string) => void): Promise<void>` (`seed/src/main.ts`) — importa `DB_MODEL_PLACEHOLDER` y emite una línea de log que lo contiene (por defecto `console.log`); no toca red ni disco; resuelve sin error. Serve R19, R21.
- `run(fn: () => Promise<void>): Promise<void>` (`seed/src/run.ts`) — espera `fn`; si rechaza, escribe el error en stderr (`console.error`) y fija `process.exitCode = 1`; nunca relanza. Serve R20.
- `seed/src/index.ts` — `await run(main)`; sin otra lógica. Serve R18, R19.

## Edge cases

- `pnpm install` muestra un aviso de engines porque `@lemoncode/lemony` declara `engines.pnpm >=11.5.1` y local es 10.19.0 → es solo un aviso (engine-strict desactivado por defecto); se acepta. Si pnpm se negara a instalar, discovery T5 (R3, R7).
- pnpm 10.19 puede no reconocer `allowBuilds` (clave de versiones más nuevas) → se conserva tal cual por decisión del PRD; `onlyBuiltDependencies` es lo que pnpm 10 aplica, y debe permitir los postinstall de esbuild y lightningcss (R4).
- `@lemoncode/lemony` se sirve desde GitHub Packages (privado): pnpm usa la misma configuración de registro/autenticación del `~/.npmrc` del usuario que usaba npm. Si pnpm no autentica, discovery (no se añade un `.npmrc` con token al repo) (R7).
- Los `node_modules` instalados por npm en la raíz y los de `front/` se borran antes del primer `pnpm install` para no mezclar layouts (R3).
- `turbo run test` en front: front no tiene script `test`, Turbo lo omite sin error (R27).
- `routeTree.gen.ts` está versionado; `build` no depende de `generate-routes` (R11).
- Error de tipos o test roto en cualquier paquete → la tarea Turbo falla y el comando raíz sale ≠ 0 (R28).
- El fallo en `main` no debe dejar el proceso en 0: `run` fija `process.exitCode = 1` (R20).

## Testing approach

- **db-model (unit, Vitest)**: `DB_MODEL_PLACEHOLDER === '@app/db-model'` (R15).
- **seed (unit, Vitest)**: `main` con un `log` espía resuelve y emite una línea que contiene
  `@app/db-model` — prueba además la resolución del workspace desde seed (R19);
  `run` con una función que rechaza escribe en stderr y deja `process.exitCode` en 1
  (restaurado tras el test) (R20); `run` con una función que resuelve no toca `exitCode`.
- **front (mecánico)**: `typecheck` y `build` en verde con el re-export (R11, R13, R17); dev
  arranca y `/` da 200 (R12). Sin tests unitarios en front: el PRD no los pide.
- **Monorepo (mecánico)**: instalación limpia con `--frozen-lockfile`, `pnpm typecheck test
  build` en verde (R3, R6, R27); prueba negativa temporal de tipos (R28); `pnpm seed`
  sale 0 (R19); `lemony.sh --version` sale 0 (R8).
- No se testea la configuración de Turbo ni de pnpm con tests automáticos: se verifica
  ejecutándola.
