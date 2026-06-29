package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

// ─────────────────────────────────────────────────────
// MessageLog — Audit record for every SMS/WhatsApp sent
//
// Every outgoing message is stored here.
// Admin can see: who was contacted, what was sent,
// which provider handled it, and whether it succeeded.
//
// This table grows over time — consider archiving
// entries older than 90 days in production.
// ─────────────────────────────────────────────────────
@Entity
@Table(name = "message_logs", indexes = {
    @Index(name = "idx_msglog_recipient",
           columnList = "recipient_phone"),
    @Index(name = "idx_msglog_type",
           columnList = "message_type"),
    @Index(name = "idx_msglog_status",
           columnList = "status"),
    @Index(name = "idx_msglog_created",
           columnList = "created_at")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MessageLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Who received the message ─────────────────────
    @Column(nullable = false, name = "recipient_phone")
    private String recipientPhone;

    // ─── Which type of message was sent ──────────────
    // Matches MessageType enum below
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, name = "message_type")
    private MessageType messageType;

    // ─── Which provider sent it ───────────────────────
    // Matches provider name from .env: twilio / vonage
    @Column(nullable = false)
    private String provider;

    // ─── The full text of the message sent ───────────
    @Column(columnDefinition = "TEXT", nullable = false)
    private String messageBody;

    // ─── Delivery status ─────────────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private DeliveryStatus status = DeliveryStatus.PENDING;

    // ─── Provider's message SID (for tracing) ─────────
    // Twilio calls this "SID", Vonage calls it "message-id"
    // Store either here for support lookups
    @Column(name = "provider_message_id")
    private String providerMessageId;

    // ─── Error details if delivery failed ─────────────
    @Column(columnDefinition = "TEXT",
            name = "error_message")
    private String errorMessage;

    // ─── Which order triggered this message ──────────
    // Nullable — some messages are not order-related
    @Column(name = "related_order_id")
    private Long relatedOrderId;

    // ─── Tracking code for O2O messages ──────────────
    @Column(name = "tracking_code")
    private String trackingCode;

    // ─── Timestamps ──────────────────────────────────
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "delivered_at")
    private LocalDateTime deliveredAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }

    // ─── What kind of message is this ────────────────
    public enum MessageType {
        // O2O: sent to offline customer with tracking link
        O2O_TRACKING_LINK,

        // Sent when a driver is assigned to an O2O order
        O2O_DRIVER_ASSIGNED,

        // Sent when admin manually clicks "Notify Driver"
        // about their outstanding commission debt
        DRIVER_DEBT_NOTIFICATION,

        // Broadcast to all active drivers (announcements)
        PLATFORM_ANNOUNCEMENT,

        // OTP for phone verification (future feature)
        OTP_VERIFICATION
    }

    // ─── Was the message delivered ────────────────────
    public enum DeliveryStatus {
        PENDING,    // Just created, not yet sent
        SENT,       // API accepted — awaiting delivery
        DELIVERED,  // Provider confirmed delivery
        FAILED      // Provider rejected or timed out
    }
}