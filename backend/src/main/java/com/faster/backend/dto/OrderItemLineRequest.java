package com.faster.backend.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.List;

/**
 * One cart line: an item, its quantity, and any selected
 * modifiers/addons. Part of the C2 fix — the client sends
 * WHAT was ordered, never what it costs. PricingService
 * looks up the real price server-side from this.
 */
@Data
public class OrderItemLineRequest {

    @NotNull(message = "itemId is required for each order line")
    private Long itemId;

    @NotNull(message = "quantity is required for each order line")
    @Min(value = 1, message = "quantity must be at least 1")
    private Integer quantity;

    // Optional — e.g. "Large" size selection
    private List<Long> modifierOptionIds;

    // Optional — e.g. "Extra Cheese"
    private List<Long> addonIds;
}