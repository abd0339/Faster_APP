package com.faster.backend.controller;

import com.faster.backend.dto.StoreScheduleRequest;
import com.faster.backend.entity.StoreSchedule;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.StoreScheduleService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/merchant/schedule")
@RequiredArgsConstructor
public class StoreScheduleController {

    private final StoreScheduleService scheduleService;
    private final UserRepository userRepository;

    // ─── POST /api/merchant/schedule ─────────────────
    @PostMapping
    public ResponseEntity<?> setSchedule(
            @Valid @RequestBody StoreScheduleRequest req,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);

        StoreSchedule schedule = scheduleService
                .setSchedule(
                    merchantId,
                    req.getDayOfWeek(),
                    req.getOpenTime(),
                    req.getCloseTime(),
                    req.getIsClosed());

        return ResponseEntity.ok(schedule);
    }

    // ─── GET /api/merchant/schedule ──────────────────
    @GetMapping
    public ResponseEntity<List<StoreSchedule>> getSchedule(
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        return ResponseEntity.ok(
            scheduleService.getSchedule(merchantId));
    }

    // ─── GET /api/merchant/schedule/status ───────────
    @GetMapping("/status")
    public ResponseEntity<?> getStoreStatus(
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        boolean isOpen = scheduleService
            .isStoreOpenNow(merchantId);

        return ResponseEntity.ok(Map.of(
            "isOpen", isOpen,
            "message", isOpen
                ? "Store is currently open"
                : "Store is currently closed"
        ));
    }

    // ─── Helper ───────────────────────────────────────
    private Long getMerchantId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository
                .findByEmail(principal)
                .orElseGet(() ->
                    userRepository.findByPhone(principal)
                        .orElseThrow(() ->
                            new RuntimeException(
                                "User not found")));
        return user.getId();
    }
}