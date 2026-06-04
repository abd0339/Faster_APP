package com.faster.backend.dto;

import com.faster.backend.entity.Offer;
import jakarta.validation.constraints.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class OfferRequest {

    @NotBlank(message = "Offer title is required")
    @Size(min = 3, max = 100,
          message = "Title must be between 3 and 100 characters")
    private String title;

    private String description;

    @DecimalMin(value = "1.0",
                message = "Discount must be at least 1%")
    @DecimalMax(value = "100.0",
                message = "Discount cannot exceed 100%")
    private BigDecimal discountPercent;

    private Offer.OfferType offerType;

    private LocalDateTime startDate;
    private LocalDateTime endDate;

    // null = unlimited usage
    private Integer usageLimit;
}