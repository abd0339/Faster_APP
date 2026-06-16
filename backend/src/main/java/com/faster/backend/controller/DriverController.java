package com.faster.backend.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.faster.backend.dto.DriverLocationRequest;
import com.faster.backend.dto.DriverStatusRequest;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.DriverService;
import com.faster.backend.service.LocationService;

import jakarta.validation.Valid;
import lombok.Data;
import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/driver")
@RequiredArgsConstructor
public class DriverController {

    private final DriverService driverService;
    private final LocationService locationService;
    private final UserRepository userRepository;

    // ─── POST /api/driver/online ──────────────────────
    @PostMapping("/online")
    public ResponseEntity<?> goOnline(
            @Valid @RequestBody DriverStatusRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = driverService.goOnline(
                driverId, req.getLat(), req.getLng(), req.getMode());

        return ResponseEntity.ok(Map.of(
                "message", "You are now online",
                "mode", driver.getDriverMode(),
                "isOnline", true));
    }

    // ─── POST /api/driver/offline ─────────────────────
    @PostMapping("/offline")
    public ResponseEntity<?> goOffline(Authentication auth) {
        Long driverId = getDriverId(auth);
        driverService.goOffline(driverId);
        return ResponseEntity.ok(Map.of(
                "message", "You are now offline",
                "isOnline", false));
    }

    // ─── PATCH /api/driver/mode ───────────────────────
    @PatchMapping("/mode")
    public ResponseEntity<?> switchMode(
            @Valid @RequestBody DriverStatusRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = driverService.switchMode(
                driverId, req.getMode(), req.getLat(), req.getLng());

        return ResponseEntity.ok(Map.of(
                "message", "Mode switched to " + req.getMode(),
                "mode", driver.getDriverMode()));
    }

    // ─── POST /api/driver/location ────────────────────
    @PostMapping("/location")
    public ResponseEntity<?> updateLocation(
            @Valid @RequestBody DriverLocationRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);

        if (!locationService.isDriverOnline(driverId)) {
            return ResponseEntity.badRequest().body(
                    Map.of("message", "You must be online first"));
        }

        locationService.updateLocation(
                driverId, req.getLat(), req.getLng());

        return ResponseEntity.ok(Map.of("message", "Location updated"));
    }

    // ─── GET /api/driver/status ───────────────────────
    // Returns driverId + online status + verificationStatus
    // Flutter uses verificationStatus to decide which screen to show
    @GetMapping("/status")
    public ResponseEntity<?> getStatus(Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new RuntimeException("Driver not found"));

        boolean isOnline = locationService.isDriverOnline(driverId);
        String mode = locationService.getDriverMode(driverId);

        return ResponseEntity.ok(Map.of(
                "driverId", driverId,
                "isOnline", isOnline,
                "mode", mode != null ? mode : "OFFLINE",
                "verificationStatus",
                driver.getVerificationStatus() != null
                        ? driver.getVerificationStatus().name()
                        : "PENDING",
                "vehicleType",
                driver.getVehicleType() != null
                        ? driver.getVehicleType() : "",
                "vehiclePlate",
                driver.getVehiclePlate() != null
                        ? driver.getVehiclePlate() : "",
                "isBlocked",
                Boolean.TRUE.equals(driver.getIsBlocked())));
    }

    // ─── POST /api/driver/profile (JSON body) ─────────
    // Driver submits vehicle info for admin review
    // Accepts JSON — NOT multipart
    @PostMapping("/profile")
    public ResponseEntity<?> submitProfile(
            @RequestBody DriverProfileRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new RuntimeException("Driver not found"));

        // Update vehicle info
        if (req.getVehicleType() != null) {
            driver.setVehicleType(req.getVehicleType());
        }
        if (req.getVehiclePlate() != null) {
            driver.setVehiclePlate(req.getVehiclePlate()
                    .toUpperCase().trim());
        }
        if (req.getDriverMode() != null) {
            try {
                driver.setDriverMode(User.DriverMode
                        .valueOf(req.getDriverMode()));
            } catch (Exception e) {
                driver.setDriverMode(User.DriverMode.PACKAGE);
            }
        }

        // Mark as SUBMITTED for admin review
        driver.setVerificationStatus(
                User.DriverVerificationStatus.SUBMITTED);

        userRepository.save(driver);

        return ResponseEntity.ok(Map.of(
                "message",
                "Profile submitted for review. "
                + "The admin will contact you on WhatsApp "
                + "once reviewed.",
                "verificationStatus", "SUBMITTED"));
    }

    // ─── WebSocket: Driver GPS via STOMP ──────────────
    @MessageMapping("/driver.location")
    public void handleWebSocketLocation(
            @Payload DriverLocationRequest req,
            Authentication auth) {

        if (auth == null) return;
        Long driverId = getDriverId(auth);
        locationService.updateLocation(
                driverId, req.getLat(), req.getLng());
    }

    // ─── Inner DTO for profile submission ─────────────
    @Data
    public static class DriverProfileRequest {
        private String vehicleType;  // MOTO / CAR / TOKTOK / VAN
        private String vehiclePlate;
        private String driverMode;   // PACKAGE / PEOPLE / HYBRID
        private Double currentLat;
        private Double currentLng;
        private String currentLocation;
    }

    // ─── Helper ───────────────────────────────────────
    private Long getDriverId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository.findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new RuntimeException(
                                "User not found")));
        return user.getId();
    }
}