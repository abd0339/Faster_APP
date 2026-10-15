package com.faster.backend.service;

import com.faster.backend.exception.BusinessException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

// §2.4 fix — Google Places calls are authenticated (so an
// anonymous scraper can't burn quota) but were otherwise
// uncapped: any signed-in account could hammer
// /api/places/autocomplete at ~$2.83/1000 requests, so a
// script at 10 req/s is ~$2,450/day. Same Redis
// per-day-counter pattern as OtpRateLimitService, keyed on
// the user instead of phone/IP.
@Slf4j
@Service
@RequiredArgsConstructor
public class PlacesRateLimitService {

    private final RedisTemplate<String, Object> redisTemplate;

    private static final String USER_DAY_PREFIX = "places:userday:";
    private static final Duration DAY = Duration.ofHours(24);

    @Value("${app.places.max-per-user-day:300}")
    private int maxPerUserDay;

    public void checkAndRecord(Long userId) {
        if (userId == null) {
            // No authenticated caller to key on — the endpoint is
            // already behind anyRequest().authenticated(), so this
            // shouldn't happen, but never block a real user over it.
            return;
        }

        try {
            String key = USER_DAY_PREFIX + userId;
            Long count = redisTemplate.opsForValue().increment(key);

            if (count != null && count == 1L) {
                redisTemplate.expire(key, DAY);
            }

            if (count != null && count > maxPerUserDay) {
                log.warn("Places API cap hit for user {} ({} calls today)",
                        userId, count);
                throw new BusinessException(
                        "Too many address searches today. Please try again tomorrow.");
            }

        } catch (BusinessException e) {
            throw e;
        } catch (Exception e) {
            // Redis unreachable — fail OPEN. Losing the spend cap for
            // a few minutes is a much smaller problem than taking
            // down address search (and every order flow that needs
            // it) over a Redis blip. Contrast with OtpRateLimitService,
            // which fails closed because an uncapped OTP endpoint can
            // drain the Twilio balance in seconds — Places abuse is
            // slower and cheaper per call.
            log.error("Places rate limiter unavailable, allowing call: {}",
                    e.getMessage());
        }
    }
}
