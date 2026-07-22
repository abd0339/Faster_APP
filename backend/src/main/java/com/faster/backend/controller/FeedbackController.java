package com.faster.backend.controller;

import com.faster.backend.dto.OrderFeedbackRequest;
import com.faster.backend.entity.OrderFeedback;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.OrderFeedbackService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequiredArgsConstructor
public class FeedbackController {

    private final OrderFeedbackService feedbackService;
    private final UserRepository userRepository;

    // ─────────────────────────────────────────────────
    // POST /api/orders/{orderId}/feedback
    // Customer submits feedback right after delivery is
    // confirmed. Every field is optional — sending an empty
    // body is exactly what happens when the customer taps
    // "Skip" (Flutter just doesn't call this endpoint at all
    // in that case — see the tracking screen).
    // ─────────────────────────────────────────────────
    @PostMapping("/api/orders/{orderId}/feedback")
    public ResponseEntity<?> submitFeedback(
            @PathVariable Long orderId,
            @RequestBody OrderFeedbackRequest req,
            Authentication auth) {

        Long customerId = getUserId(auth);

        OrderFeedback feedback = feedbackService.submitFeedback(
                orderId,
                customerId,
                req.getDriverThumbsUp(),
                req.getNegativeNote(),
                req.getDriverStars(),
                req.getMerchantStars());

        return ResponseEntity.ok(Map.of(
                "message", "Thank you for your feedback!",
                "feedbackId", feedback.getId()));
    }

    // ─────────────────────────────────────────────────
    // GET /api/driver/rating — driver views their own
    // average rating (already-authenticated driver)
    // ─────────────────────────────────────────────────
    @GetMapping("/api/driver/rating")
    public ResponseEntity<?> getOwnDriverRating(Authentication auth) {
        Long driverId = getUserId(auth);
        return ResponseEntity.ok(
                feedbackService.getDriverRatingSummary(driverId));
    }

    // ─── Helper ───────────────────────────────────────
    private Long getUserId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository.findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new RuntimeException(
                                "User not found")));
        return user.getId();
    }
}