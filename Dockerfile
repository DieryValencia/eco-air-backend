# syntax=docker/dockerfile:1

# ------------------------------------------------------------------
# Etapa 1: builder - compilacion y empaquetado del JAR ejecutable
# ------------------------------------------------------------------
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

ARG STUDENT_ID

WORKDIR /build

# Se descarga primero solo el pom.xml para cachear dependencias
# entre construcciones y aislar el arbol de dependencias del codigo fuente.
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Recien ahora se transfiere el codigo fuente.
COPY src ./src

# Empaquetado del JAR ejecutable omitiendo las pruebas.
RUN mvn package -DskipTests -B

# ------------------------------------------------------------------
# Etapa 2: runtime - imagen de produccion ligera y no privilegiada
# ------------------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine

ARG STUDENT_ID

# Variables de entorno ergonomicas para la JVM.
ENV OPERATOR_ID=${STUDENT_ID} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=25.0 -XX:+UseSerialGC -XX:+UseContainerSupport"

# Usuario del sistema sin privilegios: sensor_user (UID 10001) en el
# grupo sensorgroup (GID 10001).
RUN addgroup -g 10001 sensorgroup && \
    adduser -u 10001 -G sensorgroup -s /bin/sh -D sensor_user

WORKDIR /app

# Se copia UNICAMENTE el JAR resultante de la etapa de builder y se
# transfiere la titularidad del directorio /app a sensor_user.
COPY --from=builder /build/target/eco-air-backend.jar /app/eco-air-backend.jar
RUN chown -R sensor_user:sensorgroup /app

# Cambio al usuario no privilegiado antes del ENTRYPOINT.
USER sensor_user

ENTRYPOINT ["java", "-jar", "/app/eco-air-backend.jar"]
