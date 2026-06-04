package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.util.List;

@Entity
@Table(name = "item_modifier_groups")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ItemModifierGroup {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which item this group belongs to ───────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "item_id", nullable = false)
    private Item item;

    // ─── Group name (e.g. "Choose your size") ───────
    @Column(nullable = false)
    private String name;

    // ─── Does the customer MUST pick one? ───────────
    @Builder.Default
    private Boolean isRequired = false;

    // ─── How many options can they pick? ────────────
    // e.g. min=1, max=1 = pick exactly one
    // e.g. min=0, max=3 = pick up to 3
    @Builder.Default
    private Integer minSelections = 0;

    @Builder.Default
    private Integer maxSelections = 1;

    // ─── The options inside this group ──────────────
    @OneToMany(mappedBy = "modifierGroup",
               cascade = CascadeType.ALL,
               fetch = FetchType.LAZY)
    private List<ModifierOption> options;
}