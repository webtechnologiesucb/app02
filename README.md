# NorthwindApi

[![CI/CD](https://github.com/webtechnologiesucb/app02/actions/workflows/ci-cd-pipeline.yml/badge.svg)](https://github.com/webtechnologiesucb/app02/actions/workflows/ci-cd-pipeline.yml)

API REST sobre la base de datos **Northwind** (SQL Server), construida con **ASP.NET Core (.NET 10)**
y **Entity Framework Core (database-first)**. Expone:

- **CRUD** de las entidades de Northwind (Categories, Customers, Employees, Products, Orders, …).
- **Solo lectura** de las **16 vistas** de la base de datos.
- Invocación **explícita y parametrizada** de los **7 procedimientos almacenados**.
- **Dashboard** con métricas de ventas (JSON) y una **página web** de panel.
- **Exportación de reportes a PDF y XLSX**.
- **Swagger UI**, comprobación de **salud** y manejo de errores con **ProblemDetails**.

---

## Estructura de la solución

```
NorthwindApi.slnx
instnwnd.sql                              Script de creación/datos de Northwind
Dockerfile                                Imagen de la API (multi-stage, Kestrel)
docker-compose.yml                        SQL Server 2022 + init de BD + API (desarrollo)
.dockerignore / .env.example              Contexto de build y plantilla de variables
deploy/
  sqlserver/                              Imagen de SQL Server para Koyeb (volumen + init Northwind)
  docker-compose.prod.yml                 Referencia legacy para VPS (no la usa el pipeline)
  deploy.sh                               Referencia legacy de despliegue SSH (no la usa el pipeline)
scripts/init-northwind.sh                 Carga de la base Northwind (CI y local)
docs/database-analysis.md                 Análisis del esquema y los datos
src/
  NorthwindApi.Api/                       Capa web (controllers, middleware, Swagger, dashboard)
  NorthwindApi.Application/               DTOs, modelos, abstracciones, utilidades comunes
  NorthwindApi.Infrastructure/            EF Core (scaffolded), servicios de datos, reportes
tests/
  NorthwindApi.Tests/                     Pruebas unitarias (InMemory) e integración (WebApplicationFactory)
```

Dependencias: `Api → Application + Infrastructure`, `Infrastructure → Application`, `Tests → Api + Infrastructure + Application`.

---

## Requisitos

- **.NET SDK 10** (`net10.0`).
- **SQL Server 2022** (objetivo de producción) o **SQL Server LocalDB** (desarrollo).
- (Opcional, para re-scaffolding) `dotnet tool install --global dotnet-ef --version 10.*`.

---

## Desarrollo local paso a paso

De cero a API corriendo en desarrollo (Windows + LocalDB):

1. **Crear la base de datos** (ver [Puesta en marcha de la base de datos](#puesta-en-marcha-de-la-base-de-datos)):
   `CREATE DATABASE Northwind` y carga de `instnwnd.sql` con `sqlcmd`.
2. **Configurar la cadena de conexión** con User Secrets (ver
   [Configuración de la cadena de conexión](#configuración-de-la-cadena-de-conexión)).
3. **Ejecutar la API**: `dotnet run --project src/NorthwindApi.Api` y abrir
   `http://localhost:5297/swagger` y `http://localhost:5297/health`.
4. **Verificar con pruebas**: `dotnet test` (unitarias en memoria + integración
   contra la base real; ver [Pruebas](#pruebas)).
5. **Extender**: para un nuevo recurso CRUD siga
   [Cómo agregar un nuevo recurso CRUD](#cómo-agregar-un-nuevo-recurso-crud); si cambió
   el esquema, regenere el contexto según
   [EF Core database-first (re-scaffolding)](#ef-core-database-first-re-scaffolding).

---

## Puesta en marcha de la base de datos

El script de origen es `instnwnd.sql` (raíz del repositorio). Con **sqlcmd**:

```powershell
sqlcmd -S "(localdb)\MSSQLLocalDB" -Q "IF DB_ID('Northwind') IS NULL CREATE DATABASE Northwind;"
sqlcmd -S "(localdb)\MSSQLLocalDB" -d Northwind -i instnwnd.sql -f 65001
```

Verificación rápida:

```powershell
sqlcmd -S "(localdb)\MSSQLLocalDB" -d Northwind -Q "SELECT (SELECT COUNT(*) FROM sys.tables) AS tablas, (SELECT COUNT(*) FROM sys.views) AS vistas, (SELECT COUNT(*) FROM sys.procedures) AS proc;"
```

Resultado esperado: **13 tablas, 16 vistas, 7 procedimientos**.

---

## Configuración de la cadena de conexión

La cadena se lee de `ConnectionStrings:Northwind`. **Nunca** se codifican credenciales en el repositorio.

**Desarrollo (User Secrets):**

```powershell
dotnet user-secrets set "ConnectionStrings:Northwind" `
  "Server=(localdb)\MSSQLLocalDB;Database=Northwind;Trusted_Connection=True;TrustServerCertificate=True;MultipleActiveResultSets=True" `
  --project src/NorthwindApi.Api
```

**Producción (variable de entorno):**

```
ConnectionStrings__Northwind = "Server=servidor;Database=Northwind;User Id=app;Password=***;TrustServerCertificate=True"
```

> `appsettings.json` mantiene la clave `ConnectionStrings:Northwind` vacía como plantilla.

---

## Ejecución

```powershell
dotnet run --project src/NorthwindApi.Api
```

| Recurso      | URL                              |
|--------------|----------------------------------|
| Dashboard    | `http://localhost:5297/`         |
| Swagger UI   | `http://localhost:5297/swagger`  |
| Salud        | `http://localhost:5297/health`   |

### Comandos de ejecución

| Comando                                            | Descripción                                          |
| -------------------------------------------------- | ---------------------------------------------------- |
| `dotnet restore`                                   | Restaura los paquetes NuGet de la solución           |
| `dotnet build NorthwindApi.slnx`                   | Compila toda la solución (0 errores / 0 advertencias)|
| `dotnet build -c Release NorthwindApi.slnx`        | Compila en configuración Release                     |
| `dotnet run --project src/NorthwindApi.Api`        | Arranca la API en desarrollo (`:5297`)               |
| `dotnet watch --project src/NorthwindApi.Api run`  | Recompila y reinicia al detectar cambios             |
| `dotnet test`                                      | Ejecuta la suite de pruebas (unitarias + integración)|
| `dotnet clean`                                     | Limpia los artefactos de compilación                 |
| `dotnet publish src/NorthwindApi.Api -c Release`   | Genera artefactos listos para despliegue             |

---

## Desarrollo del backend

### Arquitectura por capas

La solución se divide en tres proyectos con dependencias unidireccionales
(`Api → Application + Infrastructure`, `Infrastructure → Application`):

```
┌──────────────────────────────────────────────────────────────────┐
│ NorthwindApi.Api            (presentación)                        │
│   Controllers · ExceptionHandlingMiddleware · Program.cs          │
│   Swagger · CORS · archivos estáticos (panel) · /health           │
└───────────────┬──────────────────────────────────────────────────┘
                │ depende de
    ┌───────────┴───────────┐
    ▼                       ▼
┌──────────────────────┐  ┌────────────────────────────────────────┐
│ Application          │  │ Infrastructure                          │
│  · DTOs / Modelos    │◄─┤  · EF Core (Data/Generated, scaffold)   │
│  · Abstracciones     │  │  · CrudServiceBase / EntityServices     │
│  · PageQuery, orden  │  │  · ViewService · StoredProcedureService │
│  · Excepciones       │  │  · DashboardService · ReportService     │
└──────────────────────┘  │  · Exportadores PDF / XLSX              │
                          └────────────────────────────────────────┘
```

**Flujo de una petición:**

```
HTTP → Controller → Servicio (abstracción en Application)
     → EF Core / SqlQuery (Infrastructure) → SQL Server
     ↑ ExceptionHandlingMiddleware traduce excepciones a ProblemDetails (400/404/409/500)
```

### Responsabilidades por proyecto

- **`Application`** — independiente de EF y ASP.NET. Define los **DTOs** (records con
  `DataAnnotations` en los *parámetros de constructor*), los **modelos de resultado** (vistas,
  procedimientos, dashboard, reportes), las **abstracciones** (`ICrudService<…>`, `IQueryServices`)
  y utilidades transversales (`PageQuery`, `PagedResult`, `QueryableExtensions`, `Exceptions`).
- **`Infrastructure`** — implementa las abstracciones con EF Core: el `NorthwindContext` y las
  entidades *scaffolded*, los servicios de datos y los exportadores de reportes. Se registra todo
  con `AddInfrastructure(connectionString)`.
- **`Api`** — capa web: controllers delgados que delegan en los servicios, middleware de errores,
  configuración de Swagger/CORS/estáticos y el endpoint de salud.

### EF Core database-first (re-scaffolding)

El contexto y las entidades viven en `src/NorthwindApi.Infrastructure/Data/Generated`. Son
**generados** y **regenerables**: no deben editarse a mano. La fábrica de tiempo de diseño
`NorthwindContextFactory` resuelve la cadena desde `ConnectionStrings__Northwind`,
`NORTHWIND_CONNECTION` o LocalDB por defecto.

Para regenerarlos (por ejemplo tras cambiar la base):

```powershell
$env:ConnectionStrings__Northwind = "Server=(localdb)\MSSQLLocalDB;Database=Northwind;Trusted_Connection=True;TrustServerCertificate=True"
dotnet ef dbcontext scaffold `
  "Microsoft.EntityFrameworkCore.SqlServer" `
  --project src/NorthwindApi.Infrastructure `
  --context NorthwindContext `
  --context-dir Data/Generated `
  --output-dir Data/Generated `
  --use-database-names `
  --no-onconfiguring `
  --force
```

Ajustes aplicados **después** del scaffolding (documentados para repetirlos al regenerar):

- Las **vistas** se mapean como `HasNoKey().ToView(...)`.
- `CustomerCustomerDemo` y `EmployeeTerritories` se modelan como relaciones
  **muchos-a-muchos** (navegaciones de omisión), sin entidad intermedia.
- Tipos nativos preservados: `float`/`real` para `Discount`, `short`/`smallint` para cantidades.

### Patrón CRUD

Cada entidad concreta fija su clave, sus DTOs y su filtro fuertemente tipado extendiendo
`ICrudService<TKey, TDto, TCreate, TUpdate, TFilter>`. La implementación reutiliza
`CrudServiceBase<TEntity, …>`, que aporta el flujo genérico y delega en métodos abstractos del
servicio concreto:

| Método abstracto            | Responsabilidad                                     |
|-----------------------------|-----------------------------------------------------|
| `BuildQuery(filter)`        | consulta de lectura **sin seguimiento**, ya filtrada |
| `ApplySort(query, paging)`  | orden por **lista blanca** de expresiones            |
| `FindByIdAsync(id)`         | búsqueda por clave (conjunto **rastreado**)          |
| `Map(entity)`               | entidad → DTO                                        |
| `ToEntity(dto)` / `Apply(…)`| DTO → entidad (create/update)                        |
| `ValidateReferencesAsync(…)`| validación de FK antes de guardar                    |

Los servicios concretos se declaran en `Infrastructure/Services/EntityServices.cs` y se registran
en `DependencyInjection.RegisterCrudServices`.

### Vistas, procedimientos, dashboard y reportes

- **Vistas** (`ViewService`, 16 vistas): proyecciones de solo lectura con paginación y filtros
  propios. `GET /api/views` devuelve el catálogo.
- **Procedimientos** (`StoredProcedureService`, 7 procedimientos): invocados con
  `Database.SqlQuery<T>` y **FormattableString** (parámetros reales, nunca concatenación de SQL).
- **Dashboard** (`DashboardService`): agregados de ventas (`summary`, `sales-by-month`, `top-*`, …).
- **Reportes** (`ReportService` + exportadores): `PdfReportExporter` (PDFsharp/MigraDoc) y
  `XlsxReportExporter` (ClosedXML), unificados por el compuesto `IReportExporter` (`ReportExporter`).

### Manejo de errores y validación

- La validación por **DataAnnotations** se integra en `InvalidModelStateResponseFactory`
  (`Program.cs`) y devuelve `ValidationProblemDetails` (HTTP 400) de forma consistente.
- `ExceptionHandlingMiddleware` traduce excepciones de dominio y **errores de SQL Server** a
  códigos HTTP: 404 (`NotFoundException`), 409 (`ConflictException`, FK `547`, unicidad `2601/2627`)
  y 500 para el resto, siempre como `ProblemDetails`.

### Cómo agregar un nuevo recurso CRUD

1. **DTOs** en `Application/Dtos`: `XxxDto`, `XxxCreateDto`, `XxxUpdateDto`, `XxxFilter` (records con
   `DataAnnotations` en los parámetros de constructor).
2. **Interfaz** en `Application/Abstractions/ICrudService.cs`: `IXxxService : ICrudService<…>`.
3. **Servicio** en `Infrastructure/Services/EntityServices.cs`, derivando de `CrudServiceBase<…>`.
4. **Registro** en `DependencyInjection.RegisterCrudServices`.
5. **Controller** en `Api/Controllers`, derivando de `CrudControllerBase<…>`.

### Compilación y verificación

```powershell
dotnet build NorthwindApi.slnx     # 0 advertencias / 0 errores
dotnet test                        # suite unitaria + integración
```

---

## API

### Entidades (CRUD)

| Recurso            | Ruta base                         | Clave          |
|--------------------|-----------------------------------|----------------|
| Categorías         | `/api/categories`                 | `int`          |
| Transportistas     | `/api/shippers`                   | `int`          |
| Proveedores        | `/api/suppliers`                  | `int`          |
| Clientes           | `/api/customers`                  | `string(5)`    |
| Empleados          | `/api/employees`                  | `int`          |
| Productos          | `/api/products`                   | `int`          |
| Pedidos            | `/api/orders`                     | `int`          |
| Líneas de pedido   | `/api/orders/{orderId}/details`   | `(int,int)`    |
| Regiones           | `/api/regions`                    | `int`          |
| Territorios        | `/api/territories`                | `string`       |
| Demográficos       | `/api/customer-demographics`      | `string`       |

Colección con `?page=&pageSize=&sort=&order=` (paginación acotada a 100 por página) y filtros propios de cada recurso.

### Vistas (solo lectura) — `/api/views`

`GET /api/views` lista el catálogo. Cada vista tiene su ruta, p. ej.:

```
GET /api/views/invoices?page=1&pageSize=20&customerId=ALFKI
GET /api/views/sales-by-category
GET /api/views/order-details-extended?orderId=10248
```

### Procedimientos almacenados — `/api/stored-procedures`

```
GET /api/stored-procedures/ten-most-expensive-products
GET /api/stored-procedures/employee-sales-by-country?beginningDate=1997-01-01&endingDate=1997-12-31
GET /api/stored-procedures/sales-by-year?beginningDate=1997-01-01&endingDate=1997-12-31
GET /api/stored-procedures/customer-order-detail/10248
GET /api/stored-procedures/customer-orders/ALFKI
GET /api/stored-procedures/customer-order-history/ALFKI
GET /api/stored-procedures/sales-by-category?categoryName=Beverages&ordYear=1997
```

### Dashboard — `/api/dashboard`

```
summary, sales-by-month, sales-by-quarter, sales-by-year,
top-products, top-categories, top-customers, recent-orders, order-status
```

Filtros opcionales `from`/`to` (por `OrderDate`) y `top` donde aplique.

### Reportes (PDF / XLSX) — `/api/reports`

```
GET /api/reports/sales-by-category.pdf
GET /api/reports/sales-by-year.xlsx
GET /api/reports/top-products.pdf?top=15
GET /api/reports/top-customers.xlsx
GET /api/reports/invoices.pdf?customerId=ALFKI
```

---

## Pruebas

```powershell
dotnet test
```

- **Unitarias**: `PageQuery`, ordenamiento por lista blanca, servicios CRUD con EF Core **InMemory**.
- **Integración**: `WebApplicationFactory` contra la base de datos Northwind real (endpoints de lectura,
  procedimientos, exportaciones y mapeo de errores 400/404/409).

Las pruebas de integración usan la cadena de conexión `NORTHWIND_TEST_CONNECTION` si está definida;
si no, LocalDB `(localdb)\MSSQLLocalDB` con la base `Northwind`.

---

## Pipeline CI/CD (GitHub Actions + Koyeb)

El flujo [`.github/workflows/ci-cd-pipeline.yml`](.github/workflows/ci-cd-pipeline.yml) cubre
**integración continua** en cada `push` a `main`, cada `pull_request` y cada tag `v*`. El
**despliegue** se ejecuta únicamente de forma manual desde
**Actions → CI/CD Pipeline → Run workflow**, con `deploy = true`.

```
push / pull_request / tag v*
        │
        ├──► build ──► test ──► image (GHCR) ──┐
        │                                      ├──► deploy (Koyeb, manual)
        └──────────────► sqlserver-image (GHCR)┘
```

| # | Job | Descripción |
|---|-----|-------------|
| 1 | **build** | Restaura paquetes, compila la solución en `Release` y publica la API; sube el artefacto `api-publish`. |
| 2 | **test** | Levanta **SQL Server 2022** como servicio del runner, carga Northwind con `scripts/init-northwind.sh` y ejecuta `dotnet test` con cobertura. Publica `test-results`. |
| 3 | **image** | Construye la imagen de la API con Buildx y la publica en **GHCR** (`ghcr.io/<owner>/<repo>`) con las etiquetas `latest`, `<rama>`, `sha-<7>` y las de un tag `v*`. |
| 4 | **sqlserver-image** | Construye la imagen de SQL Server 2022 con `instnwnd.sql` y el script de inicialización; la publica en el **mismo paquete público de GHCR** con el tag `sqlserver-sha-<7>`. |
| 5 | **deploy** | Crea o actualiza los recursos de **Koyeb**: app, volumen, secretos, servicio SQL Server privado y servicio API público. Inicializa Northwind y espera a que `/health` responda. |

En los *pull requests* las imágenes **se construyen pero no se publican** y el despliegue no se
ejecuta. La API usa la etiqueta inmutable `sha-<7>` para poder revertir a una versión anterior.

### Arquitectura en Koyeb

```
Koyeb App: northwind (región was o fra)
├── SQL Server 2022 (servicio web privado, standard medium)
│   ├── puerto 1433/TCP, sin ruta pública
│   ├── volumen persistente northwind-mssql (10 GB) en /var/opt/mssql
│   └── secreto MSSQL_SA_PASSWORD
└── API ASP.NET Core (servicio público, eco-small)
    ├── puerto 8080/HTTP, ruta /, health check /health
    └── ConnectionStrings__Northwind -> secreto NORTHWIND_CONNECTION
        Server=sqlserver.northwind.internal,1433
```

Koyeb no ofrece SQL Server como base de datos gestionada: se ejecuta como un **servicio
personalizado** con una imagen propia, un volumen persistente y escala fija en `1`. La API y
SQL Server deben estar en la **misma región** y en la **misma app** para comunicarse por la
red privada (service mesh). Las instancias **free están excluidas del mesh**, por eso la API usa
una instancia `eco-small` o superior.

### Cuándo se despliega

| Evento | `build` | `test` | `image` | `sqlserver-image` | `deploy` |
|--------|---------|--------|---------|-------------------|----------|
| `push` a `main` | ✅ | ✅ | ✅ publica | ✅ publica | ❌ |
| `push` de tag `v*` | ✅ | ✅ | ✅ publica | ✅ publica | ❌ |
| `pull_request` a `main` | ✅ | ✅ | ⚙️ sólo construye | ⚙️ sólo construye | ❌ |
| `workflow_dispatch` | ✅ | ✅ | ✅ publica | ✅ publica | ✅ sólo si `deploy = true` |

El job `deploy` usa el **environment** de GitHub (`production` por defecto, `staging` elegible),
lo que permite exigir aprobación manual y mantener los secretos separados por entorno. Para
evitar crear recursos de pago (Koyeb) sin confirmación, los pushes **no despliegan**.

Si más adelante se quiere desplegar automáticamente en cada push a `main`, hay que ampliar la
condición `if` del job `deploy` en el workflow.

En cada despliegue manual se actualizan la **API** y, si se pide, **SQL Server**. El servicio de
SQL Server **no se reinicia** en un despliegue normal: su imagen sólo se actualiza en la primera
creación o cuando se marca **`update_sqlserver = true`**. Esa actualización reinicia la base de
datos y provoca una interrupción breve; el volumen conserva los datos.

### Secretos y variables

Configurar en **Settings → Secrets and variables → Actions → Environments → production**
(o en el environment que se use):

| Nombre | Tipo | Descripción |
|--------|------|-------------|
| `KOYEB_TOKEN` | Secreto | API token de Koyeb con permisos para gestionar apps, servicios, secretos y volúmenes. |
| `MSSQL_SA_PASSWORD` | Secreto | Contraseña de `sa`; mínimo 12 caracteres, sin `;` ni comillas. Se registra también como secreto de Koyeb. |
| `KOYEB_APP` | Variable (opcional) | Nombre de la app de Koyeb. Por defecto `northwind`. |
| `KOYEB_REGION` | Variable (opcional) | `was` o `fra`, la misma región para volumen y servicios. Por defecto `was`. |
| `KOYEB_SQLSERVER_SERVICE` | Variable (opcional) | Nombre del servicio SQL Server. Por defecto `sqlserver`. |
| `KOYEB_API_SERVICE` | Variable (opcional) | Nombre del servicio de la API. Por defecto `api`. |
| `KOYEB_VOLUME` | Variable (opcional) | Nombre del volumen persistente. Por defecto `northwind-mssql`. |
| `KOYEB_SQLSERVER_INSTANCE` | Variable (opcional) | Tipo de instancia de SQL Server. Por defecto `medium` (2 GB). |
| `KOYEB_API_INSTANCE` | Variable (opcional) | Tipo de instancia de la API. Por defecto `eco-small` (1 GB). |
| `KOYEB_MSSQL_PID` | Variable (opcional) | Edición de SQL Server. Por defecto `Express`; `Developer` es válida para desarrollo/pruebas. |
| `KOYEB_MSSQL_MEMORY_MB` | Variable (opcional) | Límite de memoria de SQL Server. Por defecto `1536`. |
| `DEPLOY_URL` | Variable (opcional) | URL pública de la API en Koyeb; se muestra como enlace del environment. |

El workflow crea y actualiza automáticamente en Koyeb:

- la app `KOYEB_APP`;
- el volumen `KOYEB_VOLUME` de **10 GB** en `KOYEB_REGION`;
- el secreto `MSSQL_SA_PASSWORD` (a partir del secreto de GitHub);
- el secreto `NORTHWIND_CONNECTION` con la cadena de conexión privada;
- el servicio SQL Server con el volumen en `/var/opt/mssql`;
- el servicio público de la API con health check `/health`.

No hace falta configurar `DEPLOY_HOST`, `DEPLOY_USER`, claves SSH ni `DEPLOY_SSH_KNOWN_HOSTS`.
Esos valores pertenecen al despliegue anterior por SSH y pueden eliminarse del environment.

### Requisitos y coste

- Cuenta de **Koyeb con facturación**; los servicios necesarios no caben en el plan gratuito.
- **SQL Server**: instancia estándar `medium` (2 GB) + volumen de 10 GB. Precio aproximado:
  **21,43 USD/mes** de instancia + **5 USD/mes** de volumen (los precios pueden cambiar).
- **API**: instancia `eco-small` (1 GB), aproximadamente **5,36 USD/mes**.
- Coste total orientativo: **~32 USD/mes**. Se puede reducir la API a `eco-micro` (512 MB) o
  aumentar SQL Server a `large` (4 GB) cambiando las variables.
- El volumen persistente de Koyeb está en **public preview**: no sustituye a una base de datos
  gestionada. No hay copias de seguridad automáticas; si se necesitan, deben programarse
  (por ejemplo con `BACKUP DATABASE` y un almacenamiento externo).
- SQL Server **Express** es gratuito y suficiente para Northwind, pero tiene un límite de 10 GB
  por base de datos. Para un entorno de desarrollo se puede usar `KOYEB_MSSQL_PID=Developer`.
- La primera creación puede tardar **10–20 minutos** por la descarga de la imagen de SQL Server.

### Puesta en marcha

1. Crear un **API token** en Koyeb (**Account → API tokens**) y guardarlo como secreto
   `KOYEB_TOKEN` en el environment `production` de GitHub.
2. Crear el secreto `MSSQL_SA_PASSWORD` con una contraseña fuerte (mínimo 12 caracteres, sin
   `;` ni comillas). No se debe pegar en el chat ni en el repositorio.
3. Opcionalmente, definir las variables `KOYEB_APP`, `KOYEB_REGION`, etc. con los valores
   deseados. Los valores por defecto ya crean una arquitectura funcional.
4. Ejecutar **Actions → CI/CD Pipeline → Run workflow**, marcar `deploy = true` y elegir
   `production`. Un `push` a `main` sólo publica las imágenes; no despliega.
5. El primer despliegue crea la app, el volumen, los secretos y los dos servicios; después
   ejecuta `init-northwind.sh` dentro del contenedor de SQL Server. La API se crea al final,
   cuando la base ya está disponible.
6. Copiar la URL pública de la API desde el panel de Koyeb y asignarla a la variable
   `DEPLOY_URL` del environment. Verificar:

   ```bash
   curl -fsS https://<url-de-koyeb>/health
   # {"status":"Healthy","database":"Northwind"}
   ```

### Actualizaciones y mantenimiento

- **API**: cada push a `main` publica una imagen nueva; el servicio se actualiza en el
  siguiente despliegue manual con `deploy = true`.
- **SQL Server**: la imagen se actualiza sólo con `update_sqlserver = true` en
  `workflow_dispatch`. El volumen se conserva, pero el servicio se reinicia.
- **Contraseña de `sa`**: no cambiar `MSSQL_SA_PASSWORD` después del primer arranque sin
  cambiar también la contraseña dentro de SQL Server (`ALTER LOGIN sa WITH PASSWORD = ...`).
  El secreto de Koyeb y la cadena de conexión se actualizan en cada ejecución, pero la
  contraseña almacenada en la base no cambia sola.
- **Datos**: el volumen `northwind-mssql` persiste entre despliegues. Si se elimina el
  **volumen**, se pierden los datos y la siguiente ejecución vuelve a cargar `instnwnd.sql`.
  Eliminar sólo el servicio no borra el volumen.
- **Volver a una imagen anterior**: ejecutar el workflow con el commit anterior o cambiar el
  tag de la imagen en el panel de Koyeb. El servicio SQL Server no cambia si no se pide
  `update_sqlserver`.
- **Reiniciar la base desde cero**: eliminar el servicio y el volumen en Koyeb y volver a
  ejecutar el workflow. Es una operación destructiva.

### Despliegue SSH anterior

Los archivos [`deploy/docker-compose.prod.yml`](deploy/docker-compose.prod.yml) y
[`deploy/deploy.sh`](deploy/deploy.sh) se conservan como referencia para un VPS, pero el
pipeline ya **no los usa**. El despliegue soportado es Koyeb.


---

## Manejo de errores

Respuestas **ProblemDetails** (RFC 7807):

| Situación                                   | HTTP |
|---------------------------------------------|------|
| Validación (DataAnnotations / dominio)      | 400  |
| Recurso no encontrado                        | 404  |
| Clave foránea / unicidad / concurrencia     | 409  |
| Error no controlado                          | 500  |

---

## Despliegue con Docker

El despliegue contempla **dos contenedores Linux** orquestados con Docker Compose:

| Servicio   | Imagen                                          | Rol                                             |
|------------|-------------------------------------------------|-------------------------------------------------|
| `sqlserver`| `mcr.microsoft.com/mssql/server:2022-latest`     | SQL Server 2022 (edición Developer)              |
| `db-init`  | `mcr.microsoft.com/mssql/server:2022-latest`     | Crea `Northwind` y carga `instnwnd.sql` (una vez)|
| `api`      | build local (`Dockerfile`, Kestrel)              | API ASP.NET Core 10 en `:8080`                   |

> **Nota sobre IIS:** IIS requiere un contenedor **Windows** (`windowsservercore`), y una imagen
> oficial de SQL Server en contenedor es **Linux**. Un mismo host Docker no ejecuta contenedores
> Linux y Windows a la vez, por lo que este despliegue usa **Kestrel sobre Linux**. Para desplegar
> sobre IIS, publique la API en un host Windows con el *ASP.NET Core Hosting Bundle* y apunte la
> cadena de conexión a un SQL Server accesible por TCP.

### Requisitos

- Docker Engine / Docker Desktop con contenedores **Linux**.
- Puertos libres: **8080** (API) y **1433** (SQL Server).

### Puesta en marcha

```powershell
# (Opcional) fijar una contraseña de "sa" distinta a la de ejemplo:
Copy-Item .env.example .env      # y edite MSSQL_SA_PASSWORD

docker compose up --build -d
```

El arranque respeta el orden: `sqlserver` (healthcheck) → `db-init` (carga de datos) → `api`.

| Recurso     | URL                                     |
|-------------|-----------------------------------------|
| Dashboard   | `http://localhost:8080/`                |
| Swagger UI  | `http://localhost:8080/swagger`         |
| Salud       | `http://localhost:8080/health`          |

```
docker compose logs -f api        # seguir la API
docker compose down               # detener (conserva el volumen de datos)
docker compose down -v            # detener y borrar los datos
```

### Detalles de la configuración

- **`Dockerfile`** — build multi-stage (`sdk:10.0` → `aspnet:10.0`). En la imagen final se instalan
  las fuentes **Liberation** para la exportación a PDF (PDFsharp 6 no incluye fuentes): en Linux el
  `FileSystemFontResolver` localiza una fuente TrueType del sistema y la usa como sustituto
  métricamente compatible de Arial.
- **Cadena de conexión** — se inyecta por variable de entorno
  `ConnectionStrings__Northwind = Server=sqlserver,1433;Database=Northwind;User Id=sa;…`. El nombre
  `sqlserver` es el nombre del servicio en la red de Compose.
- **Datos** — se inicializan una sola vez con `instnwnd.sql` (montado como volumen en `db-init`) y
  persisten en el volumen `mssql-data`.
- **Entorno** — `docker-compose.yml` arranca la API en `ASPNETCORE_ENVIRONMENT=Development` para
  exponer Swagger UI y el panel. Cámbielo a `Production` para ocultarlos.
- **Reinicio de la carga de datos** — para volver a ejecutar `db-init`:
  `docker compose run --rm db-init` (tras `docker compose down`).

> Este `docker-compose.yml` es el de **desarrollo**: construye la imagen localmente
> (`--build`). El despliegue real lo hace el pipeline de GitHub Actions en **Koyeb**, usando
> las imágenes publicadas en GHCR. `deploy/docker-compose.prod.yml` y `deploy/deploy.sh`
> quedan como referencia legacy para un VPS. Véase
> [Pipeline CI/CD (GitHub Actions + Koyeb)](#pipeline-cicd-github-actions--koyeb).

---

## Decisiones de diseño

- **Database-first**: el contexto y las entidades generadas viven en
  `src/NorthwindApi.Infrastructure/Data/Generated` (scaffolding con `--use-database-names`).
  Son regenerables y **no** deben editarse a mano.
- **Sin pagos en el esquema**: no existe ninguna tabla de pagos/cobros. Por eso **“ventas”** se define
  como la suma de importes de línea de `Order Details` (`UnitPrice * Quantity * (1 - Discount)`).
- **Estado del pedido derivado**: no hay columna de estado; se infiere de `ShippedDate`/`RequiredDate`
  (`Enviado` / `Vencido` / `Pendiente`).
- **Tablas puente colapsadas**: `CustomerCustomerDemo` y `EmployeeTerritories` se modelan como
  relaciones *muchos-a-muchos* (navegaciones de omisión), sin entidades propias.
- **Vistas de solo lectura**: mapeadas como `HasNoKey().ToView(...)`.
- **Tipos**: `Discount` es `float`/`real`; `Quantity`, `UnitsInStock`, etc. son `smallint` (`short`);
  `money` → `decimal`. Los DTO de resultados respetan `short` para `smallint`.
- **Validación**: con `DataAnnotations` en **parámetros de constructor de los records** (no en propiedades),
  lo que ASP.NET Core integra en ProblemDetails automáticamente.
- **Reportes**: **PDFsharp/MigraDoc** (MIT) para PDF y **ClosedXML** (MIT) para XLSX. Se descartó
  QuestPDF por su licencia comercial. Para PDFsharp 6, en Windows se habilita
  `GlobalFontSettings.UseWindowsFontsUnderWindows` y en Linux/contenedores se registra
  `FileSystemFontResolver` (lee una fuente TrueType del sistema; `fonts-liberation` en la imagen).
- **Consultas parametrizadas**: los procedimientos se invocan con `Database.SqlQuery<T>` y
  *FormattableString* (nunca concatenación de SQL).
- **Orden seguro**: el parámetro `sort` se resuelve contra una lista blanca de expresiones; nunca se
  construye SQL a partir de texto libre.

---

## Limitaciones conocidas

- Los reportes de “Facturas” limitan a 5000 filas por exportación.
- Las vistas keyless no admiten `ORDER BY` en el servidor sin una clave; se ordenan en memoria/por columna
  representativa.
- `Ten Most Expensive Products` usa `SET ROWCOUNT` (obsoleto) dentro del procedimiento original; se expone
  tal cual viene en `instnwnd.sql`.
