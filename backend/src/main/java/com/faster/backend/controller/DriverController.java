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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.faster.backend.dto.DriverLocationRequest;
import com.faster.backend.dto.DriverStatusRequest;
import com.faster.backend.entity.User;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.DriverService;
import com.faster.backend.service.FileStorageService;
import com.faster.backend.service.LocationService;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;

@RestController
@RequestMapping("/api/driver")
@RequiredArgsConstructor
public class DriverController {

    private final DriverService driverService;
    private final LocationService locationService;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;

    // ─── POST /api/driver/online ──────────────────────
    // Driver goes online with GPS + mode
    @PostMapping("/online")
    public ResponseEntity<?> goOnline(
            @Valid @RequestBody DriverStatusRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);

        User driver = driverService.goOnline(
                driverId,
                req.getLat(),
                req.getLng(),
                req.getMode());

        return ResponseEntity.ok(Map.of(
                "message", "You are now online",
                "mode", driver.getDriverMode(),
                "isOnline", true));
    }

    // ─── POST /api/driver/offline ─────────────────────
    @PostMapping("/offline")
    public ResponseEntity<?> goOffline(
            Authentication auth) {

        Long driverId = getDriverId(auth);
        driverService.goOffline(driverId);

        return ResponseEntity.ok(Map.of(
                "message", "You are now offline",
                "isOnline", false));
    }

    // ─── PATCH /api/driver/mode ───────────────────────
    // Switch mode while staying online
    @PatchMapping("/mode")
    public ResponseEntity<?> switchMode(
            @Valid @RequestBody DriverStatusRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);

        User driver = driverService.switchMode(
                driverId,
                req.getMode(),
                req.getLat(),
                req.getLng());

        return ResponseEntity.ok(Map.of(
                "message", "Mode switched to " + req.getMode(),
                "mode", driver.getDriverMode()));
    }

    // ─── POST /api/driver/location ────────────────────
    // Driver sends GPS update (every 5 seconds)
    @PostMapping("/location")
    public ResponseEntity<?> updateLocation(
            @Valid @RequestBody DriverLocationRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);

        // Only update if driver is online
        if (!locationService.isDriverOnline(driverId)) {
            return ResponseEntity.badRequest().body(
                    Map.of("message",
                            "You must be online first"));
        }

        locationService.updateLocation(
                driverId, req.getLat(), req.getLng());

        return ResponseEntity.ok(
                Map.of("message", "Location updated"));
    }

    // ─── GET /api/driver/status ───────────────────────
    @GetMapping("/status")
    public ResponseEntity<?> getStatus(
            Authentication auth) {

        Long driverId = getDriverId(auth);
        boolean isOnline = locationService.isDriverOnline(driverId);
        String mode = locationService.getDriverMode(driverId);

        return ResponseEntity.ok(Map.of(
                "isOnline", isOnline,
                "mode", mode != null ? mode : "OFFLINE"));
    }

    // ─── WebSocket: Driver sends GPS via STOMP ────────
    // Flutter sends to: /app/driver.location
    @MessageMapping("/driver.location")
    public void handleWebSocketLocation(
            @Payload DriverLocationRequest req,
            Authentication auth) {

        if (auth == null)
            return;
        Long driverId = getDriverId(auth);
        locationService.updateLocation(
                driverId, req.getLat(), req.getLng());
    }

    // ─── POST /api/driver/profile ─────────────────────────
    // Driver submits their vehicle info + documents
    @PostMapping("/profile")
    public ResponseEntity<?> submitProfile(
            @RequestParam String vehicleType,
            @RequestParam String vehiclePlate,
            @RequestParam(required = false) MultipartFile driverPhoto,
            @RequestParam(required = false) MultipartFile nationalId,
            @RequestParam(required = false) MultipartFile vehiclePaper,
            Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new RuntimeException("Driver not found"));

        driver.setVehicleType(vehicleType);
        driver.setVehiclePlate(vehiclePlate);

        // Save uploaded documents
        if (driverPhoto != null) {
            String url = fileStorageService
                    .saveImage(driverPhoto, "drivers");
            driver.setDriverPhotoUrl(url);
        }
        if (nationalId != null) {
            String url = fileStorageService
                    .saveImage(nationalId, "drivers");
            driver.setNationalIdUrl(url);
        }
        if (vehiclePaper != null) {
            String url = fileStorageService
                    .saveImage(vehiclePaper, "drivers");
            driver.setVehiclePaperUrl(url);
        }

        // Mark as submitted for admin review
        driver.setVerificationStatus(
                User.DriverVerificationStatus.SUBMITTED);
        userRepository.save(driver);

        return ResponseEntity.ok(Map.of(
                "message",
                "Profile submitted for review. " +
                        "You will be notified once approved.",
                "status", "SUBMITTED"));
    }

    // ─── Helper ───────────────────────────────────────
    private Long getDriverId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository
                .findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new RuntimeException(
                                "User not found")));
        return user.getId();
    }
}