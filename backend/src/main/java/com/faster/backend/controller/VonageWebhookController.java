package com.faster.backend.controller;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.repository.MessageLogRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * Webhook endpoints Vonage calls — configured as the
 * "Inbound URL" and "Status URL" on the Vonage Application
 * (see dashboard.vonage.com/applications/{id}).
 *
 * These are PUBLIC (no auth) because Vonage's servers call
 * them directly, not a logged-in user — same pattern as
 * /tracking/public/**. They don't expose or accept anything
 * sensitive; they only update delivery status for messages
 * this backend already sent.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
public class VonageWebhookController {

    private final MessageLogRepository messageLogRepository;

    // ─────────────────────────────────────────────────
    // POST /api/webhooks/vonage/status
    // Vonage calls this whenever a message's delivery
    // status changes (delivered, failed, rejected, etc.)
    // FIX: this is what actually lets MessageLog.status
    // reach DELIVERED — previously it only ever went
    // PENDING → SENT → (FAILED on error), and DELIVERED
    // was defined but never reachable.
    // ─────────────────────────────────────────────────
    @PostMapping("/api/webhooks/vonage/status")
    public ResponseEntity<Void> handleStatus(
            @RequestBody Map<String, Object> payload) {

        try {
            String messageUuid = str(payload.get("message_uuid"));
            String status = str(payload.get("status"));

            if (messageUuid == null || status == null) {
                // WhatsApp sandbox / classic SMS DLR payloads use
                // different field names — try the SMS-style ones too.
                messageUuid = str(payload.get("messageId"));
                status = str(payload.get("status"));
            }

            if (messageUuid != null) {
                List<MessageLog> matches = messageLogRepository
                        .findByProviderMessageId(messageUuid);

                for (MessageLog msgLog : matches) {
                    if ("delivered".equalsIgnoreCase(status)) {
                        msgLog.setStatus(MessageLog.DeliveryStatus.DELIVERED);
                        msgLog.setDeliveredAt(LocalDateTime.now());
                    } else if ("failed".equalsIgnoreCase(status)
                            || "rejected".equalsIgnoreCase(status)
                            || "expired".equalsIgnoreCase(status)) {
                        msgLog.setStatus(MessageLog.DeliveryStatus.FAILED);
                        msgLog.setErrorMessage("Vonage status: " + status);
                    }
                    messageLogRepository.save(msgLog);
                }
            }

            log.info("📬 Vonage status webhook: uuid={} status={}",
                    messageUuid, status);

        } catch (Exception e) {
            // Never let a malformed webhook payload throw a 500 —
            // Vonage will retry aggressively if it sees errors.
            log.warn("Vonage status webhook parse issue: {}", e.getMessage());
        }

        return ResponseEntity.ok().build();
    }

    // ─────────────────────────────────────────────────
    // POST /api/webhooks/vonage/inbound
    // Vonage calls this if a customer replies to a WhatsApp
    // message (e.g. types something back). Not used for any
    // business logic today — just logged for visibility.
    // Required field on the Vonage Application regardless of
    // whether inbound replies matter yet.
    // ─────────────────────────────────────────────────
    @PostMapping("/api/webhooks/vonage/inbound")
    public ResponseEntity<Void> handleInbound(
            @RequestBody Map<String, Object> payload) {

        log.info("📩 Vonage inbound message received: {}", payload);
        return ResponseEntity.ok().build();
    }

    private String str(Object value) {
        return value != null ? value.toString() : null;
    }
}