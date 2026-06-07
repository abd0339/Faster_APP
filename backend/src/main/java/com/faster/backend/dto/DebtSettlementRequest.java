package com.faster.backend.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class DebtSettlementRequest {

    @NotNull(message = "Amount is required")
    @DecimalMin(value = "0.01",
                message = "Amount must be greater than 0")
    private BigDecimal amount;

    // OMT or WishMoney transaction reference number
    @NotBlank(message = "Payment reference is required")
    private String paymentReference;

    // Optional note from admin
    private String adminNote;
}