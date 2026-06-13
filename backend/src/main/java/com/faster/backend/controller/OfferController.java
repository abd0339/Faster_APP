package com.faster.backend.controller;

import com.faster.backend.dto.OfferRequest;
import com.faster.backend.entity.Offer;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.OfferService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/merchant/offers")
@RequiredArgsConstructor
public class OfferController {

    private final OfferService offerService;
    private final UserRepository userRepository;

    // ─── POST /api/merchant/offers ────────────────────
    @PostMapping
    public ResponseEntity<?> createOffer(
            @Valid @RequestBody OfferRequest req,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Offer offer = offerService.createOffer(
                merchantId,
                req.getTitle(),
                req.getDescription(),
                req.getDiscountPercent(),
                req.getOfferType(),
                req.getStartDate(),
                req.getEndDate(),
                req.getUsageLimit(),
                req.getCategoryIds(),
                req.getItemIds());

        return ResponseEntity.ok(offer);
    }

    // ─── PUT /api/merchant/offers/{id} ────────────────
    @PutMapping("/{id}")
    public ResponseEntity<?> updateOffer(
            @PathVariable Long id,
            @Valid @RequestBody OfferRequest req,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Offer offer = offerService.updateOffer(
                merchantId,
                id,
                req.getTitle(),
                req.getDescription(),
                req.getDiscountPercent(),
                req.getOfferType(),
                req.getStartDate(),
                req.getEndDate(),
                req.getUsageLimit(),
                req.getCategoryIds(),
                req.getItemIds());

        return ResponseEntity.ok(offer);
    }

    // ─── GET /api/merchant/offers ─────────────────────
    @GetMapping
    public ResponseEntity<List<Offer>> getAllOffers(
            Authentication auth) {
        return ResponseEntity.ok(
            offerService.getAllOffers(getMerchantId(auth)));
    }

    // ─── GET /api/merchant/offers/live ────────────────
    @GetMapping("/live")
    public ResponseEntity<List<Offer>> getLiveOffers(
            Authentication auth) {
        return ResponseEntity.ok(
            offerService.getLiveOffers(getMerchantId(auth)));
    }

    // ─── PATCH /api/merchant/offers/{id}/toggle ───────
    @PatchMapping("/{id}/toggle")
    public ResponseEntity<?> toggleOffer(
            @PathVariable Long id,
            Authentication auth) {
        Offer offer = offerService
            .toggleOffer(getMerchantId(auth), id);
        return ResponseEntity.ok(Map.of(
            "message", "Offer status updated",
            "isActive", offer.getIsActive()
        ));
    }

    // ─── POST /api/merchant/offers/{id}/image ─────────
    @PostMapping("/{id}/image")
    public ResponseEntity<?> uploadOfferImage(
            @PathVariable Long id,
            @RequestParam("image") MultipartFile image,
            Authentication auth) {
        Offer offer = offerService
            .uploadOfferImage(getMerchantId(auth), id, image);
        return ResponseEntity.ok(Map.of(
            "message", "Offer image uploaded",
            "imageUrl", offer.getImageUrl()
        ));
    }

    // ─── DELETE /api/merchant/offers/{id} ─────────────
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteOffer(
            @PathVariable Long id,
            Authentication auth) {
        offerService.deleteOffer(getMerchantId(auth), id);
        return ResponseEntity.ok(Map.of(
            "message", "Offer deleted successfully"));
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