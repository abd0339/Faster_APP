package com.faster.backend.dto;

import com.faster.backend.entity.Item;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.util.List;

@Data
public class PublicMenuDTO {

    // ─── Category ─────────────────────────────────────
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class CategoryDTO {
        private Long id;
        private String name;
        private String icon;
        private Integer displayOrder;
        private List<ItemDTO> items;
    }

    // ─── Item ─────────────────────────────────────────
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ItemDTO {
        private Long id;
        private String name;
        private String description;
        private BigDecimal price;
        private String imageUrl;
        private Boolean isAvailable;
        private Boolean isSnoozed;
        private Integer prepTimeMinutes;
        private Integer stockQuantity;
        private Integer displayOrder;
    }
}