package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.List;

@Entity
@Table(name = "categories", indexes = {
    @Index(name = "idx_category_merchant", columnList = "merchant_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Category {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which merchant owns this category ──────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    private User merchant;

    // ─── Category name (e.g. "Burgers", "Drinks") ───
    @Column(nullable = false)
    private String name;

    // ─── Emoji or icon URL for the category ─────────
    private String icon;

    // ─── Order to display in the menu ───────────────
    @Builder.Default
    @Column(name = "display_order")
    private Integer displayOrder = 0;

    // ─── Is this category currently visible? ────────
    @Builder.Default
    private Boolean isActive = true;

    // ─── Items inside this category ─────────────────
    @OneToMany(mappedBy = "category",
               cascade = CascadeType.ALL,
               fetch = FetchType.LAZY)
    private List<Item> items;

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