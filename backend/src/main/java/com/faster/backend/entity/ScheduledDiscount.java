package com.faster.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalTime;

@Entity
@Table(name = "scheduled_discounts")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ScheduledDiscount {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which item gets discounted ──────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "item_id", nullable = false)
    private Item item;

    // ─── Discount label (e.g. "Happy Hour 🎉") ──────
    @Column(nullable = false)
    private String label;

    // ─── Discount percentage (e.g. 50 = 50% off) ────
    @Column(nullable = false, precision = 5, scale = 2)
    private BigDecimal discountPercent;

    // ─── Time window (e.g. 16:00 to 18:00) ──────────
    @Column(nullable = false)
    private LocalTime startTime;

    @Column(nullable = false)
    private LocalTime endTime;

    // ─── Which days does this discount apply? ────────
    // Stored as comma-separated: "MON,TUE,WED,THU,FRI"
    // or "SAT,SUN" for weekends
    @Column(nullable = false)
    private String daysOfWeek;

    // ─── Is this discount currently active? ─────────
    @Builder.Default
    private Boolean isActive = true;
}