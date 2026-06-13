package com.faster.backend.dto;

import com.faster.backend.entity.Offer;
import jakarta.validation.constraints.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Data
public class OfferRequest {

    @NotBlank(message = "Offer title is required")
    @Size(min = 3, max = 100,
          message = "Title must be between 3 and 100 characters")
    private String title;

    private String description;

    private BigDecimal discountPercent;

    private Offer.OfferType offerType;

    // No @JsonFormat — handled globally by JavaTimeModule
    private LocalDateTime startDate;
    private LocalDateTime endDate;

    private Integer usageLimit;

    private List<Long> categoryIds;
    private List<Long> itemIds;
}