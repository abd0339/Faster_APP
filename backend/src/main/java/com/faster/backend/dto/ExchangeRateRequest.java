package com.faster.backend.dto;

import java.math.BigDecimal;

import lombok.Data;

@Data
public class ExchangeRateRequest {

    private BigDecimal rate;

    // SANITY GUARD (final review fix wave) — see
    // ExchangeRateService.updateRate. Defaults to false/absent: an
    // admin who hasn't seen the confirmation dialog never silently
    // bypasses the guard just by omitting this field.
    private boolean confirm;
}
