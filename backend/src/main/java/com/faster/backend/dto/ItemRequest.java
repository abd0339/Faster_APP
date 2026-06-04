package com.faster.backend.dto;

import jakarta.validation.constraints.*;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class ItemRequest {

    @NotBlank(message = "Item name is required")
    @Size(min = 2, max = 100,
          message = "Name must be between 2 and 100 characters")
    private String name;

    private String description;

    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01",
                message = "Price must be greater than 0")
    private BigDecimal price;

    @NotNull(message = "Category ID is required")
    private Long categoryId;

    // -1 = unlimited stock
    private Integer stockQuantity;

    // Minutes to prepare (default 15)
    private Integer prepTimeMinutes;

    // Tax rate as decimal e.g. 0.11 = 11%
    private BigDecimal taxRate;

    // Fixed service fee
    private BigDecimal serviceFee;

    private Integer displayOrder;
}