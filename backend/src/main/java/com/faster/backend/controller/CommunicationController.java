package com.faster.backend.controller;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.entity.User;
import com.faster.backend.repository.MessageLogRepository;
import com.faster.backend.repository.UserRepository;
import com.faster.backend.service.CommunicationService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

// ─────────────────────────────────────────────────────
// CommunicationController
//
// Admin-only endpoints for manual message triggers.
// All routes under /api/admin/notify/**
//
// The 3 actions admin can trigger manually:
//   1. Notify driver of their debt balance
//   2. Send announcement to a phone number
//   3. View the full message log for audit
// ─────────────────────────────────────────────────────
@RestController
@RequestMapping("/api/admin/notify")
@RequiredArgsConstructor
public class CommunicationController {

    private final CommunicationService communicationService;
    private final MessageLogRepository messageLogRepository;
    private final UserRepository userRepository;

    // ─────────────────────────────────────────────────
    // POST /api/admin/notify/driver-debt/{driverId}
    //
    // Admin manually clicks "Notify Driver" on the
    // debt management page. Sends a WhatsApp/SMS message
    // to the driver about their outstanding balance.
    // ─────────────────────────────────────────────────
    @PostMapping("/driver-debt/{driverId}")
    public ResponseEntity<?> notifyDriverDebt(
            @PathVariable Long driverId) {

        User driver = userRepository.findById(driverId)
                .orElseThrow(() ->
                        new RuntimeException("Driver not found"));

        if (driver.getRole() != User.Role.DRIVER) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "User is not a driver"));
        }

        BigDecimal debt = driver.getDebtAmount() != null
                ? driver.getDebtAmount()
                : BigDecimal.ZERO;

        communicationService.sendDriverDebtNotification(
                driver,
                debt.toPlainString()
        );

        return ResponseEntity.ok(Map.of(
                "message", "Debt notification sent to "
                        + driver.getFullName(),
                "phone", driver.getPhone(),
                "amountDue", debt
        ));
    }

    // ─────────────────────────────────────────────────
    // POST /api/admin/notify/announcement
    //
    // Admin sends a broadcast message to a specific
    // phone number (or use a list endpoint for bulk).
    //
    // Body: { "phone": "+96170000001",
    //         "message": "Platform will be down..." }
    // ─────────────────────────────────────────────────
    @PostMapping("/announcement")
    public ResponseEntity<?> sendAnnouncement(
            @RequestBody Map<String, String> body) {

        String phone = body.get("phone");
        String message = body.get("message");

        if (phone == null || phone.isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "Phone is required"));
        }
        if (message == null || message.isBlank()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("message", "Message text is required"));
        }

        communicationService.sendPlatformAnnouncement(phone, message);

        return ResponseEntity.ok(Map.of(
                "message", "Announcement sent to " + phone
        ));
    }

    // ─────────────────────────────────────────────────
    // GET /api/admin/notify/logs
    //
    // Admin views all sent messages for audit.
    // ─────────────────────────────────────────────────
    @GetMapping("/logs")
    public ResponseEntity<List<MessageLog>> getAllLogs() {
        return ResponseEntity.ok(
                messageLogRepository
                        .findAll()
                        // Newest first
                        .stream()
                        .sorted((a, b) -> b.getCreatedAt()
                                .compareTo(a.getCreatedAt()))
                        .toList()
        );
    }

    // ─────────────────────────────────────────────────
    // GET /api/admin/notify/logs/order/{orderId}
    //
    // Admin sees all messages related to a specific order.
    // Useful for support when customer says they didn't
    // receive their tracking link.
    // ─────────────────────────────────────────────────
    @GetMapping("/logs/order/{orderId}")
    public ResponseEntity<List<MessageLog>> getOrderLogs(
            @PathVariable Long orderId) {
        return ResponseEntity.ok(
                messageLogRepository
                        .findByRelatedOrderIdOrderByCreatedAtDesc(
                                orderId)
        );
    }

    // ─────────────────────────────────────────────────
    // GET /api/admin/notify/logs/phone/{phone}
    //
    // Admin sees all messages sent to a phone number.
    // ─────────────────────────────────────────────────
    @GetMapping("/logs/phone/{phone}")
    public ResponseEntity<List<MessageLog>> getPhoneLogs(
            @PathVariable String phone) {
        return ResponseEntity.ok(
                messageLogRepository
                        .findByRecipientPhoneOrderByCreatedAtDesc(
                                phone)
        );
    }

    // ─────────────────────────────────────────────────
    // GET /api/admin/notify/logs/failed
    //
    // Admin sees all failed messages.
    // Can use this to identify delivery issues
    // or retry failed sends manually.
    // ─────────────────────────────────────────────────
    @GetMapping("/logs/failed")
    public ResponseEntity<List<MessageLog>> getFailedLogs() {
        return ResponseEntity.ok(
                messageLogRepository
                        .findByStatusOrderByCreatedAtDesc(
                                MessageLog.DeliveryStatus.FAILED)
        );
    }
}