package com.faster.backend.service;

import com.faster.backend.exception.BusinessException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Slf4j
@Service
@RequiredArgsConstructor
public class OtpRateLimitService {

    private final RedisTemplate<String, Object> redisTemplate;

    private static final String COOLDOWN_PREFIX  = "otp:cooldown:";
    private static final String PHONE_DAY_PREFIX = "otp:phoneday:";
    private static final String IP_DAY_PREFIX    = "otp:ipday:";

    private static final Duration DAY = Duration.ofHours(24);

    // Tunable from .env without a rebuild — if a limit turns out to
    // be wrong in production you do not want to be waiting on a
    // Maven build to fix it.
    @Value("${app.otp.cooldown-seconds:60}")
    private long cooldownSeconds;

    @Value("${app.otp.max-per-phone-day:5}")
    private int maxPerPhoneDay;

    @Value("${app.otp.max-per-ip-day:50}")
    private int maxPerIpDay;

    /**
     * Call this BEFORE sending an OTP. Throws BusinessException with a
     * user-facing message if the send is not allowed.
     *
     * @param phone E.164 phone number the OTP would go to
     * @param ip    caller's real IP address, or null if unavailable
     */
    public void checkAndRecord(String phone, String ip) {

        if (phone == null || phone.isBlank()) {
            // Nothing to key on. The callers already reject blank
            // phones, so this is belt-and-braces.
            throw new BusinessException("A phone number is required.");
        }

        try {
            // ─── Layer 1: per-phone cooldown ──────────────
            String cooldownKey = COOLDOWN_PREFIX + phone;
            Long ttl = redisTemplate.getExpire(cooldownKey, TimeUnit.SECONDS);

            if (ttl != null && ttl > 0) {
                throw new BusinessException(
                        "Please wait " + ttl + " seconds before "
                                + "requesting another code.");
            }

            // ─── Layer 2: per-phone daily cap ─────────────
            String phoneDayKey = PHONE_DAY_PREFIX + phone;
            Long phoneCount = redisTemplate.opsForValue().increment(phoneDayKey);

            if (phoneCount != null && phoneCount == 1L) {
                // First send in this window — start the 24h clock.
                // Without this the key would live forever.
                redisTemplate.expire(phoneDayKey, DAY);
            }

            if (phoneCount != null && phoneCount > maxPerPhoneDay) {
                log.warn("OTP phone cap hit for {} ({} attempts)",
                        maskPhone(phone), phoneCount);
                throw new BusinessException(
                        "Too many verification codes requested for this "
                                + "number today. Please try again tomorrow "
                                + "or contact support.");
            }

            // ─── Layer 3: per-IP daily cap ────────────────
            if (isUsableClientIp(ip)) {
                String ipDayKey = IP_DAY_PREFIX + ip;
                Long ipCount = redisTemplate.opsForValue().increment(ipDayKey);

                if (ipCount != null && ipCount == 1L) {
                    redisTemplate.expire(ipDayKey, DAY);
                }

                if (ipCount != null && ipCount > maxPerIpDay) {
                    log.warn("OTP IP cap hit for {} ({} attempts) — "
                            + "possible SMS flooding", ip, ipCount);
                    throw new BusinessException(
                            "Too many verification codes requested from "
                                    + "this network today. Please try again "
                                    + "tomorrow or contact support.");
                }
            } else {
                // Logged at debug, not warn: this fires on every
                // single send when the proxy header is missing, and
                // a warning per request would bury the log.
                log.debug("Per-IP OTP cap skipped — no usable client "
                        + "IP (got: {}). Check nginx X-Forwarded-For.", ip);
            }

            // ─── Allowed — arm the cooldown ───────────────
            redisTemplate.opsForValue().set(
                    cooldownKey, "1", cooldownSeconds, TimeUnit.SECONDS);

        } catch (BusinessException e) {
            // A real rejection — pass it through to the user.
            throw e;

        } catch (Exception e) {
            // Redis unreachable. Fail CLOSED — see the class comment.
            log.error("OTP rate limiter unavailable, refusing send: {}",
                    e.getMessage());
            throw new BusinessException(
                    "Verification is temporarily unavailable. "
                            + "Please try again in a few minutes.");
        }
    }

    /**
     * Clears the cooldown and daily count for a phone number. Called
     * after a SUCCESSFUL verification, so a user who signs up,
     * verifies, and later needs a fresh code is not still carrying
     * the count from their first signup.
     */
    public void clear(String phone) {
        if (phone == null || phone.isBlank()) {
            return;
        }
        try {
            redisTemplate.delete(COOLDOWN_PREFIX + phone);
            redisTemplate.delete(PHONE_DAY_PREFIX + phone);
        } catch (Exception e) {
            // Best effort — a stale counter is a minor annoyance, not
            // a reason to fail a successful verification.
            log.error("Could not clear OTP limits for {}: {}",
                    maskPhone(phone), e.getMessage());
        }
    }

    // A loopback or private address means we are seeing nginx, not
    // the user. Counting those would lump every user together.
    private boolean isUsableClientIp(String ip) {
        if (ip == null || ip.isBlank() || "unknown".equalsIgnoreCase(ip)) {
            return false;
        }
        return !(ip.startsWith("127.")
                || ip.startsWith("10.")
                || ip.startsWith("192.168.")
                || ip.startsWith("172.16.")
                || ip.startsWith("172.17.")
                || ip.startsWith("172.18.")
                || ip.startsWith("::1")
                || "0:0:0:0:0:0:0:1".equals(ip));
    }

    // Never log a full phone number.
    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 5) {
            return "***";
        }
        return phone.substring(0, 4) + "****"
                + phone.substring(phone.length() - 2);
    }
}