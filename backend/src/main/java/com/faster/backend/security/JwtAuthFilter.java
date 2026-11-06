package com.faster.backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;

@Component
@RequiredArgsConstructor
public class JwtAuthFilter extends OncePerRequestFilter {

    // Shared with StompChannelInterceptor — see that class's own doc for
    // why this used to be two independently-drifting copies of the same
    // blacklist/validity/blocked checks.
    private final JwtAuthenticationSupport jwtAuthenticationSupport;
    private final ObjectMapper objectMapper;

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

        // Subject is EMAIL — used as the Spring Security principal.
        // Controllers call auth.getName() to get email, then look up
        // the user via userRepository.findByEmail().
        try {
            UsernamePasswordAuthenticationToken authentication =
                    jwtAuthenticationSupport.authenticate(token);

            if (authentication != null) {
                SecurityContextHolder.getContext()
                        .setAuthentication(authentication);
            }
            // null means the token itself was missing/invalid/expired —
            // not an error here, since many endpoints are public; just
            // continue unauthenticated and let Spring Security's own
            // authorization rules decide.
        } catch (JwtAuthenticationSupport.AuthRejected e) {
            writeJsonError(response,
                    e.isForbidden()
                            ? HttpServletResponse.SC_FORBIDDEN
                            : HttpServletResponse.SC_UNAUTHORIZED,
                    e.getMessage());
            return;
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