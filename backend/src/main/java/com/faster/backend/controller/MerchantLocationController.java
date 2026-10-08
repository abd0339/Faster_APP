package com.faster.backend.controller;

import com.faster.backend.dto.MerchantLocationRequest;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.MerchantLocationService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/merchant/location")
@RequiredArgsConstructor
public class MerchantLocationController {

    private final MerchantLocationService locationService;
    private final UserRepository userRepository;

    // ─── PUT /api/merchant/location ───────────────────
    // One-time (or whenever the store moves) map-pin set.
    // Used by PricingService as the pickup point for every
    // LOGISTICS order from this store, instead of the flat
    // minimum-fee fallback.
    @PutMapping
    public ResponseEntity<?> setLocation(
            @Valid @RequestBody MerchantLocationRequest req,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        User merchant = locationService.setLocation(
                merchantId, req.getLatitude(), req.getLongitude(), req.getAddress());

        return ResponseEntity.ok(Map.of(
                "storeLatitude", merchant.getStoreLatitude(),
                "storeLongitude", merchant.getStoreLongitude(),
                "storeAddress", merchant.getStoreAddress() != null
                        ? merchant.getStoreAddress() : ""));
    }

    // ─── GET /api/merchant/location ───────────────────
    @GetMapping
    public ResponseEntity<?> getLocation(Authentication auth) {
        Long merchantId = getMerchantId(auth);
        User merchant = locationService.getLocation(merchantId);

        return ResponseEntity.ok(Map.of(
                "storeLatitude", merchant.getStoreLatitude(),
                "storeLongitude", merchant.getStoreLongitude(),
                "storeAddress", merchant.getStoreAddress() != null
                        ? merchant.getStoreAddress() : ""));
    }

    // ─── Helper ───────────────────────────────────────
    private Long getMerchantId(Authentication auth) {
        String principal = auth.getName();
        return userRepository.findByEmail(principal)
                .orElseGet(() ->
                        userRepository.findByPhone(principal)
                                .orElseThrow(() ->
                                        new RuntimeException(
                                                "User not found")))
                .getId();
    }
}
