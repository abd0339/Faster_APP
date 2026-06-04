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
            @Valid @RequestBody OfferRequest request,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);

        Offer offer = offerService.createOffer(
                merchantId,
                request.getTitle(),
                request.getDescription(),
                request.getDiscountPercent(),
                request.getOfferType(),
                request.getStartDate(),
                request.getEndDate(),
                request.getUsageLimit());

        return ResponseEntity.ok(offer);
    }

    // ─── GET /api/merchant/offers ─────────────────────
    @GetMapping
    public ResponseEntity<List<Offer>> getAllOffers(
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        return ResponseEntity.ok(
            offerService.getAllOffers(merchantId));
    }

    // ─── GET /api/merchant/offers/live ────────────────
    @GetMapping("/live")
    public ResponseEntity<List<Offer>> getLiveOffers(
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        return ResponseEntity.ok(
            offerService.getLiveOffers(merchantId));
    }

    // ─── PATCH /api/merchant/offers/{id}/toggle ───────
    @PatchMapping("/{id}/toggle")
    public ResponseEntity<?> toggleOffer(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = getMerchantId(auth);
        Offer offer = offerService
            .toggleOffer(merchantId, id);

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

        Long merchantId = getMerchantId(auth);
        Offer offer = offerService.uploadOfferImage(
            merchantId, id, image);

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

        Long merchantId = getMerchantId(auth);
        offerService.deleteOffer(merchantId, id);

        return ResponseEntity.ok(
            Map.of("message",
                   "Offer deleted successfully"));
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