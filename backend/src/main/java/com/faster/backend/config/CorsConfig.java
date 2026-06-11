package com.faster.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import java.util.List;

@Configuration
public class CorsConfig {

    @Bean
    public CorsFilter corsFilter() {

        CorsConfiguration config =
            new CorsConfiguration();

        // ─── Allow Flutter web + mobile ───────────
        config.setAllowedOriginPatterns(
            List.of("*"));

        // ─── Allow all HTTP methods ───────────────
        config.setAllowedMethods(List.of(
            "GET", "POST", "PUT",
            "PATCH", "DELETE", "OPTIONS"
        ));

        // ─── Allow all headers ────────────────────
        config.setAllowedHeaders(List.of(
            "Authorization",
            "Content-Type",
            "Accept",
            "Origin",
            "X-Requested-With"
        ));

        // ─── Allow credentials (JWT token) ────────
        config.setAllowCredentials(true);

        // ─── Cache preflight for 1 hour ───────────
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source =
            new UrlBasedCorsConfigurationSource();

        // Apply to ALL routes
        source.registerCorsConfiguration(
            "/**", config);

        return new CorsFilter(source);
    }
}