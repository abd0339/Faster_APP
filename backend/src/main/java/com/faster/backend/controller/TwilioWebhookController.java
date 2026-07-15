package com.faster.backend.controller;

import com.faster.backend.entity.MessageLog;
import com.faster.backend.repository.MessageLogRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Webhook Twilio calls when a message's delivery status
 * changes — configured as the Status Callback URL.
 * (Set this in Twilio Console → Messaging → Services →
 * faster-app → Integration → Status Callback URL, or per
 * message if you prefer not to configure it globally.)
 *
 * Twilio posts these as application/x-www-form-urlencoded,
 * NOT JSON (this is the key difference from the old Vonage
 * webhook) — hence @RequestParam instead of @RequestBody.
 *
 * PUBLIC (no auth) — Twilio's servers call this directly,
 * same pattern as /tracking/public/**. Only ever updates
 * delivery status for messages this backend already sent.
 */
@Slf4j
@RestController
@RequiredArgsConstructor
public class TwilioWebhookController {

    private final MessageLogRepository messageLogRepository;

    // ─────────────────────────────────────────────────
    // POST /api/webhooks/twilio/status
    // Twilio's standard fields: MessageSid, MessageStatus,
    // ErrorCode (only present on failure)
    // ─────────────────────────────────────────────────
    @PostMapping("/api/webhooks/twilio/status")
    public ResponseEntity<Void> handleStatus(
            @RequestParam(value = "MessageSid", required = false) String messageSid,
            @RequestParam(value = "MessageStatus", required = false) String status,
            @RequestParam(value = "ErrorCode", required = false) String errorCode) {

        try {
            if (messageSid != null) {
                List<MessageLog> matches = messageLogRepository
                        .findByProviderMessageId(messageSid);

                for (MessageLog msgLog : matches) {
                    if ("delivered".equalsIgnoreCase(status)) {
                        msgLog.setStatus(MessageLog.DeliveryStatus.DELIVERED);
                        msgLog.setDeliveredAt(LocalDateTime.now());
                    } else if ("failed".equalsIgnoreCase(status)
                            || "undelivered".equalsIgnoreCase(status)) {
                        msgLog.setStatus(MessageLog.DeliveryStatus.FAILED);
                        msgLog.setErrorMessage(
                                "Twilio status: " + status
                                + (errorCode != null ? " (error " + errorCode + ")" : ""));
                    }
                    messageLogRepository.save(msgLog);
                }
            }

            log.info("📬 Twilio status webhook: sid={} status={} errorCode={}",
                    messageSid, status, errorCode);

        } catch (Exception e) {
            // Never let a malformed webhook throw a 500 —
            // Twilio retries aggressively on errors.
            log.warn("Twilio status webhook parse issue: {}", e.getMessage());
        }

        return ResponseEntity.ok().build();
    }
}