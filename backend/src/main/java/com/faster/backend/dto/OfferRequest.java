package com.faster.backend.dto;

import com.faster.backend.entity.Offer;
import com.fasterxml.jackson.annotation.JsonFormat;
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

    // ─── Fix: tell Jackson how to parse the date ──────
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                timezone = "UTC")
    private LocalDateTime startDate;

    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                timezone = "UTC")
    private LocalDateTime endDate;

    private Integer usageLimit;

    // ─── Scope: which categories this offer applies to
    // null or empty = whole store
    private List<Long> categoryIds;

    // ─── Scope: which specific items this offer applies to
    // null or empty = not item-specific
    private List<Long> itemIds;
}