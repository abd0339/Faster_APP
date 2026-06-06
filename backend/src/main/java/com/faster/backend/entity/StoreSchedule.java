package com.faster.backend.entity;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalTime;

@Entity
@Table(name = "store_schedules", indexes = {
    @Index(name = "idx_schedule_merchant", columnList = "merchant_id")
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class StoreSchedule {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // ─── Which merchant ──────────────────────────────
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "merchant_id", nullable = false)
    @JsonIgnore
    private User merchant;

    // ─── Day of week ─────────────────────────────────
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private DayOfWeek dayOfWeek;

    // ─── Opening and closing times ───────────────────
    private LocalTime openTime;
    private LocalTime closeTime;

    // ─── Is the store closed on this day entirely? ───
    @Builder.Default
    private Boolean isClosed = false;

    // ─── Days enum ───────────────────────────────────
    public enum DayOfWeek {
        MONDAY,
        TUESDAY,
        WEDNESDAY,
        THURSDAY,
        FRIDAY,
        SATURDAY,
        SUNDAY
    }
}