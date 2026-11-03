package com.faster.backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.faster.backend.dto.ExchangeRateRequest;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.ExchangeRateService;

import lombok.RequiredArgsConstructor;

// ─────────────────────────────────────────────────────
// ExchangeRateController — current USD/LBP rate, readable
// by any authenticated user, settable by ADMIN only. The
// admin-only check is enforced by SecurityConfig's
// /api/admin/** → hasRole("ADMIN") matcher, not here.
// ─────────────────────────────────────────────────────
@RestController
@RequiredArgsConstructor
public class ExchangeRateController {

    private final ExchangeRateService exchangeRateService;
    private final AuthenticatedUserResolver authResolver;

    // ─── GET /api/exchange-rate ────────────────────────
    @GetMapping("/api/exchange-rate")
    public ResponseEntity<?> getRate() {
        return ResponseEntity.ok(Map.of(
                "usdToLbpRate", exchangeRateService.getCurrentRate()));
    }

    // ─── PUT /api/admin/exchange-rate ──────────────────
    @PutMapping("/api/admin/exchange-rate")
    public ResponseEntity<?> updateRate(
            @RequestBody ExchangeRateRequest req,
            Authentication auth) {

        Long adminId = authResolver.resolveId(auth);
        return ResponseEntity.ok(Map.of(
                "usdToLbpRate",
                exchangeRateService.updateRate(
                        req.getRate(), adminId, req.isConfirm())));
    }
}
