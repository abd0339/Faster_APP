# ─────────────────────────────────────────────────────
# FASTER APP — Backend Dockerfile
# Multi-stage build:
#   Stage 1 (builder): compiles the JAR with Maven
#   Stage 2 (runtime): runs the JAR on a minimal JRE
# Uses system Maven — no mvnw wrapper needed
# ─────────────────────────────────────────────────────

# ── Stage 1: Build ───────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /build

# Copy pom.xml first — Docker caches this layer
# Dependencies only re-download if pom.xml changes
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Copy source and build the JAR
COPY src ./src
RUN mvn clean package -DskipTests -q

# ── Stage 2: Runtime ─────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runtime

WORKDIR /app

# Create non-root user — never run prod apps as root
RUN addgroup -S faster && adduser -S faster -G faster

# Copy the compiled JAR from builder stage
COPY --from=builder /build/target/backend-0.0.1-SNAPSHOT.jar app.jar

# Create uploads directory and set ownership
RUN mkdir -p /app/uploads/items /app/uploads/offers && \
    chown -R faster:faster /app

# Switch to non-root user
USER faster

# Expose Spring Boot port
EXPOSE 8080

# Health check — Docker restarts container if unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD wget -qO- http://localhost:8080/api/health || exit 1

# Run — prod profile activates application-prod.properties
ENTRYPOINT ["java", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-Dspring.profiles.active=prod", \
    "-jar", "app.jar"]