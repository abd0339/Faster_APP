package com.faster.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "ledger_entries", indexes = {
    @Index(name = "idx_ledger_user",
           columnList = "user_id"),
    @Index(name = "idx_ledger_order",
           columnList = "order_id"),
    @Index(name = "idx_ledger_type",
           columnList = "type"),
    @Index(name = "idx_ledger_created",
           columnList = "created_at")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties({"hibernateLazyInitializer",
                       "handler"})
public class LedgerEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Who this entry belongs to ────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    @JsonIgnore
    private User user;

    // ─── Which order triggered this entry ────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id")
    @JsonIgnoreProperties({"merchant", "driver",
                            "customer",
                            "hibernateLazyInitializer"})
    private Order order;

    // ─── DEBIT = owes money / CREDIT = money received ─
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EntryType type;

    // ─── What kind of transaction ─────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EntryCategory category;

    // ─── The delivery fee (base for commission calc) ──
    // Stored separately for transparency
    @Column(name = "delivery_fee",
            precision = 10, scale = 2)
    private BigDecimal deliveryFee;

    // ─── Amount of this transaction ───────────────────
    // For DRIVER_COMMISSION: 20% of delivery_fee
    // For MERCHANT_COMMISSION: 10% of monthly sales
    // For SETTLEMENT: full amount driver paid
    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal amount;

    // ─── Running debt balance after this entry ────────
    // For drivers: how much they owe platform
    // Resets to 0.00 after settlement
    @Column(name = "balance_after",
            nullable = false,
            precision = 10, scale = 2)
    private BigDecimal balanceAfter;

    // ─── Human-readable description ───────────────────
    @Column(nullable = false)
    private String description;

    // ─── Payment reference (OMT/WishMoney receipt) ────
    // Admin fills this when driver pays manually
    // Future: auto-filled by WishMoney webhook
    private String paymentReference;

    // ─── Who processed this entry ─────────────────────
    // null = system auto-generated
    // admin ID = manually processed by admin
    @Column(name = "processed_by")
    private Long processedBy;

    // ─── Timestamp ────────────────────────────────────
    @Column(updatable = false, nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }

    // ─── Entry Type ───────────────────────────────────
    public enum EntryType {
        DEBIT,   // Money owed to platform
        CREDIT   // Money paid or earned
    }

    // ─── Entry Category ───────────────────────────────
    public enum EntryCategory {

        // DRIVER entries
        DRIVER_COMMISSION,   // 20% of delivery fee
                             // auto-created on delivery

        DRIVER_SETTLEMENT,   // Driver paid their debt
                             // admin processes manually
                             // future: WishMoney auto

        // MERCHANT entries
        MERCHANT_COMMISSION, // 10% of monthly total
                             // admin invoices monthly

        MERCHANT_SETTLEMENT, // Merchant paid commission

        // Other
        ADJUSTMENT,          // Admin manual correction
        REFUND               // Order cancelled/refunded
    }
}