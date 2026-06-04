package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;

@Entity
@Table(name = "modifier_options")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ModifierOption {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which group this option belongs to ─────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "group_id", nullable = false)
    private ItemModifierGroup modifierGroup;

    // ─── Option name (e.g. "Large", "Extra Cheese") ─
    @Column(nullable = false)
    private String name;

    // ─── Extra cost for this option (can be 0.00) ───
    @Builder.Default
    @Column(name = "extra_price", precision = 10, scale = 2)
    private BigDecimal extraPrice = BigDecimal.ZERO;

    // ─── Can customers still select this option? ────
    @Builder.Default
    private Boolean isAvailable = true;
}