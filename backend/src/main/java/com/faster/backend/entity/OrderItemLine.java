package com.faster.backend.entity;

import java.time.LocalDateTime;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One catalog item + quantity line from a LOGISTICS store order
 * (createOrder), recorded at the same time stock is decremented.
 *
 * Exists purely so a later cancellation/dispute-resolution can
 * restore exactly the stock this order took — without it, there was
 * no record anywhere of which items/quantities a given order actually
 * contained, so a cancelled order's decremented stock could never be
 * given back (PricingService.restoreStockForOrder reads these rows).
 * O2O/Direct-Delivery/MOBILITY orders have no catalog items at all, so
 * they never write rows here.
 */
@Entity
@Table(name = "order_item_lines", indexes = {
        @Index(name = "idx_order_item_line_order", columnList = "order_id"),
})
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderItemLine {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "order_id", nullable = false)
    private Long orderId;

    @Column(name = "item_id", nullable = false)
    private Long itemId;

    @Column(nullable = false)
    private Integer quantity;

    @Column(updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
    }
}
