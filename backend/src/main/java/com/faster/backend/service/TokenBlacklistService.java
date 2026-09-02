package com.faster.backend.service;

import com.faster.backend.security.JwtUtil;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.util.concurrent.TimeUnit;

/**
 * TokenBlacklistService — M5 (logout / token revocation).
 *
 * A JWT is stateless by design: once issued it stays valid until it
 * expires, and this project issues 10-day tokens. That means logging
 * out previously did nothing server-side — the token kept working,
 * so a stolen or shared token remained usable for days after the
 * user thought they had signed out.
 *
 * Revoked tokens are stored in Redis with a TTL equal to the token's
 * OWN remaining lifetime. Once that passes, the entry disappears on
 * its own and the token would fail signature/expiry validation
 * anyway — so the blacklist stays small and needs no cleanup job.
 *
 * Redis is already a dependency (driver GPS), so this adds no new
 * infrastructure.
 *
 * Failure behaviour is deliberate and asymmetric:
 *   • If Redis is down during LOGOUT, we log and continue — the user
 *     is still logged out client-side, and refusing to log someone
 *     out because a cache is unavailable is worse than the risk.
 *   • If Redis is down during a CHECK, we treat the token as NOT
 *     blacklisted, because failing closed would lock every user out
 *     of the platform the moment Redis hiccups. The isBlocked check
 *     in JwtAuthFilter still runs regardless and is the stronger
 *     protection for the case that actually matters (a banned user).
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TokenBlacklistService {

    private final RedisTemplate<String, Object> redisTemplate;
    private final JwtUtil jwtUtil;

    private static final String KEY_PREFIX = "blacklist:token:";

    /** Revokes a token for the remainder of its natural lifetime. */
    public void blacklist(String token) {
        try {
            long ttlMillis = jwtUtil.getRemainingValidityMillis(token);

            // Already expired — nothing to revoke.
            if (ttlMillis <= 0) {
                return;
            }

            redisTemplate.opsForValue().set(
                    KEY_PREFIX + token,
                    "revoked",
                    ttlMillis,
                    TimeUnit.MILLISECONDS);

            log.info("🔒 Token revoked (expires naturally in {} minutes)",
                    ttlMillis / 60000);

        } catch (Exception e) {
            // Never block logout because the cache is unavailable.
            log.error("Could not blacklist token on logout: {}",
                    e.getMessage());
        }
    }

    /** True if this token was explicitly revoked via logout. */
    public boolean isBlacklisted(String token) {
        try {
            return Boolean.TRUE.equals(
                    redisTemplate.hasKey(KEY_PREFIX + token));
        } catch (Exception e) {
            // Fail OPEN — see the class comment. Locking every user
            // out over a Redis blip would be a worse outage than the
            // narrow window this leaves.
            log.error("Blacklist check failed, allowing request: {}",
                    e.getMessage());
            return false;
        }
    }
}