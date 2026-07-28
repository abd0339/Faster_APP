package com.faster.backend.entity;

import java.time.LocalDateTime;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One row per device a user is logged into. A user can have
 * multiple devices (phone + web, or two phones) — each gets
 * its own FCM token, so pushes go to every device they're
 * logged in on.
 *
 * Phase 4 (FCM) — purely additive: push notifications are
 * sent ALONGSIDE the existing WebSocket broadcasts and Twilio
 * messages at each order lifecycle event, never replacing
 * them. If a push fails (invalid/expired token, no internet
 * on the device, etc.) it's logged and swallowed — it can
 * never block an order from updating.
 */
@Entity
@Table(name = "device_tokens", indexes = {
        @Index(name = "idx_device_token_user", columnList = "user_id"),
}, uniqueConstraints = {
        // The same physical token should only ever map to one
        // row — if a device re-registers (app reinstall, token
        // refresh), we upsert rather than accumulate duplicates.
        @UniqueConstraint(name = "uk_device_token", columnNames = "fcm_token")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DeviceToken {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "fcm_token", nullable = false, length = 512)
    private String fcmToken;

    // ANDROID / IOS / WEB — informational, doesn't change
    // send behavior (FCM handles platform differences itself)
    @Column(nullable = false)
    private String platform;

    @Column(updatable = false)
    private LocalDateTime createdAt;

    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }
}