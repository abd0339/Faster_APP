package com.faster.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "offers", indexes = {
    @Index(name = "idx_offer_merchant", columnList = "merchant_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Offer {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which merchant created this offer ──────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    @JsonIgnore
    private User merchant;

    // ─── Offer details ───────────────────────────────
    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    // ─── Optional banner image ───────────────────────
    private String imageUrl;

    // ─── Discount percentage (e.g. 20 = 20% off) ────
    @Column(precision = 5, scale = 2)
    private BigDecimal discountPercent;

    // ─── Offer type ──────────────────────────────────
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private OfferType offerType = OfferType.PERCENTAGE;

    // ─── Validity window ─────────────────────────────
    private LocalDateTime startDate;
    private LocalDateTime endDate;

    // ─── Is this offer currently live? ──────────────
    @Builder.Default
    private Boolean isActive = true;

    // ─── How many times was this offer used? ────────
    @Builder.Default
    private Integer usageCount = 0;

    // ─── Optional usage limit (null = unlimited) ────
    private Integer usageLimit;

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

    // ─── Offer Type Enum ─────────────────────────────
    public enum OfferType {
        PERCENTAGE,      // e.g. 20% off
        FIXED_AMOUNT,    // e.g. $2 off
        BUY_X_GET_Y,     // e.g. Buy 2 Get 1 Free
        FREE_DELIVERY    // Free delivery on this offer
    }
}
