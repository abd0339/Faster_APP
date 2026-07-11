package com.faster.backend.controller;

import java.util.Map;

import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.faster.backend.dto.DriverLocationRequest;
import com.faster.backend.dto.DriverStatusRequest;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.ForbiddenException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.DriverService;
import com.faster.backend.service.FileStorageService;
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
    private final FileStorageService fileStorageService;

    // Every allowed document type — single source of truth
    // for validation, storage subfolder naming, and the
    // switch statements below.
    private static final java.util.Set<String> VALID_DOC_TYPES =
            java.util.Set.of(
                    "PROFILE_PHOTO",
                    "NATIONAL_ID",
                    "LICENSE_FRONT",
                    "LICENSE_BACK");

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
    // Also returns which documents are already uploaded (booleans
    // only — never raw paths) so the verification screen can show
    // "already uploaded" state instead of re-asking every time.
    @GetMapping("/status")
    public ResponseEntity<?> getStatus(Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException("Driver not found"));

        boolean isOnline = locationService.isDriverOnline(driverId);
        String mode = locationService.getDriverMode(driverId);

        // NOTE: Map.of() caps out at 10 key-value pairs (20 args).
        // This response needs 11, so Map.ofEntries() is used instead —
        // it has no such limit.
        return ResponseEntity.ok(Map.ofEntries(
                Map.entry("driverId", driverId),
                Map.entry("isOnline", isOnline),
                Map.entry("mode", mode != null ? mode : "OFFLINE"),
                Map.entry("verificationStatus",
                        driver.getVerificationStatus() != null
                                ? driver.getVerificationStatus().name()
                                : "PENDING"),
                Map.entry("vehicleType",
                        driver.getVehicleType() != null
                                ? driver.getVehicleType() : ""),
                Map.entry("vehiclePlate",
                        driver.getVehiclePlate() != null
                                ? driver.getVehiclePlate() : ""),
                Map.entry("isBlocked",
                        Boolean.TRUE.equals(driver.getIsBlocked())),
                Map.entry("hasProfilePhoto", driver.getDriverPhotoUrl() != null),
                Map.entry("hasNationalId", driver.getNationalIdUrl() != null),
                Map.entry("hasLicenseFront", driver.getDriverLicenseFrontUrl() != null),
                Map.entry("hasLicenseBack", driver.getDriverLicenseBackUrl() != null)));
    }

    // ─────────────────────────────────────────────────
    // POST /api/driver/documents/{docType}  (multipart)
    // Driver uploads one document at a time. docType is
    // one of PROFILE_PHOTO / NATIONAL_ID / LICENSE_FRONT /
    // LICENSE_BACK. Stored in PRIVATE storage — never
    // reachable via a public URL, only through the GET
    // endpoint below (self) or the admin equivalent.
    // ─────────────────────────────────────────────────
    @PostMapping("/documents/{docType}")
    public ResponseEntity<?> uploadDocument(
            @PathVariable String docType,
            @RequestParam("file") MultipartFile file,
            Authentication auth) {

        String type = docType.toUpperCase();
        if (!VALID_DOC_TYPES.contains(type)) {
            throw new BusinessException(
                    "Invalid document type. Must be one of "
                    + VALID_DOC_TYPES);
        }

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException("Driver not found"));

        String relativePath = fileStorageService
                .savePrivateImage(file, "drivers", driverId);

        switch (type) {
            case "PROFILE_PHOTO" -> driver.setDriverPhotoUrl(relativePath);
            case "NATIONAL_ID" -> driver.setNationalIdUrl(relativePath);
            case "LICENSE_FRONT" -> driver.setDriverLicenseFrontUrl(relativePath);
            case "LICENSE_BACK" -> driver.setDriverLicenseBackUrl(relativePath);
            default -> throw new BusinessException("Invalid document type");
        }

        userRepository.save(driver);

        return ResponseEntity.ok(Map.of(
                "message", type + " uploaded successfully",
                "docType", type));
    }

    // ─────────────────────────────────────────────────
    // GET /api/driver/documents/{docType}
    // Driver views their OWN uploaded document. Streams
    // the actual image bytes — this endpoint requires a
    // valid JWT (enforced by SecurityConfig's DRIVER role
    // rule on /api/driver/**), so the file can never be
    // fetched without authentication regardless of URL
    // guessing.
    // ─────────────────────────────────────────────────
    @GetMapping("/documents/{docType}")
    public ResponseEntity<Resource> viewOwnDocument(
            @PathVariable String docType,
            Authentication auth) {

        String type = docType.toUpperCase();
        if (!VALID_DOC_TYPES.contains(type)) {
            throw new BusinessException("Invalid document type");
        }

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException("Driver not found"));

        String relativePath = resolveDocPath(driver, type);
        Resource resource = fileStorageService.loadPrivateImage(relativePath);

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(
                        guessContentType(relativePath)))
                .body(resource);
    }

    // ─── POST /api/driver/profile (JSON body) ─────────
    // Driver submits vehicle info for admin review.
    //
    // FIX: previously this marked the driver SUBMITTED with
    // zero documents on file — the admin had to collect ID
    // photos manually over WhatsApp. Now profile photo and
    // national ID are required before SUBMITTED; license
    // front/back stay optional (product decision — driver's
    // license isn't blocking, matches "not necessary now").
    // ─────────────────────────────────────────────────
    @PostMapping("/profile")
    public ResponseEntity<?> submitProfile(
            @RequestBody DriverProfileRequest req,
            Authentication auth) {

        Long driverId = getDriverId(auth);
        User driver = userRepository.findById(driverId)
                .orElseThrow(() -> new NotFoundException("Driver not found"));

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

        // Required documents check — the actual fix
        if (driver.getDriverPhotoUrl() == null
                || driver.getNationalIdUrl() == null) {
            throw new BusinessException(
                    "Please upload your profile photo and "
                    + "national ID before submitting for review.");
        }

        driver.setVerificationStatus(
                User.DriverVerificationStatus.SUBMITTED);

        userRepository.save(driver);

        return ResponseEntity.ok(Map.of(
                "message",
                "Profile submitted for review. "
                + "The admin will review your documents shortly.",
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

    // ─── Helpers ───────────────────────────────────────
    private String resolveDocPath(User driver, String type) {
        String path = switch (type) {
            case "PROFILE_PHOTO" -> driver.getDriverPhotoUrl();
            case "NATIONAL_ID" -> driver.getNationalIdUrl();
            case "LICENSE_FRONT" -> driver.getDriverLicenseFrontUrl();
            case "LICENSE_BACK" -> driver.getDriverLicenseBackUrl();
            default -> null;
        };
        if (path == null) {
            throw new NotFoundException(
                    "No " + type.toLowerCase().replace("_", " ")
                    + " uploaded yet");
        }
        return path;
    }

    private String guessContentType(String path) {
        String lower = path.toLowerCase();
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".gif")) return "image/gif";
        if (lower.endsWith(".webp")) return "image/webp";
        return "image/jpeg";
    }

    private Long getDriverId(Authentication auth) {
        String principal = auth.getName();
        User user = userRepository.findByEmail(principal)
                .orElseGet(() -> userRepository.findByPhone(principal)
                        .orElseThrow(() -> new NotFoundException(
                                "User not found")));
        return user.getId();
    }
}