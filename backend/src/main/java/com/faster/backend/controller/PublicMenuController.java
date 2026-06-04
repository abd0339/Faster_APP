package com.faster.backend.controller;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.MenuCacheService;
import com.faster.backend.service.OfferService;
import com.faster.backend.service.StoreScheduleService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

// ─── PUBLIC — No JWT needed ───────────────────────────
// This is what customers see when they open a store
@RestController
@RequestMapping("/api/store")
@RequiredArgsConstructor
public class PublicMenuController {

    private final MenuCacheService menuCacheService;
    private final StoreScheduleService scheduleService;
    private final OfferService offerService;
    private final UserRepository userRepository;

    // ─── GET /api/store/{merchantId}/menu ─────────────
    // Returns full cached menu for a merchant
    @GetMapping("/{merchantId}/menu")
    public ResponseEntity<?> getMenu(
            @PathVariable Long merchantId) {

        // Verify merchant exists
        userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Store not found"));

        List<Category> menu = menuCacheService
            .getFullMenu(merchantId);

        boolean isOpen = scheduleService
            .isStoreOpenNow(merchantId);

        return ResponseEntity.ok(Map.of(
            "isOpen", isOpen,
            "menu", menu,
            "message", isOpen
                ? "Store is open"
                : "Store is closed — you can pre-order"
        ));
    }

    // ─── GET /api/store/{merchantId}/status ───────────
    @GetMapping("/{merchantId}/status")
    public ResponseEntity<?> getStoreStatus(
            @PathVariable Long merchantId) {

        boolean isOpen = scheduleService
            .isStoreOpenNow(merchantId);

        return ResponseEntity.ok(Map.of(
            "merchantId", merchantId,
            "isOpen", isOpen
        ));
    }

    // ─── GET /api/store/{merchantId}/offers ───────────
    @GetMapping("/{merchantId}/offers")
    public ResponseEntity<?> getLiveOffers(
            @PathVariable Long merchantId) {

        return ResponseEntity.ok(
            offerService.getLiveOffers(merchantId));
    }
}