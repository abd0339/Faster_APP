# ─────────────────────────────────────────────────────
# FASTER APP — Backend Dockerfile
# Multi-stage build:
#   Stage 1 (builder): compiles the JAR with Maven
#   Stage 2 (runtime): runs the JAR on a minimal JRE
# Final image is ~200MB instead of ~600MB
# ─────────────────────────────────────────────────────

# ── Stage 1: Build ───────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder

WORKDIR /build

# Copy Maven wrapper and pom.xml first
# Docker caches this layer — only re-runs if pom.xml changes
COPY pom.xml .
COPY mvnw .
COPY .mvn .mvn

# Download dependencies (cached layer)
RUN ./mvnw dependency:go-offline -q

# Copy source and build
COPY src ./src
RUN ./mvnw clean package -DskipTests -q

# ── Stage 2: Runtime ─────────────────────────────────
FROM eclipse-temurin:17-jre-alpine AS runtime

WORKDIR /app

# Create non-root user for security
# Never run production apps as root
RUN addgroup -S faster && adduser -S faster -G faster

# Copy the compiled JAR from builder stage
COPY --from=builder /build/target/backend-0.0.1-SNAPSHOT.jar app.jar

# Create uploads directory and set ownership
RUN mkdir -p /app/uploads/items /app/uploads/offers && \
    chown -R faster:faster /app

# Switch to non-root user
USER faster

# Expose the Spring Boot port
EXPOSE 8080

# Health check — Docker will restart container if unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:8080/api/health || exit 1

# Run the app
# SPRING_PROFILES_ACTIVE=prod activates application-prod.properties
ENTRYPOINT ["java", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-Dspring.profiles.active=prod", \
    "-jar", "app.jar"]