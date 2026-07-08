package com.faster.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import java.util.List;

@Configuration
public class CorsConfig {

    // Reads from ALLOWED_ORIGIN env var — set in .env on the server.
    // Falls back to common local dev origins if not set.
    @Value("${ALLOWED_ORIGIN:}")
    private String allowedOrigin;

    @Bean
    public CorsFilter corsFilter() {

        CorsConfiguration config = new CorsConfiguration();

        // Always allow local dev origins
        java.util.List<String> origins = new java.util.ArrayList<>(List.of(
            "http://localhost:*",
            "http://10.0.2.*",
            "http://192.168.*.*"
        ));

        // Add the production domain from env var if set
        if (allowedOrigin != null && !allowedOrigin.isBlank()) {
            origins.add(allowedOrigin);
            // Also allow the www subdomain automatically
            if (!allowedOrigin.contains("www.")) {
                origins.add(allowedOrigin.replace("https://", "https://www."));
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