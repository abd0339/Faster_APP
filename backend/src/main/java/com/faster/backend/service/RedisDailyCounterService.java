package com.faster.backend.service;

import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;

/**
 * Shared "increment a Redis counter, arm a 24h TTL on its first hit"
 * primitive (design-pattern-review finding, 2026-11-01).
 *
 * OtpRateLimitService and PlacesRateLimitService both hand-rolled this
 * exact increment+TTL dance for their per-phone/per-IP/per-user daily
 * caps — PlacesRateLimitService's own comment already said as much
 * ("Same Redis per-day-counter pattern as OtpRateLimitService").
 *
 * Deliberately NOT shared here: the max-count comparison, the
 * exception thrown, or whether a Redis failure fails OPEN or CLOSED.
 * Those differ between callers for real business reasons (an
 * uncapped OTP endpoint can drain the Twilio balance in seconds, so
 * it fails closed; losing the Places spend cap for a few minutes is
 * a smaller problem than breaking address search, so it fails open).
 * Burying that choice inside a shared helper is exactly the kind of
 * "important decision hidden in generic exception-handling code" the
 * review flagged — each caller keeps making that call explicitly.
 */
@Service
@RequiredArgsConstructor
public class RedisDailyCounterService {

    private final RedisTemplate<String, Object> redisTemplate;

    private static final Duration DAY = Duration.ofHours(24);

    /**
     * Atomically increments {@code key}. If this is the first
     * increment of a fresh window, arms a 24h TTL so the key expires
     * on its own with no cleanup job needed.
     *
     * @return the new count, or null if the increment itself
     *         returned null (caller decides how to treat that —
     *         see the class comment on why fail-open/closed isn't
     *         decided here). Does NOT catch Redis exceptions; the
     *         caller's own try/catch (with its own fail-open/closed
     *         policy) is expected to wrap this call.
     */
    public Long incrementWithDailyWindow(String key) {
        Long count = redisTemplate.opsForValue().increment(key);
        if (count != null && count == 1L) {
            // First hit in this window — start the 24h clock.
            // Without this the key would live forever.
            redisTemplate.expire(key, DAY);
        }
        return count;
    }
}
