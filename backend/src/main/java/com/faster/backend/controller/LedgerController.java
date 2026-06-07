package com.faster.backend.controller;

import com.faster.backend.dto.LedgerResponse;
import com.faster.backend.entity.LedgerEntry;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.LedgerService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/ledger")
@RequiredArgsConstructor
public class LedgerController {

    private final LedgerService ledgerService;
    private final UserRepository userRepository;

    // ─── GET /api/ledger/my ───────────────────────────
    // Driver or merchant sees own ledger history
    @GetMapping("/my")
    public ResponseEntity<List<LedgerResponse>>
            getMyLedger(Authentication auth) {

        User user = getUser(auth);
        List<LedgerEntry> entries;

        if (user.getRole() == User.Role.DRIVER) {
            entries = ledgerService
                .getDriverLedger(user.getId());
        } else if (user.getRole()
                == User.Role.MERCHANT) {
            entries = ledgerService
                .getMerchantLedger(user.getId());
        } else {
            return ResponseEntity.badRequest().build();
        }

        List<LedgerResponse> response = entries
                .stream()
                .map(LedgerResponse::from)
                .collect(Collectors.toList());

        return ResponseEntity.ok(response);
    }

    // ─── GET /api/ledger/my/debt ──────────────────────
    // Driver sees current debt + block status
    @GetMapping("/my/debt")
    public ResponseEntity<?> getMyDebt(
            Authentication auth) {

        User user = getUser(auth);

        if (user.getRole() != User.Role.DRIVER) {
            return ResponseEntity.badRequest().body(
                Map.of("message",
                       "Only drivers have debt"));
        }

        return ResponseEntity.ok(
            ledgerService.getDriverDebtSummary(
                user.getId()));
    }

    // ─── Helper ───────────────────────────────────────
    private User getUser(Authentication auth) {
        String principal = auth.getName();
        return userRepository
                .findByEmail(principal)
                .orElseGet(() ->
                    userRepository.findByPhone(principal)
                        .orElseThrow(() ->
                            new RuntimeException(
                                "User not found")));
    }
}