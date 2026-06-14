package com.faster.backend.controller;

import com.faster.backend.dto.PublicMenuDTO;
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

        // ─── GET /api/store/all ───────────────────────────
        // PUBLIC — Returns all active merchants for customer browse
        @GetMapping("/all")
        public ResponseEntity<?> getAllMerchants() {

                List<User> merchants = userRepository
                                .findByRoleAndIsActiveTrue(User.Role.MERCHANT);

                // Return only safe public fields
                List<Map<String, Object>> result = merchants.stream()
                                .filter(m -> !Boolean.TRUE.equals(m.getIsBlocked()))
                                .map(m -> {
                                        Map<String, Object> data = new java.util.HashMap<>();
                                        data.put("id", m.getId());
                                        data.put("fullName", m.getFullName());
                                        data.put("phone", m.getPhone());
                                        // Check if store is open right now
                                        boolean isOpen = scheduleService
                                                        .isStoreOpenNow(m.getId());
                                        data.put("isOpen", isOpen);
                                        return data;
                                })
                                .toList();

                return ResponseEntity.ok(result);
        }

        // ─── GET /api/store/{merchantId}/menu ─────────────
        // Returns full cached menu for a merchant
        @GetMapping("/{merchantId}/menu")
        public ResponseEntity<?> getMenu(
                        @PathVariable Long merchantId) {

                userRepository.findById(merchantId)
                                .orElseThrow(() -> new RuntimeException(
                                                "Store not found"));

                List<Category> rawCategories = menuCacheService
                                .getFullMenu(merchantId);

                boolean isOpen = scheduleService
                                .isStoreOpenNow(merchantId);

                // ─── Map to safe public DTO (includes items) ──
                List<PublicMenuDTO.CategoryDTO> menu = rawCategories
                                .stream()
                                .filter(cat -> Boolean.TRUE.equals(
                                                cat.getIsActive()))
                                .map(cat -> {
                                        List<PublicMenuDTO.ItemDTO> itemDTOs = cat.getItems() == null
                                                        ? java.util.List.of()
                                                        : cat.getItems().stream()
                                                                        .filter(item -> Boolean.TRUE.equals(
                                                                                        item.getIsAvailable())
                                                                                        && !Boolean.TRUE.equals(
                                                                                                        item.getIsSnoozed()))
                                                                        .sorted(java.util.Comparator
                                                                                        .comparingInt(item -> item
                                                                                                        .getDisplayOrder() != null
                                                                                                                        ? item.getDisplayOrder()
                                                                                                                        : 0))
                                                                        .map(item -> PublicMenuDTO.ItemDTO.builder()
                                                                                        .id(item.getId())
                                                                                        .name(item.getName())
                                                                                        .description(
                                                                                                        item.getDescription())
                                                                                        .price(item.getPrice())
                                                                                        .imageUrl(
                                                                                                        item.getImageUrl())
                                                                                        .isAvailable(
                                                                                                        item.getIsAvailable())
                                                                                        .isSnoozed(
                                                                                                        item.getIsSnoozed())
                                                                                        .prepTimeMinutes(
                                                                                                        item.getPrepTimeMinutes())
                                                                                        .stockQuantity(
                                                                                                        item.getStockQuantity())
                                                                                        .displayOrder(
                                                                                                        item.getDisplayOrder())
                                                                                        .build())
                                                                        .toList();

                                        return PublicMenuDTO.CategoryDTO.builder()
                                                        .id(cat.getId())
                                                        .name(cat.getName())
                                                        .icon(cat.getIcon())
                                                        .displayOrder(cat.getDisplayOrder())
                                                        .items(itemDTOs)
                                                        .build();
                                })
                                .toList();

                return ResponseEntity.ok(Map.of(
                                "isOpen", isOpen,
                                "menu", menu,
                                "message", isOpen
                                                ? "Store is open"
                                                : "Store is closed — you can pre-order"));
        }

        // ─── GET /api/store/{merchantId}/status ───────────
        @GetMapping("/{merchantId}/status")
        public ResponseEntity<?> getStoreStatus(
                        @PathVariable Long merchantId) {

                boolean isOpen = scheduleService
                                .isStoreOpenNow(merchantId);

                return ResponseEntity.ok(Map.of(
                                "merchantId", merchantId,
                                "isOpen", isOpen));
        }

        // ─── GET /api/store/{merchantId}/offers ───────────
        @GetMapping("/{merchantId}/offers")
        public ResponseEntity<?> getLiveOffers(
                        @PathVariable Long merchantId) {

                return ResponseEntity.ok(
                                offerService.getLiveOffers(merchantId));
        }
}