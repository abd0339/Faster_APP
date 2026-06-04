package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Entity
@Table(name = "items", indexes = {
    @Index(name = "idx_item_merchant",  columnList = "merchant_id"),
    @Index(name = "idx_item_category",  columnList = "category_id"),
    @Index(name = "idx_item_name",      columnList = "name")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Item {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Owner ───────────────────────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    private User merchant;

    // ─── Category ────────────────────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id", nullable = false)
    private Category category;

    // ─── Basic Info ──────────────────────────────────
    @Column(nullable = false)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal price;

    // ─── Image ───────────────────────────────────────
    private String imageUrl;

    // ─── Stock Management ────────────────────────────
    // -1 means unlimited stock
    @Builder.Default
    private Integer stockQuantity = -1;

    // Master on/off switch for the item
    @Builder.Default
    private Boolean isAvailable = true;

    // Temporary snooze (e.g. out of avocados for 2hrs)
    @Builder.Default
    private Boolean isSnoozed = false;

    // When the snooze expires (null = not snoozed)
    private LocalDateTime snoozeUntil;

    // ─── Logistics ───────────────────────────────────
    // How long to prepare this item (in minutes)
    @Builder.Default
    @Column(name = "prep_time_minutes")
    private Integer prepTimeMinutes = 15;

    // ─── Pricing ─────────────────────────────────────
    // Tax rate as a decimal (e.g. 0.11 = 11% VAT)
    @Builder.Default
    @Column(name = "tax_rate", precision = 5, scale = 4)
    private BigDecimal taxRate = BigDecimal.ZERO;

    // Fixed service fee on top of price
    @Builder.Default
    @Column(name = "service_fee", precision = 10, scale = 2)
    private BigDecimal serviceFee = BigDecimal.ZERO;

    // ─── Display ─────────────────────────────────────
    @Builder.Default
    @Column(name = "display_order")
    private Integer displayOrder = 0;

    // ─── Relations ───────────────────────────────────
    @OneToMany(mappedBy = "item",
               cascade = CascadeType.ALL,
               fetch = FetchType.LAZY)
    private List<ItemModifierGroup> modifierGroups;

    @OneToMany(mappedBy = "item",
               cascade = CascadeType.ALL,
               fetch = FetchType.LAZY)
    private List<ItemAddon> addons;

    @OneToMany(mappedBy = "item",
               cascade = CascadeType.ALL,
               fetch = FetchType.LAZY)
    private List<ScheduledDiscount> scheduledDiscounts;

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
}