# Requirements — Monorepo (pnpm + Turborepo)

> Source PRD: docs/prds/monorepo-infra-2026-10-26.md
> Alcance: **Part 1 of #1** — monorepo (pnpm workspaces + Turborepo, `front/` + `seed/` +
> `packages/db-model`, scope `@app/*`, `tsconfig.base.json`, Vitest, lemony en la raíz con
> pnpm). La infraestructura local (docker compose MongoDB + Silo S3, `.env.example`,
> scripts `infra:up`/`infra:down`) es la Parte 2 y queda **fuera** de esta spec.

## Workspace raíz e instalación única (historia 1)

- **R1** (ubiquitous): El repositorio shall declarar un workspace pnpm en la raíz
  (`pnpm-workspace.yaml`) cuyos globs sean exactamente `front`, `seed` y `packages/*`.
- **R2** (ubiquitous): El repositorio shall tener un único lockfile, `pnpm-lock.yaml` en la
  raíz; no shall existir `package-lock.json` en la raíz ni `pnpm-lock.yaml` /
  `pnpm-workspace.yaml` dentro de `front/`.
- **R3** (event): When un desarrollador ejecuta `pnpm install` en la raíz sobre un checkout
  limpio (sin `node_modules`), el workspace shall instalar las dependencias de `front`,
  `seed`, `packages/db-model` y del tooling raíz, y terminar con código 0.
- **R4** (ubiquitous): La configuración pnpm de la raíz shall conservar `allowBuilds`
  (`esbuild: true`, `lightningcss: true`) y la lista `onlyBuiltDependencies`
  (`esbuild`, `lightningcss`) migrada desde `front/package.json`, que deja de contener el
  bloque `pnpm`.
- **R5** (ubiquitous): El `package.json` raíz shall declarar `"private": true`,
  `"packageManager": "pnpm@10.19.0"` y `"engines": { "node": ">=24" }`, y el repo shall
  incluir `.nvmrc` con el contenido `24`.
- **R6** (event): When se ejecuta `pnpm install --frozen-lockfile` en la raíz sobre un
  checkout limpio, la instalación shall terminar con código 0 (el lockfile versionado es
  coherente con todos los `package.json` del workspace).

### Acceptance criteria

- [ ] `git ls-files` muestra `pnpm-lock.yaml` y `pnpm-workspace.yaml` en la raíz y ninguno en `front/`; no hay `package-lock.json`.
- [ ] `rm -rf node_modules front/node_modules seed/node_modules packages/*/node_modules && pnpm install --frozen-lockfile` termina con 0.
- [ ] `pnpm-workspace.yaml` lista `front`, `seed`, `packages/*` y contiene `allowBuilds` y `onlyBuiltDependencies` con `esbuild` y `lightningcss`.
- [ ] `front/package.json` ya no tiene el campo `pnpm`.
- [ ] `package.json` raíz tiene `private`, `packageManager: pnpm@10.19.0`, `engines.node: ">=24"`; existe `.nvmrc` = `24`.

## Lemony en la raíz bajo pnpm

- **R7** (ubiquitous): El `package.json` raíz shall declarar `@lemoncode/lemony` como
  devDependency gestionada por pnpm, con el mismo rango que hoy (`^0.11.0`).
- **R8** (event): When se ha ejecutado `pnpm install` en la raíz, el lanzador
  `.claude/hooks/lib/lemony.sh` shall resolver el CLI en `node_modules/.bin/lemony` de la
  raíz y ejecutar un subcomando (p. ej. `--version`) con código 0.
- **R9** (unwanted): If tras la migración el CLI `lemony` no resuelve desde
  `node_modules/.bin` de la raíz, then la migración shall considerarse no completada
  (el criterio de aceptación falla) en lugar de depender de una instalación global.

### Acceptance criteria

- [ ] `test -x node_modules/.bin/lemony` es verdadero tras `pnpm install`.
- [ ] `.claude/hooks/lib/lemony.sh --version` imprime `0.11.x` y sale con 0.
- [ ] `.claude/hooks/lib/lemony.sh emit …` (p. ej. el `spec_created` de la plantilla) no falla con 127.

## Front sigue funcionando (historia 2)

- **R10** (ubiquitous): La app TanStack Start shall permanecer en `front/` y su paquete
  shall llamarse `@app/front`.
- **R11** (event): When se ejecuta `pnpm --filter @app/front build` (o `turbo run build`),
  front shall compilar con código 0.
- **R12** (event): When se ejecuta `pnpm --filter @app/front dev`, front shall arrancar el
  servidor de desarrollo en el puerto 3000 y servir la ruta `/` con HTTP 200.
- **R13** (ubiquitous): `front/tsconfig.json` shall extender `../tsconfig.base.json`,
  conservando lo propio de front (libs DOM, `jsx: react-jsx`, `types: ["vite/client"]` y
  los paths `#/*` y `@/*`).

### Acceptance criteria

- [ ] `front/package.json` → `"name": "@app/front"`; scripts `dev`, `build`, `preview`, `generate-routes` intactos.
- [ ] `turbo run build --filter=@app/front` en verde.
- [ ] `pnpm --filter @app/front dev` arranca y `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/` devuelve `200`.

## Paquete `@app/db-model` como internal package (historia 3)

- **R14** (ubiquitous): El paquete `packages/db-model` shall llamarse `@app/db-model`, ser
  `private` y exportar TypeScript sin compilar mediante `"exports": "./src/index.ts"`, sin
  script `build` ni dependencias de base de datos.
- **R15** (ubiquitous): `@app/db-model` shall exportar un placeholder: la constante
  `DB_MODEL_PLACEHOLDER` con el valor literal `'@app/db-model'` y el tipo derivado
  `DbModelPlaceholder`.
- **R16** (ubiquitous): `front` y `seed` shall declarar `"@app/db-model": "workspace:*"` en
  sus dependencias.
- **R17** (event): When se compila front (`build`), Vite/TanStack Start shall resolver y
  transpilar el import de valor de `@app/db-model` sin configuración adicional ni paso de
  build del paquete.

### Acceptance criteria

- [ ] `packages/db-model/package.json` tiene `name`, `private`, `type: module`, `exports: ./src/index.ts` y ningún script `build`.
- [ ] `front/src` contiene un import de valor (no `import type`) de `@app/db-model` en un módulo alcanzable desde el grafo de la app, y `build` pasa.
- [ ] `pnpm why @app/db-model` (o `pnpm ls`) muestra el enlace `workspace` en front y seed.

## Proyecto `seed` ejecutable (historia 4)

- **R18** (ubiquitous): El proyecto `seed/` shall llamarse `@app/seed`, ser `private` y
  tener como entry `seed/src/index.ts`, ejecutado con `tsx` mediante su script `seed`.
- **R19** (event): When un desarrollador ejecuta `pnpm seed` en la raíz, seed shall importar
  `@app/db-model`, imprimir por stdout una línea de log que incluya el valor de
  `DB_MODEL_PLACEHOLDER`, y terminar con código 0.
- **R20** (unwanted): If la función principal de seed lanza o rechaza, then el proceso shall
  imprimir el error por stderr y terminar con código distinto de 0.
- **R21** (ubiquitous): seed shall no conectarse a MongoDB ni escribir datos en esta fase.

### Acceptance criteria

- [ ] `pnpm seed` en la raíz imprime una línea con `@app/db-model` y `echo $?` da `0`.
- [ ] Un test de Vitest prueba que la función principal resuelve sin error importando `@app/db-model`.
- [ ] Un test de Vitest prueba que un fallo en la función principal produce código de salida ≠ 0 (o que el manejador de errores fija `process.exitCode` ≠ 0).

## TypeScript compartido y verificación con Turbo (historia 8)

- **R22** (ubiquitous): La raíz shall contener `tsconfig.base.json` con las opciones
  comunes (`strict`, `target: ES2022`, `module: ESNext`, `moduleResolution: bundler`,
  `verbatimModuleSyntax`, `skipLibCheck`, `noEmit`, `noUnusedLocals`,
  `noUnusedParameters`, `noFallthroughCasesInSwitch`, `noUncheckedSideEffectImports`), y
  `front`, `seed` y `db-model` shall extenderlo.
- **R23** (ubiquitous): `front`, `seed` y `db-model` shall exponer cada uno un script
  `typecheck` (`tsc --noEmit`).
- **R24** (ubiquitous): `seed` y `db-model` shall exponer un script `test` que ejecute
  Vitest en modo no interactivo (`vitest run`).
- **R25** (ubiquitous): La raíz shall declarar `turbo` como devDependency y un `turbo.json`
  con las tareas `build`, `dev`, `typecheck` y `test`, siendo `dev` no cacheable y
  persistente.
- **R26** (ubiquitous): El `package.json` raíz shall exponer los scripts `dev`, `build`,
  `typecheck` y `test` como `turbo run <tarea>`, y `seed` como alias que ejecuta el script
  `seed` de `@app/seed`.
- **R27** (event): When se ejecuta `pnpm turbo run typecheck test build` en la raíz tras una
  instalación limpia, todas las tareas shall terminar en verde.
- **R28** (unwanted): If un paquete contiene un error de tipos o un test falla, then la tarea
  correspondiente de Turbo (`typecheck` / `test`) shall fallar y el comando raíz shall
  terminar con código distinto de 0.
- **R29** (ubiquitous): `.gitignore` de la raíz shall ignorar la caché local de Turbo
  (`.turbo`).

### Acceptance criteria

- [ ] `pnpm typecheck`, `pnpm test` y `pnpm build` en la raíz terminan con 0.
- [ ] Introducir temporalmente un error de tipos en `packages/db-model/src/index.ts` hace que `pnpm typecheck` termine ≠ 0 (comprobado y revertido).
- [ ] `db-model` tiene un smoke test Vitest que comprueba el valor de `DB_MODEL_PLACEHOLDER`.
- [ ] `git status` no muestra `.turbo/` tras ejecutar las tareas.
