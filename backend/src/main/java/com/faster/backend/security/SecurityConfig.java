package com.faster.backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

import java.time.LocalDateTime;
import java.util.Map;

import lombok.RequiredArgsConstructor;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;
    private final ObjectMapper objectMapper = new ObjectMapper()
            .findAndRegisterModules();

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)

                .cors(cors -> {
                })

                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))

                // ─── Consistent JSON error bodies ────────────
                // FIX: previously there was no entry point / access
                // denied handler, so an unauthenticated or forbidden
                // request returned an EMPTY body. That's why testing
                // /api/orders/quote without a token printed nothing —
                // it wasn't a bug in the endpoint, but it meant every
                // protected route gave a blank response instead of a
                // JSON message the Flutter app could actually show.
                .exceptionHandling(handling -> handling
                        // No token / invalid token → 401
                        .authenticationEntryPoint((request, response, ex) -> {
                            response.setStatus(401);
                            response.setContentType(
                                    MediaType.APPLICATION_JSON_VALUE);
                            response.getWriter().write(
                                    objectMapper.writeValueAsString(Map.of(
                                            "status", "error",
                                            "message",
                                            "Authentication required. "
                                            + "Please log in.",
                                            "timestamp",
                                            LocalDateTime.now().toString())));
                        })
                        // Valid token, wrong role → 403
                        .accessDeniedHandler((request, response, ex) -> {
                            response.setStatus(403);
                            response.setContentType(
                                    MediaType.APPLICATION_JSON_VALUE);
                            response.getWriter().write(
                                    objectMapper.writeValueAsString(Map.of(
                                            "status", "error",
                                            "message",
                                            "You don't have permission "
                                            + "to access this.",
                                            "timestamp",
                                            LocalDateTime.now().toString())));
                        }))

                .authorizeHttpRequests(auth -> auth

                        .requestMatchers(
                                "/api/auth/register",
                                "/api/auth/login",
                                "/api/auth/verify-otp",
                                "/api/auth/resend-otp",
                                "/api/health",
                                "/tracking/public/**",
                                "/api/store/**",
                                "/uploads/**",
                                "/ws/**",
                                "/api/webhooks/twilio/**")
                        .permitAll()

                        .requestMatchers("/api/merchant/**")
                        .hasRole("MERCHANT")
                        .requestMatchers("/api/driver/**")
                        .hasRole("DRIVER")
                        .requestMatchers("/api/admin/**")
                        .hasRole("ADMIN")

                        .anyRequest().authenticated())

                .addFilterBefore(jwtAuthFilter,
                        UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}