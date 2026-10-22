# FORENSIC REPORT — TALLER DOCKER (Semana 13)
## Contenerización, Seguridad de Runtime y Estrés de cgroups

| | |
|---|---|
| **Proyecto** | `eco-air-backend` |
| **Estudiante / STUDENT_ID** | `1193522218` |
| **Imagen resultante** | `eco-air-backend:1.0.0` |
| **Fecha de auditoría** | 2026-10-21 |
| **Entorno** | Windows 11 + Docker Desktop (Linux engine) 29.3.1 |
| **Log crudo de terminal** | `audit_session.log` |

---

## 1. TABLA DE IDENTIDAD

| Campo | Valor |
|---|---|
| **Hash de la imagen** (`docker inspect --format='{{.Id}}'`) | `sha256:67f93db4f9a9481477e0da9d1f0d5db8f3faa2ea5b97b9e6a4f952a48043bfa3` |
| **Variable de entorno inyectada** (`OPERATOR_ID`) | `1193522218` |
| **Usuario de runtime** | `sensor_user` — UID `10001`, grupo `sensorgroup` (GID `10001`) |
| **Consumo final calibrado** (`-m 108m`) | CPU `0.68%` · MEM `94.43MiB / 108MiB` · MEM% `87.44%` |

### 1.1 Huella SHA-256 de las capas (`RootFS.Layers`)

```
sha256:74d97c428c51a828f9051a7a40a53ff1fc99e54fc30323ce36760701b0b7f711
sha256:a152dfd2607b01e7c5b933b98da8c746ed0bd242e4f544ff3afd656fdfc7c7a1
sha256:b9398a5bcfd34ada6c3760ac870b064bf54fb191a502393cbb6a3088f8c9be5b
sha256:76b42b7b749e5cf63c4ef5fe61a878a5f508733d81f12305b29e6320007a49de
sha256:6c0c03120c42828b5d975a2b84e53a9ca0ed58b0b0dab9b6c79f5516ddabce2c
sha256:004589a481a5477a6c9189e53f708aab3c617a4176403f11755fe428e299b189
sha256:87f14b0f80e1cbef4e7162e6a09abe32bd4415de000709a06950034b3c7c2563
sha256:72d15e488914f157922b34a52395287554f439acc88db3338be96568058c79d7
sha256:a2c269a519677c9a600e79ec46f6a82b34c3fdb320d7ef762d9be713104ee2a4
```

> 9 capas en total. La etapa `builder` (Maven) no aporta capas a la imagen final: sólo se
> copia el artefacto `.jar` ya empaquetado, lo que reduce la superficie de ataque.

### 1.2 Comando de construcción obligatorio

```bash
docker build --build-arg STUDENT_ID="1193522218" -t eco-air-backend:1.0.0 .
```

---

## 2. RETO 1 — CONSTRUCCIÓN MULTIETAPA CON HUELLA ESTRICTA

### 2.1 Diseño del `Dockerfile`

- **Etapa `builder`** (`maven:3.9.6-eclipse-temurin-17-alpine`):
  - `COPY pom.xml .` + `RUN mvn dependency:go-offline -B` **antes** de transferir `src/`,
    de modo que el árbol de dependencias queda cacheado entre construcciones.
  - `ARG STUDENT_ID` declarado en build-time.
  - `RUN mvn package -DskipTests -B` para empaquetar el JAR omitiendo pruebas.
- **Etapa `runtime`** (`eclipse-temurin:17-jre-alpine`):
  - `addgroup -g 10001 sensorgroup` y `adduser -u 10001 -G sensorgroup -D sensor_user`.
  - `COPY --from=builder .../eco-air-backend.jar` (sólo el JAR) + `chown -R sensor_user:sensorgroup /app`.
  - `ENV OPERATOR_ID=${STUDENT_ID}` y variables ergonómicas de JVM (`JAVA_TOOL_OPTIONS`).
  - `USER sensor_user` antes del `ENTRYPOINT`.

### 2.2 Desacoplamiento de capas (`docker history`)

```
$ docker history --human --format "table {{.Size}}\t{{.CreatedBy}}" eco-air-backend:1.0.0
SIZE      CREATED BY
0B        ENTRYPOINT ["java" "-jar" "/app/eco-air-backend.jar"]
0B        USER sensor_user
47MB      RUN |1 STUDENT_ID=1193522218 /bin/sh -c chown -R sensor_user:sensorgroup /app
47MB      COPY /build/target/eco-air-backend.jar /app/eco-air-backend.jar
8.19kB    WORKDIR /app
41kB      RUN |1 STUDENT_ID=1193522218 /bin/sh -c addgroup -g 10001 sensorgroup && adduser -u 10001 ...
0B        ENV OPERATOR_ID=1193522218 JAVA_TOOL_OPTIONS=...
0B        ARG STUDENT_ID=1193522218
0B        ENTRYPOINT ["/__cacert_entrypoint.sh"]
12.3kB    COPY --chmod=755 entrypoint.sh /__cacert_entrypoint.sh
12.3kB    RUN /bin/sh -c set -eux; echo "Verifying..." ...
141MB     RUN /bin/sh -c set -eux; ARCH="$(apk --p..." ...
0B        ENV JAVA_VERSION=jdk-17.0.20.1+1
44MB      RUN /bin/sh -c set -eux; apk add --no-ca..." ...
0B        ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_AL...
0B        ENV PATH=/opt/java/openjdk/bin:/usr/local/sb...
0B        ENV JAVA_HOME=/opt/java/openjdk
0B        CMD ["/bin/sh"]
9.08MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /
```

**Lectura:** no aparece ninguna capa de Maven ni de `src/` en la imagen final. El peso
dominante (141 MB) corresponde al JRE embebido de `eclipse-temurin`; el artefacto de
negocio aporta ~47 MB. La huella es la esperada para una imagen de producción ligera.

---

## 3. RETO 2 — AUDITORÍA FORENSE Y VULNERABILIDADES

### 3.1 Inspección del proceso del host (aislamiento de privilegios)

```bash
docker run -d --name eco_air_active -p 8080:8080 eco-air-backend:1.0.0
docker top eco_air_active -o pid,user,comm
```

```
PID                 USER                COMMAND
7735                10001               java
```

**Evidencia:** el proceso `java` se ejecuta bajo el UID `10001` (`sensor_user`), **no**
como `root`. La directiva `USER sensor_user` se aplica correctamente.

### 3.2 Test de penetración — inmutabilidad de runtime

```bash
docker exec eco_air_active touch /etc/crontab_fake
```

```
touch: cannot touch '/etc/crontab_fake': Permission denied
```

**Evidencia:** un proceso no privilegiado no puede escribir en `/etc`. La escritura de un
script malicioso en el sistema de archivos queda bloqueada por permisos, no por una
supuesta inmutabilidad del rootfs.

### 3.3 Auditoría de artefactos de desarrollo

```bash
docker exec eco_air_active which mvn
```
```
(sin salida — el binario `mvn` no existe en la imagen de runtime)
```

```bash
docker exec eco_air_active find / -name "*.java"
```
```
find: /root: Permission denied
find: /proc/tty/driver: Permission denied
```

**Evidencia:** no hay ningún archivo `*.java` en el rootfs de producción. El compilador,
el código fuente y Maven sólo existen en la etapa `builder`, que no se exporta. La
imagen de runtime contiene exclusivamente el JAR ya compilado.

### 3.4 Variable de entorno inyectada

```bash
docker exec eco_air_active env | grep OPERATOR_ID
```
```
OPERATOR_ID=1193522218
```

---

## 4. RETO 3 — CALIBRACIÓN DE CGROUPS Y CAPTURA DEL ASESINO OOM

### 4.1 Inducción del colapso por memoria (OOMKilled)

```bash
docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
# espera de 70 segundos
docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
```

```
Status: exited | ExitCode: 137 | OOMKilled: true
```

**Evidencia:** con un presupuesto de 48 MB el kernel Linux (a través del cgroup `memory`)
detecta que el proceso supera el límite y lo elimina con `SIGKILL` (código 137 = 128 + 9).
`OOMKilled: true` confirma que el asesino fue el OOM-killer del kernel, no un fallo de la
aplicación. En los logs se observa que Spring Boot alcanzaba a arrancar los repositorios
JPA pero no completaba la inicialización de Tomcat antes del colapso.

### 4.2 Calibración del límite operativo mínimo

Se iteró `-m` de forma decreciente. Criterios: contenedor `running`, arranque < 15 s y
`docker stats` estable.

| Límite `-m` | Estado | Arranque (`Started EcoAirApplication`) | MEM USAGE / LIMIT | MEM % |
|---|---|---|---|---|
| 512m | running | 11.268 s | 175.7MiB / 512MiB | 34.31% |
| 384m | running | 15.964 s | 168.1MiB / 384MiB | 43.78% |
| 256m | running | 9.184 s | 158.2MiB / 256MiB | 61.78% |
| 192m | running | 7.904 s | 150.8MiB / 192MiB | 78.55% |
| 144m | running | 9.822 s | 126.1MiB / 144MiB | 87.57% |
| **108m** | **running** | **14.74 s** | **94.88MiB / 108MiB** | **87.85%** |
| 104m | running | 16.315 s | 90.86MiB / 104MiB | 87.36% |
| 100m | running | 17.635 s | 89.68MiB / 100MiB | 89.68% |
| 96m | running | 20.154 s | 88MiB / 96MiB | 91.67% |
| 48m | **exited (OOM)** | — | — | — |

**Umbral mínimo operativo calibrado: `-m 108m`.**

Justificación:
- En 108 MiB la aplicación arranca en **14.74 s** (< 15 s) y `docker stats` se mantiene
  estable en ~87% del límite, con margen para el *garbage collector*.
- En 104 MiB el arranque supera el presupuesto (16.315 s) y a partir de 100 MiB degrada
  de forma progresiva (17.6 s → 20.2 s en 96 MiB), síntoma de presión de GC.
- El tiempo de arranque presenta *jitter* de ±2–3 s por carga del host, por lo que el
  umbral exacto se sitúa en la franja **104–108 MiB**; se adopta 108 MiB como valor
  mínimo con margen de seguridad.

### 4.3 Consumo final calibrado (requerido)

```bash
docker stats --no-stream eco_air_active
```

```
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O       PIDS
5aa1ae24e665   eco_air_active   0.68%     94.43MiB / 108MiB   87.44%    1.17kB / 126B   51.5MB / 96.1MB   31
```

| Métrica | Valor |
|---|---|
| **CPU %** | 0.68% |
| **MEM USAGE / LIMIT** | 94.43MiB / 108MiB |
| **MEM %** | 87.44% |
| **Arranque** | 12.23 s |
| **Estado** | running · OOMKilled=false |

---

## 5. CONCLUSIONES

1. **Imagen mínima y desacoplada.** La construcción multietapa elimina Maven, el código
   fuente y las herramientas de compilación de la imagen de producción (9 capas, dominadas
   por el JRE).
2. **Runtime no privilegiado.** `sensor_user` (UID 10001) ejecuta la JVM; un intento de
   escritura en `/etc` es rechazado por permisos.
3. **Supervivencia garantizada por cgroups.** El límite de memoria es aplicado por el
   kernel: a 48 MB el contenedor muere con `ExitCode 137` y `OOMKilled=true`, protegiendo
   al host. El límite operativo mínimo estable es **108 MiB**.
4. **Inyección de identidad en build-time.** `OPERATOR_ID=1193522218` queda embebido como
   variable de entorno y es verificable en caliente.

---

## ANEXO — Estructura de entrega

```
taller-docker-semana13/
├── Dockerfile
├── .dockerignore
├── audit_session.log
└── FORENSIC_REPORT.md
```
