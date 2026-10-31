# Align sync server image. Build from server/:  docker build -t align-server .
# Not used by the tests; see README.md.

# --- build stage -------------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-noble AS build
WORKDIR /src
# Resolve dependencies first so source edits do not invalidate this layer.
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw -B -ntp -q dependency:go-offline
COPY src src
RUN ./mvnw -B -ntp -q -DskipTests package \
    && java -Djarmode=tools -jar target/align-server.jar extract --layers --launcher --destination /extracted

# --- runtime stage -----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-noble
RUN groupadd --system --gid 10001 align \
    && useradd --system --uid 10001 --gid align --home-dir /app --shell /usr/sbin/nologin align
WORKDIR /app
COPY --from=build --chown=align:align /extracted/dependencies/ ./
COPY --from=build --chown=align:align /extracted/spring-boot-loader/ ./
COPY --from=build --chown=align:align /extracted/snapshot-dependencies/ ./
COPY --from=build --chown=align:align /extracted/application/ ./
USER 10001:10001
EXPOSE 8080
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
