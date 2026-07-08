package com.faster.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import java.util.ArrayList;
import java.util.List;

/**
 * REST CORS configuration.
 *
 * FIX (C1): now reads the SAME property as WebSocketConfig and
 * application-prod.properties — app.cors.allowed-origins, backed by the
 * ALLOWED_ORIGINS env var (comma-separated). Previously this file read a
 * different, singular ALLOWED_ORIGIN env var that nothing else used, so
 * REST CORS and WebSocket CORS were configured from two different sources.
 *
 * Set in prod .env:
 *   ALLOWED_ORIGINS=https://faster-app.org,https://www.faster-app.org
 */
@Configuration
public class CorsConfig {

    @Value("${app.cors.allowed-origins:http://localhost:*,http://10.0.2.*,http://192.168.*.*}")
    private String allowedOrigins;

    @Bean
    public CorsFilter corsFilter() {

        CorsConfiguration config = new CorsConfiguration();

        List<String> origins = new ArrayList<>();
        for (String origin : allowedOrigins.split(",")) {
            String trimmed = origin.trim();
            if (!trimmed.isEmpty()) {
                origins.add(trimmed);
            }
        }

        config.setAllowedOriginPatterns(origins);

        config.setAllowedMethods(List.of(
            "GET", "POST", "PUT",
            "PATCH", "DELETE", "OPTIONS"
        ));

        config.setAllowedHeaders(List.of(
            "Authorization",
            "Content-Type",
            "Accept",
            "Origin",
            "X-Requested-With"
        ));

        config.setAllowCredentials(true);
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source =
            new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);

        return new CorsFilter(source);
    }
}