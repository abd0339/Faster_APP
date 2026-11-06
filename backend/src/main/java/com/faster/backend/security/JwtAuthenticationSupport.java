package com.faster.backend.security;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.TokenBlacklistService;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Shared bearer-token → authenticated-principal resolution, used by both
 * JwtAuthFilter (REST) and StompChannelInterceptor (WebSocket/STOMP CONNECT).
 *
 * Before this class existed, each transport re-implemented the same three
 * checks independently (blacklist, signature/expiry validation, current
 * isBlocked status) with its own copy-pasted logic — the two copies had
 * already drifted once (the STOMP side gained its own exchange-rate topic
 * case without the REST side knowing), which is exactly the failure mode
 * duplicated security logic invites: a fix applied to one copy silently
 * doesn't apply to the other. This class is the one copy both transports
 * call.
 *
 * The two transports still react differently to the result (JwtAuthFilter
 * lets a missing/invalid token continue unauthenticated since many REST
 * endpoints are public; STOMP CONNECT always requires authentication), so
 * this returns null for "no valid token" rather than deciding that for the
 * caller, and throws {@link AuthRejected} only for the cases both
 * transports must always reject outright (revoked token, deleted account,
 * blocked account).
 */
@Component
@RequiredArgsConstructor
public class JwtAuthenticationSupport {

    private final JwtUtil jwtUtil;
    private final TokenBlacklistService tokenBlacklistService;
    private final UserRepository userRepository;

    /**
     * Thrown for a token that must always be rejected, regardless of
     * whether the caller otherwise allows anonymous access.
     */
    @Getter
    public static class AuthRejected extends RuntimeException {
        private final boolean forbidden;

        public AuthRejected(String message, boolean forbidden) {
            super(message);
            this.forbidden = forbidden;
        }
    }

    /**
     * Returns the authentication to set for a valid, live token, or null
     * when the token itself is missing/malformed/expired (not an error —
     * callers that permit anonymous access should just continue
     * unauthenticated). Throws AuthRejected when the token is otherwise
     * well-formed but must never be honored: blacklisted (logged out),
     * its account deleted, or its account blocked.
     */
    public UsernamePasswordAuthenticationToken authenticate(String token) {
        if (tokenBlacklistService.isBlacklisted(token)) {
            throw new AuthRejected(
                    "This session has ended. Please sign in again.", false);
        }

        if (!jwtUtil.validateToken(token)) {
            return null;
        }

        String email = jwtUtil.getEmailFromToken(token);
        String role = jwtUtil.getRoleFromToken(token);

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new AuthRejected(
                        "Your account no longer exists. Please sign in again.",
                        false));

        if (Boolean.TRUE.equals(user.getIsBlocked())) {
            // Forbidden, not unauthorized: the credentials are valid, the
            // account is barred. Treating it as unauthorized would make
            // clients retry the login loop pointlessly.
            throw new AuthRejected(
                    "Your account has been blocked. Please contact support.",
                    true);
        }

        return new UsernamePasswordAuthenticationToken(
                email, null,
                List.of(new SimpleGrantedAuthority("ROLE_" + role)));
    }
}
