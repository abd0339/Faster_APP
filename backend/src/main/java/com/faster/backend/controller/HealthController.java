package com.faster.backend.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    // ─── GET /api/health ─────────────────────────────
    // Used by:
    //   - Docker HEALTHCHECK in Dockerfile
    //   - GitHub Actions deploy script
    //   - Nginx upstream health check
    // Must be in SecurityConfig public routes (already is via /api/auth/**)
    // Returns 200 UP when backend is running and ready
    @GetMapping("/api/health")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok(Map.of(
                "status", "UP",
                "service", "Faster Backend"));
    }
}