package com.faster.backend.controller;

import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Merchant-scoped customer lookup used during O2O order creation.
 *
 * SECURITY NOTE (was MEDIUM — customer enumeration):
 * This endpoint lets an authenticated merchant probe whether an arbitrary phone
 * number belongs to a registered customer, and returns the customer's full name.
 * A malicious merchant can iterate phone numbers to harvest names — a privacy /
 * enumeration risk. The response is intentionally minimal (found + name + phone),
 * but you MUST additionally:
 *   1. Require an EXACT, fully-formatted phone match (done — findByPhone is exact).
 *   2. Rate-limit this route hard at nginx (a dedicated limit_req zone, e.g.
 *      20 requests/minute per IP) — see the provided nginx.conf snippet.
 *   3. Consider not returning fullName at all: return only {found:true|false}
 *      and let the merchant type the name manually. That fully removes the
 *      harvest value. Toggle via app.merchant.lookup.reveal-name.
 */
@RestController
@RequestMapping("/api/merchant")
@RequiredArgsConstructor
public class MerchantCustomerController {

    private final UserRepository userRepository;

    @org.springframework.beans.factory.annotation.Value(
            "${app.merchant.lookup.reveal-name:false}")
    private boolean revealName;

    @GetMapping("/customer/lookup")
    public ResponseEntity<?> lookupCustomer(@RequestParam String phone) {

        // Normalize / basic sanity check to avoid partial-match probing.
        String normalized = phone == null ? "" : phone.trim();
        if (!normalized.matches("^\\+?[0-9]{7,15}$")) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "Invalid phone format"));
        }

        return userRepository.findByPhone(normalized)
                .filter(u -> u.getRole() == User.Role.CUSTOMER)
                .map(u -> revealName
                        ? ResponseEntity.ok(Map.of(
                                "found", true,
                                "fullName", u.getFullName(),
                                "phone", u.getPhone()))
                        : ResponseEntity.ok(Map.of(
                                "found", true,
                                "phone", u.getPhone())))
                .orElse(ResponseEntity.ok(Map.of(
                        "found", false,
                        "phone", normalized,
                        "message",
                        "Phone not registered — will create as offline customer")));
    }
}