package com.faster.backend.controller;

import com.faster.backend.dto.ItemRequest;
import com.faster.backend.dto.SnoozeRequest;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.ItemService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/merchant/items")
@RequiredArgsConstructor
public class ItemController {

    private final ItemService itemService;
    private final UserRepository userRepository;

    // ─── POST /api/merchant/items ─────────────────────
    @PostMapping
    public ResponseEntity<?> createItem(
            @Valid @RequestBody ItemRequest request,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);

        Item item = itemService.createItem(
                merchantId,
                request.getCategoryId(),
                request.getName(),
                request.getDescription(),
                request.getPrice(),
                request.getStockQuantity(),
                request.getPrepTimeMinutes(),
                request.getTaxRate(),
                request.getServiceFee(),
                request.getDisplayOrder());

        return ResponseEntity.ok(item);
    }

    // ─── GET /api/merchant/items ──────────────────────
    @GetMapping
    public ResponseEntity<List<Item>> getItems(
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        return ResponseEntity.ok(
            itemService.getMerchantItems(merchantId));
    }

    // ─── GET /api/merchant/items/{id} ─────────────────
    @GetMapping("/{id}")
    public ResponseEntity<?> getItem(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        return ResponseEntity.ok(
            itemService.getItem(merchantId, id));
    }

    // ─── PUT /api/merchant/items/{id} ─────────────────
    @PutMapping("/{id}")
    public ResponseEntity<?> updateItem(
            @PathVariable Long id,
            @RequestBody ItemRequest request,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);

        Item updated = itemService.updateItem(
                merchantId,
                id,
                request.getName(),
                request.getDescription(),
                request.getPrice(),
                request.getStockQuantity(),
                request.getPrepTimeMinutes(),
                request.getCategoryId());

        return ResponseEntity.ok(updated);
    }

    // ─── DELETE /api/merchant/items/{id} ──────────────
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteItem(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        itemService.deleteItem(merchantId, id);

        return ResponseEntity.ok(
            Map.of("message",
                   "Item deleted successfully"));
    }

    // ─── PATCH /api/merchant/items/{id}/toggle ────────
    @PatchMapping("/{id}/toggle")
    public ResponseEntity<?> toggleAvailability(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Item item = itemService
            .toggleAvailability(merchantId, id);

        return ResponseEntity.ok(Map.of(
            "message", "Item availability updated",
            "isAvailable", item.getIsAvailable()
        ));
    }

    // ─── PATCH /api/merchant/items/{id}/snooze ────────
    @PatchMapping("/{id}/snooze")
    public ResponseEntity<?> snoozeItem(
            @PathVariable Long id,
            @Valid @RequestBody SnoozeRequest request,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Item item = itemService.snoozeItem(
            merchantId, id, request.getHours());

        return ResponseEntity.ok(Map.of(
            "message", "Item snoozed for "
                       + request.getHours() + " hour(s)",
            "snoozeUntil", item.getSnoozeUntil()
        ));
    }

    // ─── PATCH /api/merchant/items/{id}/unsnooze ─────
    @PatchMapping("/{id}/unsnooze")
    public ResponseEntity<?> unsnoozeItem(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        itemService.unsnoozeItem(merchantId, id);

        return ResponseEntity.ok(
            Map.of("message", "Item is available again"));
    }

    // ─── POST /api/merchant/items/{id}/image ──────────
    @PostMapping("/{id}/image")
    public ResponseEntity<?> uploadImage(
            @PathVariable Long id,
            @RequestParam("image") MultipartFile image,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Item item = itemService.uploadItemImage(
            merchantId, id, image);

        return ResponseEntity.ok(Map.of(
            "message", "Image uploaded successfully",
            "imageUrl", item.getImageUrl()
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