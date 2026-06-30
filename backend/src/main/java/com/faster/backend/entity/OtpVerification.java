package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

// ─────────────────────────────────────────────────────
// OtpVerification — Stores OTP codes for phone verification
//
// One OTP per user at a time.
// - Expires 10 minutes after creation
// - Max 3 attempts before invalidated
// - Deleted after successful verification
//
// Security rules:
//   - Code is 6 digits (100000–999999)
//   - Stored as plain text (short-lived, low risk)
//   - Invalidated after 3 wrong attempts
//   - New OTP request invalidates any existing one
// ─────────────────────────────────────────────────────
@Entity
@Table(name = "otp_verifications", indexes = {
    @Index(name = "idx_otp_phone", columnList = "phone"),
    @Index(name = "idx_otp_user",  columnList = "user_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OtpVerification {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which user this OTP belongs to ──────────────
    @Column(name = "user_id", nullable = false)
    private Long userId;

    // ─── Phone that received the OTP ─────────────────
    @Column(nullable = false)
    private String phone;

    // ─── The 6-digit OTP code ─────────────────────────
    @Column(nullable = false, length = 6)
    private String code;

    // ─── Expiry: 10 minutes from creation ─────────────
    @Column(nullable = false, name = "expires_at")
    private LocalDateTime expiresAt;

    // ─── Track wrong attempts ─────────────────────────
    // After 3 wrong attempts the OTP is invalidated.
    // User must request a new one.
    @Builder.Default
    @Column(nullable = false, name = "attempts")
    private Integer attempts = 0;

    // ─── Was this OTP already used? ───────────────────
    // Set to true after successful verification.
    // Prevents replay attacks.
    @Builder.Default
    @Column(nullable = false, name = "is_used")
    private Boolean isUsed = false;

    // ─── When was it created ──────────────────────────
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }

    // ─── Helper: is this OTP still valid? ─────────────
    public boolean isValid() {
        return !Boolean.TRUE.equals(isUsed)
            && attempts < 3
            && LocalDateTime.now().isBefore(expiresAt);
    }
}