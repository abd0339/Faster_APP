package com.faster.backend.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import com.faster.backend.entity.ExchangeRate;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.ExchangeRateRepository;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

// ─────────────────────────────────────────────────────
// ExchangeRateService — reads/updates the single admin-settable
// USD/LBP exchange rate row (id = 1L, seeded by
// infra/migrations/0004_add_exchange_rate.sql) and broadcasts
// every change over WebSocket so connected clients (pricing
// screens, etc.) can react live.
// ─────────────────────────────────────────────────────
@Service
@RequiredArgsConstructor
@Slf4j
public class ExchangeRateService {

    // Singleton row id — never auto-generated, always this.
    private static final Long RATE_ROW_ID = 1L;

    // Mirrors the DB column's actual
    // representable range (infra/migrations/0004_add_exchange_rate.sql:
    // usd_to_lbp_rate NUMERIC(14,2) — 12 integer digits, 2 decimal
    // digits). Without these bounds: a value above MAX_RATE either
    // crashes with a raw DataIntegrityViolationException once it
    // actually reaches Postgres (caught only generically, as a leaky
    // 400), and a positive value below MIN_RATE silently rounds to
    // 0.00 once the DB truncates it to scale 2 — a "successful" update
    // to a zero rate, which would then divide-by-zero everywhere
    // downstream (CurrencyConverter.lbpToUsd).
    private static final BigDecimal MIN_RATE = new BigDecimal("0.01");
    private static final BigDecimal MAX_RATE = new BigDecimal("999999999999.99");

    // SANITY GUARD (final whole-branch review, finding #3) — MIN_RATE/
    // MAX_RATE above are just the DB column's representable range, not
    // a plausibility check: nothing stopped an admin fat-fingering
    // "89.5" instead of "89500" and silently corrupting every
    // LBP-priced order's conversion until someone noticed. This bounds
    // how much a single update may move the rate, as a fraction of the
    // CURRENT rate, before requiring an explicit confirm. Configurable
    // (not hardcoded) per the review's request.
    @Value("${exchange-rate.sanity-change-ratio:0.50}")
    private BigDecimal sanityChangeRatio;

    private final ExchangeRateRepository exchangeRateRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final PricingService pricingService;

    // ─── Current rate ──────────────────────────────────
    // Absence of the row means the migration wasn't run —
    // that should be loud (NotFoundException), never silently
    // defaulted to some hardcoded rate.
    public BigDecimal getCurrentRate() {
        return loadRate().getUsdToLbpRate();
    }

    // ─── Admin updates the rate ────────────────────────
    // Legacy 2-arg overload — always runs the sanity guard (confirm
    // defaults to false). The controller calls the 3-arg overload
    // directly so it can pass the admin's explicit confirmation.
    public BigDecimal updateRate(BigDecimal newRate, Long updatedByAdminId) {
        return updateRate(newRate, updatedByAdminId, false);
    }

    public BigDecimal updateRate(
            BigDecimal newRate, Long updatedByAdminId, boolean confirm) {
        if (newRate == null || newRate.compareTo(BigDecimal.ZERO) <= 0) {
            throw new BusinessException(
                    "Exchange rate must be greater than 0");
        }

        if (newRate.compareTo(MIN_RATE) < 0) {
            throw new BusinessException(
                    "Exchange rate must be at least " + MIN_RATE);
        }

        if (newRate.compareTo(MAX_RATE) > 0) {
            throw new BusinessException(
                    "Exchange rate of " + newRate
                    + " is too large (max " + MAX_RATE + ")");
        }

        // A value can sit well within MIN_RATE/MAX_RATE by magnitude while
        // still carrying an enormous scale (e.g. many trailing fractional
        // digits) — the bounds check above is a cheap compareTo regardless
        // of scale, but setScale below is not. Reject before it runs, same
        // guard OrderService uses before its own setScale calls.
        pricingService.rejectIfScaleIsDangerous(newRate);

        // Round to the column's actual scale here, explicitly, rather
        // than relying on the DB to do it silently — same convention
        // OrderService uses everywhere else for money (setScale(2,
        // HALF_UP) before persisting).
        newRate = newRate.setScale(2, RoundingMode.HALF_UP);

        ExchangeRate rate = loadRate();
        BigDecimal currentRate = rate.getUsdToLbpRate();

        // SANITY GUARD — see field comment above. Skipped only when the
        // admin has explicitly confirmed, or there's no sensible
        // "current rate" to compare against yet (defensive; the row
        // always exists once migrated, but a zero/negative stored rate
        // would make the ratio meaningless rather than wrong).
        if (!confirm && currentRate != null
                && currentRate.compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal changeRatio = newRate.subtract(currentRate)
                    .abs()
                    .divide(currentRate, 4, RoundingMode.HALF_UP);

            if (changeRatio.compareTo(sanityChangeRatio) > 0) {
                BigDecimal changePercent = changeRatio
                        .multiply(new BigDecimal("100"))
                        .setScale(1, RoundingMode.HALF_UP);
                throw new BusinessException(
                        "New rate " + newRate + " is a " + changePercent
                        + "% change from the current rate of " + currentRate
                        + " — resubmit with confirm:true if this change is intentional");
            }
        }

        rate.setUsdToLbpRate(newRate);
        rate.setUpdatedAt(LocalDateTime.now());
        rate.setUpdatedByAdminId(updatedByAdminId);

        ExchangeRate saved = exchangeRateRepository.save(rate);

        messagingTemplate.convertAndSend(
                "/topic/exchange-rate",
                Map.of(
                        "usdToLbpRate", saved.getUsdToLbpRate(),
                        "updatedAt", saved.getUpdatedAt()));

        log.info("Exchange rate updated to {} by admin {}",
                saved.getUsdToLbpRate(), updatedByAdminId);

        return saved.getUsdToLbpRate();
    }

    private ExchangeRate loadRate() {
        return exchangeRateRepository.findById(RATE_ROW_ID)
                .orElseThrow(() -> new NotFoundException(
                        "Exchange rate not found — has migration 0004 "
                                + "been run?"));
    }
}
