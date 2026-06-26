package com.faster.backend.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

import lombok.RequiredArgsConstructor;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            // ─── Disable CSRF (we use JWT not sessions) ──
            .csrf(AbstractHttpConfigurer::disable)

            // ─── Enable CORS ──────────────────────────────
            .cors(cors -> {} )

            // ─── Stateless sessions (JWT only) ───────────
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))

            // ─── Route Permissions ───────────────────────
            .authorizeHttpRequests(auth -> auth

                // PUBLIC — anyone can hit these
                .requestMatchers(
                    "/api/auth/register",
                    "/api/auth/login",
                    "/tracking/public/**",
                    "/api/store/**",
                    "/uploads/**",
                    "/ws/**"
                ).permitAll()

                // MERCHANT only routes
                .requestMatchers("/api/merchant/**")
                    .hasRole("MERCHANT")
                //DRIVER only routes
                .requestMatchers("/api/driver/**")
                    .hasRole("DRIVER")
                //Admin only routes 
                .requestMatchers("/api/admin/**")
                    .hasRole("ADMIN")

                // Everything else needs a valid token
                .anyRequest().authenticated()
            )

            // ─── Add JWT filter before default filter ────
            .addFilterBefore(jwtAuthFilter,
                UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    // ─── Password Encoder (BCrypt hashing) ──────────
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}