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
           columnList = "tracking_code"),
    @Index(name = "idx_order_created",
           columnList = "created_at")
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
    // Format: FST-20260606-A3X9
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
                            "isBlocked",
                            "hibernateLazyInitializer"})
    private User driver;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id")
    @JsonIgnore
    private User customer;

    // ─── O2O Bridge (offline customer) ───────────────
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

    // ─── FINANCIALS ───────────────────────────────────

    // Product value only (what driver pays merchant)
    @Column(nullable = false,
            name = "total_price",
            precision = 10, scale = 2)
    private BigDecimal totalPrice;

    // Delivery fee charged to customer
    // This is what the driver earns per trip
    @Builder.Default
    @Column(name = "delivery_fee",
            precision = 10, scale = 2)
    private BigDecimal deliveryFee = BigDecimal.ZERO;

    // Platform commission = 20% of delivery fee ONLY
    // Auto-calculated on order creation
    @Builder.Default
    @Column(name = "commission_amount",
            precision = 10, scale = 2)
    private BigDecimal commissionAmount = BigDecimal.ZERO;

    // Grand total customer pays
    // = totalPrice + deliveryFee
    @Builder.Default
    @Column(name = "grand_total",
            precision = 10, scale = 2)
    private BigDecimal grandTotal = BigDecimal.ZERO;

    // What driver pays merchant at pickup (= totalPrice)
    @Builder.Default
    @Column(name = "driver_pays_merchant",
            precision = 10, scale = 2)
    private BigDecimal driverPaysMerchant = BigDecimal.ZERO;

    // Merchant daily commission = 10% of daily sales
    // Calculated and stored per order for daily totals
    @Builder.Default
    @Column(name = "merchant_commission",
            precision = 10, scale = 2)
    private BigDecimal merchantCommission = BigDecimal.ZERO;

    // ─── Location data ────────────────────────────────
    private Double pickupLat;
    private Double pickupLng;
    private String pickupAddress;

    private Double deliveryLat;
    private Double deliveryLng;
    private String deliveryAddress;

    // ─── Timing ──────────────────────────────────────
    private LocalDateTime acceptedAt;
    private LocalDateTime pickedUpAt;
    private LocalDateTime deliveredAt;

    @Builder.Default
    private Integer estimatedPrepMinutes = 15;

    // ─── Notes & Dispute ─────────────────────────────
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

    // ─── Order Type ───────────────────────────────────
    public enum OrderType {
        LOGISTICS,   // Package delivery
        MOBILITY     // People transport
    }

    // ─── Order Status ─────────────────────────────────
    public enum OrderStatus {
        PENDING,           // Waiting for driver
        ACCEPTED,          // Driver accepted
        PREPARING,         // Merchant preparing
        READY_FOR_PICKUP,  // Ready at merchant
        PICKED_UP,         // Driver has the package
        DELIVERED,         // Completed ✅
        CANCELLED,         // Cancelled ❌
        DISPUTED           // Problem reported ⚠️
    }
}