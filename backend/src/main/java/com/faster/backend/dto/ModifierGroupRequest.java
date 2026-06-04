package com.faster.backend.dto;

import jakarta.validation.constraints.*;
import lombok.Data;
import java.math.BigDecimal;
import java.util.List;

@Data
public class ModifierGroupRequest {

    @NotBlank(message = "Group name is required")
    private String name;

    private Boolean isRequired;

    @Min(value = 0)
    private Integer minSelections;

    @Min(value = 1)
    private Integer maxSelections;

    // Options to create with this group
    private List<OptionItem> options;

    @Data
    public static class OptionItem {

        @NotBlank(message = "Option name is required")
        private String name;

        private BigDecimal extraPrice;
    }
}