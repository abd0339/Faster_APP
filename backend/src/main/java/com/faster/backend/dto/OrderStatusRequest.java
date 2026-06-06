package com.faster.backend.dto;

import com.faster.backend.entity.Order;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

@Data
public class OrderStatusRequest {

    @NotNull(message = "Status is required")
    private Order.OrderStatus status;

    // Required only when status = DISPUTED
    private String disputeReason;
}