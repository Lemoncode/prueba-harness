# PRD: Monorepo (pnpm + Turborepo) e infraestructura local (MongoDB + S3)

**Date**: 2026-10-26
**Mode**: validation
**Status**: completed

## Problem Statement

El repo contiene una app TanStack Start en `front/` gestionada con pnpm (lockfile y
`pnpm-workspace.yaml` propios), y una raíz con un `package.json` + `package-lock.json`
(npm) que solo instala `@lemoncode/lemony`. Se necesita:

1. Convertir el repo en un **monorepo** para poder añadir proyectos hermanos:
   - un paquete de **modelo común de base de datos** (solo el esqueleto; no se modela
     nada en esta fase),
   - un proyecto **seed** que generará la semilla de datos de desarrollo (solo el
     esqueleto; no se escribe semilla en esta fase) y que depende del modelo.
2. Levantar con **docker compose** la infraestructura local de desarrollo: una base de
   datos **MongoDB** y un **emulador de S3** para subir imágenes.

## User Stories

1. Como desarrollador, quiero ejecutar un único `pnpm install` en la raíz e instalar todo
   el workspace (front, seed, db-model, tooling), para no gestionar instalaciones por
   carpeta.
2. Como desarrollador, quiero que `front` siga funcionando igual (`dev`, `build`) tras la
   migración a monorepo, para que la conversión no rompa nada.
3. Como desarrollador, quiero un paquete `@app/db-model` importable desde `front` y desde
   `seed` sin paso de build, para compartir el modelo de datos cuando exista.
4. Como desarrollador, quiero ejecutar `pnpm seed` desde la raíz y que el proyecto seed
   arranque (importando `@app/db-model`) y termine con éxito, para tener el punto de
   entrada listo para la semilla futura.
5. Como desarrollador, quiero ejecutar `pnpm infra:up` y tener MongoDB y un S3 local
   sanos (healthchecks en verde), con el bucket de imágenes ya creado y de lectura
   pública, para poder subir y servir imágenes en local sin pasos manuales.
6. Como desarrollador, quiero `pnpm infra:down` para parar la infraestructura sin perder
   los datos (volúmenes persistentes).
7. Como desarrollador, quiero copiar `.env.example` a `.env` y tener todos los valores de
   desarrollo (credenciales, puertos y variables de conexión), pudiendo cambiar puertos
   si chocan con otros servicios.
8. Como desarrollador, quiero ejecutar a nivel de raíz `typecheck` y `test` vía Turbo
   sobre todos los paquetes, para verificar el monorepo con un solo comando.

## Product / UX Decisions

- **Experiencia de dev "un comando"**: scripts en la raíz (`pnpm infra:up`,
  `pnpm infra:down`, `pnpm seed`, más las tareas de Turbo) — porque reduce la fricción de
  onboarding.
- **Bucket listo al arrancar y público en lectura**: las imágenes se pueden servir por URL
  directa en dev, sin presigned URLs — el usuario lo prefiere por comodidad en desarrollo,
  aceptando que se aleja de producción.

## Technical Decisions

- **Gestor del monorepo**: pnpm workspaces + **Turborepo** (orquestación de tareas y caché).
- **Layout** (en la raíz):
  - `front/` — la app TanStack Start existente (se queda en su sitio, sin mover).
  - `seed/` — proyecto seed (ejecutable).
  - `packages/db-model/` — modelo común de BBDD (librería).
  - Globs de workspace: `front`, `seed`, `packages/*`.
- **Nombres de paquete**: scope `@app/*` → `@app/front`, `@app/seed`, `@app/db-model`.
- **Consumo de `@app/db-model`**: *internal package* (Just-in-Time) — exporta TypeScript
  sin compilar (`"exports": "./src/index.ts"`); Vite (front) y tsx (seed) lo transpilan.
  Sin build ni watch.
- **Dependencias**: tanto `seed` como `front` declaran `@app/db-model: workspace:*`. La
  integración se demuestra con un import trivial de un placeholder exportado por
  db-model (constante o tipo).
- **Librería de acceso a Mongo**: **diferida** a la fase de modelado. `db-model` nace sin
  dependencias de BBDD; solo exporta un placeholder.
- **Ejecución de seed**: `tsx` sobre `seed/src/index.ts`; script `seed` en el paquete y
  alias `pnpm seed` en la raíz. En esta fase solo importa db-model, imprime un log y sale
  con código 0.
- **TypeScript**: `tsconfig.base.json` en la raíz (strict, ES2022, `moduleResolution:
  bundler`, `verbatimModuleSyntax`, etc.) que extienden los tres proyectos; cada uno
  añade lo suyo (front: DOM/JSX/vite types y sus paths `#/*`, `@/*`; seed: tipos de Node).
  Cada paquete expone `typecheck` (`tsc --noEmit`) orquestado por Turbo.
- **Tests**: Vitest en `db-model` y `seed` (front ya trae Vite), con tarea `test` en Turbo.
- **Raíz del repo**:
  - `@lemoncode/lemony` pasa al `package.json` raíz gestionado por pnpm; se elimina
    `package-lock.json`.
  - `pnpm-lock.yaml` y `pnpm-workspace.yaml` suben de `front/` a la raíz (único lockfile),
    conservando `allowBuilds` (esbuild, lightningcss) y migrando el bloque
    `pnpm.onlyBuiltDependencies` de `front/package.json` a la configuración raíz.
  - `packageManager: pnpm@10.19.0` en el `package.json` raíz, `.nvmrc` con `24` y
    `engines.node: ">=24"`.
- **Docker compose** (`docker-compose.yml` en la raíz, valores desde `.env`):
  - **MongoDB**: imagen oficial `mongo:8` (mayor fijado), standalone, usuario root vía
    `MONGO_INITDB_ROOT_USERNAME`/`PASSWORD`, volumen con nombre, healthcheck con
    `mongosh`. Puerto por defecto 27017.
  - **S3**: **Silo (pgsty)**, el fork mantenido de MinIO — imagen `pgsty/minio` con tag de
    release **fijado** (objetivo: `RELEASE.2026-10-18T00-00-00Z`; verificar en Docker Hub el
    nombre y el tag exactos al implementar). Volumen con nombre, healthcheck. Puertos por
    defecto: API 9000, consola 9001.
  - **Init de bucket**: servicio de un solo uso (cliente `mc`) que espera a que S3 esté
    healthy, crea de forma **idempotente** el bucket (`images` por defecto, configurable)
    con política de **lectura anónima pública** y termina.
- **Configuración**: `.env.example` versionado con valores de dev; `.env` ignorado en git.
  Incluye credenciales y puertos de los servicios, y las variables de conexión para
  consumidores futuros: `MONGODB_URI`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`,
  `S3_BUCKET`, `S3_PUBLIC_URL`.
- **Scripts raíz**: `infra:up` (`docker compose up -d`), `infra:down` (`docker compose
  down`, sin borrar volúmenes), `seed`, y `dev`/`build`/`typecheck`/`test` vía `turbo run`.

## Testing Decisions

- **db-model**: smoke test con Vitest — el placeholder exportado existe y tiene el valor o
  tipo esperado.
- **seed**: smoke test con Vitest — el entry importa `@app/db-model` (la resolución del
  workspace funciona) y su función principal termina sin error.
- **front**: verificación mecánica — `typecheck` y `build` pasan con el import de
  `@app/db-model` (prueba que Vite/TanStack Start resuelven el internal package).
- **Monorepo**: `pnpm install` limpio en la raíz; `turbo run typecheck test build` en verde.
- **Infra**: `docker compose up` → mongo y s3 healthy; el init termina con código 0; el
  bucket existe y un objeto subido se puede leer por URL anónima; volver a ejecutar el init
  no falla (idempotencia).

## Out of Scope

- Modelar entidades, colecciones o esquemas en `db-model`.
- Escribir datos de semilla o conectar seed a MongoDB.
- Elegir driver/ODM de Mongo (driver oficial vs Mongoose).
- Que front se conecte a MongoDB o S3, o implemente la subida de imágenes.
- Despliegue o infraestructura de producción; CI.
- UI de administración de Mongo (mongo-express); se puede usar Compass en local.

## Discarded Alternatives

- **pnpm workspaces sin Turbo / npm workspaces**: el usuario prefiere Turbo para
  orquestar; npm obligaría a regenerar el lock de front y pierde el aislamiento de pnpm.
- **`apps/` + `packages/`**: se mantiene `front/` y `seed/` en la raíz para minimizar
  cambios.
- **Scopes `@proyecto-pesado/*`, `@pp/*` o sin scope**: se elige `@app/*`, corto y genérico.
- **db-model compilado a `dist/`**: añade build/watch en dev sin necesidad de publicar.
- **Node nativo (type stripping) o tsc+node para seed**: limitaciones de sintaxis TS o más
  pasos; tsx resuelve el internal package sin config.
- **Imagen `minio/minio` original**: sin builds comunitarios desde oct-2025 y repo
  archivado. **LocalStack**: más pesado de lo necesario. **Chainguard minio**: solo
  `latest`, no se puede fijar versión. **Silo con `latest`**: no reproducible.
- **Bucket manual o privado**: se elige automático y público en lectura.
- **Replica set de un nodo**: no hacen falta transacciones ni change streams aún.
- **Paquete `@app/tsconfig`** o tsconfigs independientes: sobredimensionado o divergente.

## Assumptions

- La imagen de Silo sigue publicándose como `pgsty/minio` y es compatible con el cliente
  `mc` y la API S3 de MinIO (endpoints, políticas de bucket, consola en 9001).
- TanStack Start/Vite 8 resuelven y transpilan un paquete de workspace que exporta `.ts`
  sin configuración adicional.
- Turborepo es compatible con pnpm 10.19 y Node 24.
- El `front` actual compila hoy (`build`) antes de la migración.

## Risks

- **Nombre y tag de la imagen de Silo**: las fuentes no coinciden (renombrado a Silo el
  2026-08-06; Docker Hub sigue como `pgsty/minio`). Si el tag no existe, hará falta una
  discovery para elegir otro.
- **Migrar el lockfile** de `front/` a la raíz puede cambiar versiones resueltas; hay que
  regenerarlo con cuidado y comprobar que front sigue arrancando.
- **Lemony en la raíz bajo pnpm**: el harness se instaló con npm; hay que verificar que sus
  hooks y CLI (`lemony`) siguen funcionando tras el cambio.
- **Bucket público**: comodidad en dev que no debe trasladarse a producción.

## Open Points

- [ ] Elegir driver/ODM de Mongo en la fase de modelado.
- [ ] Definir la estrategia de semilla (datos, idempotencia, reset) en la fase de seed.

## Next Steps

- [ ] Hand off to the Spec Author (`prd-to-spec`) to turn this PRD into a spec.
