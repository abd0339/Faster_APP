package com.faster.backend.security;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.TokenBlacklistService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Component
@RequiredArgsConstructor
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;

    // M5 FIX: needed to re-check the user's CURRENT state on every
    // request. A JWT is a signed snapshot taken at login — it cannot
    // know that an admin blocked the user five minutes later. Without
    // this lookup a blocked driver kept full access until their token
    // expired naturally, which is up to TEN DAYS. Blocking someone for
    // fraud has to take effect on their very next request, not next
    // week.
    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;

    // M5: tokens explicitly revoked at logout. Without this, "log
    // out" was purely cosmetic — the token kept working for the
    // rest of its 10-day life.
    private final TokenBlacklistService tokenBlacklistService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        // ─── Read the Authorization header ───────────
        String authHeader = request.getHeader("Authorization");

        // ─── If no token, skip and continue ──────────
        if (authHeader == null ||
                !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        // ─── Extract the raw token ────────────────────
        String token = authHeader.substring(7);

        // ─── Validate token and set user in context ───
        // Subject is EMAIL — used as the Spring Security principal
        // Controllers call auth.getName() to get email,
        // then look up user via userRepository.findByEmail()
        // ─── Reject tokens revoked at logout ─────────
        if (tokenBlacklistService.isBlacklisted(token)) {
            writeJsonError(response,
                    HttpServletResponse.SC_UNAUTHORIZED,
                    "This session has ended. Please sign in again.");
            return;
        }

        if (jwtUtil.validateToken(token)) {
            String email = jwtUtil.getEmailFromToken(token);
            String role  = jwtUtil.getRoleFromToken(token);

            // ─── M5: re-check current block status ────────
            // One indexed lookup by email per authenticated request.
            // Cheap, and the alternative is a blocked account staying
            // live for days.
            Optional<User> currentUser = userRepository.findByEmail(email);

            if (currentUser.isEmpty()) {
                // Account deleted since the token was issued.
                writeJsonError(response,
                        HttpServletResponse.SC_UNAUTHORIZED,
                        "Your account no longer exists. Please sign in again.");
                return;
            }

            if (Boolean.TRUE.equals(currentUser.get().getIsBlocked())) {
                // 403, not 401: the credentials are valid, the account
                // is barred. A 401 would make clients retry the login
                // loop pointlessly.
                writeJsonError(response,
                        HttpServletResponse.SC_FORBIDDEN,
                        "Your account has been blocked. Please contact support.");
                return;
            }

            UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(
                            email,
                            null,
                            List.of(new SimpleGrantedAuthority(
                                    "ROLE_" + role))
                    );

            SecurityContextHolder.getContext()
                    .setAuthentication(authentication);
        }

        filterChain.doFilter(request, response);
    }

    // Writes a JSON body rather than letting Spring return an empty
    // response — the Flutter app parses {"message": ...} everywhere,
    // and a blank body shows the user nothing at all.
    private void writeJsonError(HttpServletResponse response,
                                int status,
                                String message) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.getWriter().write(objectMapper.writeValueAsString(
                Map.of(
                        "status", "error",
                        "message", message)));
    }
}