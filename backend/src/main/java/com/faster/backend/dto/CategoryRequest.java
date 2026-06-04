package com.faster.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class CategoryRequest {

    @NotBlank(message = "Category name is required")
    @Size(min = 2, max = 50,
          message = "Name must be between 2 and 50 characters")
    private String name;

    // Emoji or icon URL (optional)
    private String icon;

    // Display order in menu (optional, default 0)
    private Integer displayOrder;
}