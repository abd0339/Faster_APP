package com.faster.backend.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import java.security.Key;
import java.util.Date;

@Component
public class JwtUtil {

    // ─── Pulled from application.properties ─────────
    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Value("${app.jwt.expiration-ms}")
    private long jwtExpirationMs;

    // ─── Generate a token for a logged-in user ───────
    public String generateToken(String phone, String role) {
        return Jwts.builder()
                .setSubject(phone)
                .claim("role", role)
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + jwtExpirationMs))
                .signWith(getSigningKey(), SignatureAlgorithm.HS256)
                .compact();
    }

    // ─── Extract the phone number from a token ───────
    public String getPhoneFromToken(String token) {
        return parseClaims(token).getSubject();
    }

    // ─── Extract the role from a token ───────────────
    public String getRoleFromToken(String token) {
        return parseClaims(token).get("role", String.class);
    }

    // ─── Check if token is still valid ───────────────
    public boolean validateToken(String token) {
        try {
            parseClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false;
        }
    }

    // ─── Internal: decode the token ──────────────────
    private Claims parseClaims(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(getSigningKey())
                .build()
                .parseClaimsJws(token)
                .getBody();
    }

    // ─── Internal: build the signing key ─────────────
    private Key getSigningKey() {
        return Keys.hmacShaKeyFor(jwtSecret.getBytes());
    }
}