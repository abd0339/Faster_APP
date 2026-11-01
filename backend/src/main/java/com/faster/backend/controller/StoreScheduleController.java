package com.faster.backend.controller;

import com.faster.backend.dto.StoreScheduleRequest;
import com.faster.backend.entity.StoreSchedule;
import com.faster.backend.security.AuthenticatedUserResolver;
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
    private final AuthenticatedUserResolver authResolver;

    // ─── POST /api/merchant/schedule (single day) ────
    @PostMapping
    public ResponseEntity<?> setSchedule(
            @Valid @RequestBody StoreScheduleRequest req,
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);
        StoreSchedule schedule = scheduleService.setSchedule(
                merchantId,
                req.getDayOfWeek(),
                req.getOpenTime(),
                req.getCloseTime(),
                req.getIsClosed());

        return ResponseEntity.ok(schedule);
    }

    // ─── POST /api/merchant/schedule/bulk ────────────
    // Save all 7 days in one call
    @PostMapping("/bulk")
    public ResponseEntity<?> setBulkSchedule(
            @RequestBody List<StoreScheduleRequest> requests,
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);

        for (StoreScheduleRequest req : requests) {
            if (req.getDayOfWeek() == null) continue;
            scheduleService.setSchedule(
                    merchantId,
                    req.getDayOfWeek(),
                    req.getOpenTime(),
                    req.getCloseTime(),
                    req.getIsClosed());
        }

        return ResponseEntity.ok(Map.of(
            "message", "Schedule updated successfully",
            "days", requests.size()
        ));
    }

    // ─── GET /api/merchant/schedule ──────────────────
    @GetMapping
    public ResponseEntity<List<StoreSchedule>> getSchedule(
            Authentication auth) {
        Long merchantId = authResolver.resolveId(auth);
        return ResponseEntity.ok(
            scheduleService.getSchedule(merchantId));
    }

    // ─── GET /api/merchant/schedule/status ───────────
    @GetMapping("/status")
    public ResponseEntity<?> getStoreStatus(
            Authentication auth) {
        Long merchantId = authResolver.resolveId(auth);
        boolean isOpen = scheduleService
            .isStoreOpenNow(merchantId);
        return ResponseEntity.ok(Map.of(
            "isOpen", isOpen,
            "message", isOpen
                ? "Store is currently open"
                : "Store is currently closed"
        ));
    }
}