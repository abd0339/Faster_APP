package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;

@Entity
@Table(name = "item_addons")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ItemAddon {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which item this addon belongs to ───────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "item_id", nullable = false)
    private Item item;

    // ─── Addon name (e.g. "Extra Sauce", "Bag") ─────
    @Column(nullable = false)
    private String name;

    // ─── Extra cost (e.g. 0.50) ─────────────────────
    @Builder.Default
    @Column(name = "extra_price", precision = 10, scale = 2)
    private BigDecimal extraPrice = BigDecimal.ZERO;

    // ─── Is this addon currently available? ─────────
    @Builder.Default
    private Boolean isAvailable = true;
}