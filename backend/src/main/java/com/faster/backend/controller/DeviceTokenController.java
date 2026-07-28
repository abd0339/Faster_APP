package com.faster.backend.controller;

import com.faster.backend.dto.DeviceTokenRequest;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.PushNotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Phase 4 (FCM) — lets any authenticated role (customer,
 * driver, merchant, admin) register the device they're
 * currently using so pushes can reach them. Called once
 * after login (and again whenever FCM rotates the token —
 * see PushNotificationService in Flutter for that).
 */
@RestController
@RequestMapping("/api/devices")
@RequiredArgsConstructor
public class DeviceTokenController {

    private final PushNotificationService pushNotificationService;
    private final UserRepository userRepository;

    // ─── POST /api/devices/register ───────────────────
    @PostMapping("/register")
    public ResponseEntity<?> register(
            @jakarta.validation.Valid @RequestBody DeviceTokenRequest req,
            Authentication auth) {

        Long userId = getUserId(auth);
        pushNotificationService.registerDevice(
                userId, req.getFcmToken(), req.getPlatform());

        return ResponseEntity.ok(Map.of(
                "message", "Device registered for push notifications"));
    }

    // ─── DELETE /api/devices/unregister?fcmToken=... ──
    // Called on logout so a signed-out device stops
    // receiving pushes meant for that user. Uses a query
    // param (not a body) to match the simple DELETE call
    // ApiService already supports.
    @DeleteMapping("/unregister")
    public ResponseEntity<?> unregister(
            @RequestParam String fcmToken,
            Authentication auth) {

        Long userId = getUserId(auth);
        pushNotificationService.unregisterDevice(userId, fcmToken);

        return ResponseEntity.ok(Map.of("message", "Device unregistered"));
    }

    private Long getUserId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository.findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new RuntimeException("User not found")));
        return user.getId();
    }
}