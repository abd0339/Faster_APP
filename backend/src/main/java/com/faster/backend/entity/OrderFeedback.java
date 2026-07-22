package com.faster.backend.entity;

import java.time.LocalDateTime;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One feedback record per delivered order. Created once,
 * right after the customer confirms delivery — see
 * FeedbackController.
 *
 * Two independent things captured here, matching how Uber/
 * other delivery platforms do it:
 *   1. Driver thumbs up/down — negative REQUIRES a note,
 *      which surfaces in the admin dashboard for resolution.
 *   2. Star ratings (1-5) — for BOTH the driver and the
 *      merchant, each optional/skippable independently.
 *
 * The customer can also skip the whole thing — in that case
 * no OrderFeedback row is created at all (nothing to store).
 */
@Entity
@Table(name = "order_feedback", indexes = {
        @Index(name = "idx_feedback_driver", columnList = "driver_id"),
        @Index(name = "idx_feedback_merchant", columnList = "merchant_id"),
        @Index(name = "idx_feedback_resolved", columnList = "resolved")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderFeedback {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "order_id", nullable = false, unique = true)
    private Long orderId;

    @Column(name = "customer_id", nullable = false)
    private Long customerId;

    // Denormalized (copied from the order at submission time)
    // so admin/driver queries never need to join through Order.
    @Column(name = "driver_id")
    private Long driverId;

    @Column(name = "merchant_id")
    private Long merchantId;

    // ─── Driver thumbs up/down ─────────────────────────
    // null = customer skipped this part entirely
    @Column(name = "driver_thumbs_up")
    private Boolean driverThumbsUp;

    // Required when driverThumbsUp == false. Goes straight
    // to the admin dashboard for immediate resolution.
    @Column(name = "negative_note", columnDefinition = "TEXT")
    private String negativeNote;

    // ─── Star ratings (1-5), each independently optional ─
    @Column(name = "driver_stars")
    private Integer driverStars;

    @Column(name = "merchant_stars")
    private Integer merchantStars;

    // ─── Admin resolution (only meaningful when
    // driverThumbsUp == false) ─────────────────────────
    @Builder.Default
    @Column(nullable = false)
    private Boolean resolved = false;

    private LocalDateTime resolvedAt;

    @Column(name = "resolved_by_admin_id")
    private Long resolvedByAdminId;

    @Column(updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}