package com.faster.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.Fetch;
import org.hibernate.annotations.FetchMode;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

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

    // ─── Which merchant ──────────────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    @JsonIgnore
    private User merchant;

    // ─── Offer details ───────────────────────────────
    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "TEXT")
    private String description;

    private String imageUrl;

    @Column(precision = 5, scale = 2)
    private BigDecimal discountPercent;

    @Enumerated(EnumType.STRING)
    @Builder.Default
    private OfferType offerType = OfferType.PERCENTAGE;

    // ─── Scope: applies to which categories ──────────
    // Empty list = applies to ALL items in the store
    @ManyToMany(fetch = FetchType.EAGER)
    @Fetch(FetchMode.SUBSELECT)
    @JoinTable(
        name = "offer_categories",
        joinColumns = @JoinColumn(name = "offer_id"),
        inverseJoinColumns = @JoinColumn(name = "category_id")
    )
    @JsonIgnoreProperties({"items", "merchant",
        "hibernateLazyInitializer", "handler"})
    @Builder.Default
    private List<Category> appliedToCategories = new ArrayList<>();

    // ─── Scope: applies to which specific items ───────
    // Empty list = not item-specific
    // FIX: EAGER alone still issued one SELECT per offer per
    // collection (2N+1 for a list of N offers) -- SUBSELECT makes
    // Hibernate fetch every offer's rows for this collection in one
    // extra query (keyed off the same WHERE the owning query used),
    // so loading N offers is always 3 queries total, not 2N+1.
    @ManyToMany(fetch = FetchType.EAGER)
    @Fetch(FetchMode.SUBSELECT)
    @JoinTable(
        name = "offer_items",
        joinColumns = @JoinColumn(name = "offer_id"),
        inverseJoinColumns = @JoinColumn(name = "item_id")
    )
    @JsonIgnoreProperties({"category", "merchant",
        "hibernateLazyInitializer", "handler"})
    @Builder.Default
    private List<Item> appliedToItems = new ArrayList<>();

    // ─── Validity window ─────────────────────────────
    private LocalDateTime startDate;
    private LocalDateTime endDate;

    @Builder.Default
    private Boolean isActive = true;

    @Builder.Default
    private Integer usageCount = 0;

    private Integer usageLimit;

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

    public enum OfferType {
        PERCENTAGE,
        FIXED_AMOUNT,
        BUY_X_GET_Y,
        FREE_DELIVERY
    }
}