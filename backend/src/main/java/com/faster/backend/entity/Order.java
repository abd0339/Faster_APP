package com.faster.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "orders", indexes = {
    @Index(name = "idx_order_merchant",
           columnList = "merchant_id"),
    @Index(name = "idx_order_driver",
           columnList = "driver_id"),
    @Index(name = "idx_order_status",
           columnList = "status"),
    @Index(name = "idx_order_tracking",
           columnList = "tracking_code")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties({"hibernateLazyInitializer",
                       "handler"})
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Unique tracking code for O2O link ───────────
    // e.g. "FST-20260606-A3X9"
    @Column(nullable = false, unique = true)
    private String trackingCode;

    // ─── Three sides of the order ────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    @JsonIgnore
    private User merchant;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "driver_id")
    @JsonIgnoreProperties({"password", "debtAmount",
                            "isBlocked", "hibernateLazyInitializer"})
    private User driver;

    // ─── Customer info (app user or offline) ─────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id")
    @JsonIgnore
    private User customer;

    // ─── Offline customer (O2O bridge) ───────────────
    // Used when merchant creates order for phone customer
    private String offlineCustomerPhone;
    private String offlineCustomerLandmark;

    // ─── Order type ───────────────────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private OrderType orderType = OrderType.LOGISTICS;

    // ─── Order status lifecycle ───────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private OrderStatus status = OrderStatus.PENDING;

    // ─── Financials ───────────────────────────────────
    // Total price customer pays
    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal totalPrice;

    // Platform commission (20% of total)
    @Column(precision = 10, scale = 2)
    private BigDecimal commissionAmount;

    // Amount driver pays merchant at pickup
    @Column(precision = 10, scale = 2)
    private BigDecimal driverPaysMerchant;

    // ─── Location data ────────────────────────────────
    // Pickup location (merchant address)
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    // Delivery location (customer address)
    private Double deliveryLat;
    private Double deliveryLng;
    private String deliveryAddress;

    // ─── Timing ──────────────────────────────────────
    private LocalDateTime acceptedAt;
    private LocalDateTime pickedUpAt;
    private LocalDateTime deliveredAt;

    // Estimated prep time in minutes
    @Builder.Default
    private Integer estimatedPrepMinutes = 15;

    // ─── Notes ───────────────────────────────────────
    @Column(columnDefinition = "TEXT")
    private String customerNotes;

    @Column(columnDefinition = "TEXT")
    private String disputeReason;

    // ─── Timestamps ──────────────────────────────────
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

    // ─── Order Type Enum ─────────────────────────────
    public enum OrderType {
        LOGISTICS,   // Package delivery
        MOBILITY     // People transport
    }

    // ─── Order Status Enum ───────────────────────────
    public enum OrderStatus {
        PENDING,           // Waiting for driver
        ACCEPTED,          // Driver accepted
        PREPARING,         // Merchant preparing
        READY_FOR_PICKUP,  // Ready at merchant
        PICKED_UP,         // Driver has it
        DELIVERED,         // Done ✅
        CANCELLED,         // Cancelled
        DISPUTED           // Problem reported
    }
}