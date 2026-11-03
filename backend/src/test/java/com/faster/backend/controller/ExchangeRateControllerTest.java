package com.faster.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;

import com.faster.backend.dto.ExchangeRateRequest;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.ExchangeRateService;

@ExtendWith(MockitoExtension.class)
class ExchangeRateControllerTest {

    @Mock
    private ExchangeRateService exchangeRateService;

    @Mock
    private AuthenticatedUserResolver authResolver;

    @Mock
    private Authentication auth;

    private ExchangeRateController controller;

    @BeforeEach
    void setUp() {
        controller = new ExchangeRateController(exchangeRateService, authResolver);
    }

    @Test
    void getRate_returnsCurrentRate() {
        when(exchangeRateService.getCurrentRate())
                .thenReturn(new BigDecimal("89500.00"));

        ResponseEntity<?> response = controller.getRate();

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody())
                .isEqualTo(Map.of("usdToLbpRate", new BigDecimal("89500.00")));
    }

    @Test
    void updateRate_callsServiceWithResolvedAdminId() {
        when(authResolver.resolveId(auth)).thenReturn(7L);
        when(exchangeRateService.updateRate(new BigDecimal("90000.00"), 7L, false))
                .thenReturn(new BigDecimal("90000.00"));

        ExchangeRateRequest req = new ExchangeRateRequest();
        req.setRate(new BigDecimal("90000.00"));

        ResponseEntity<?> response = controller.updateRate(req, auth);

        verify(exchangeRateService)
                .updateRate(new BigDecimal("90000.00"), 7L, false);
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody())
                .isEqualTo(Map.of("usdToLbpRate", new BigDecimal("90000.00")));
    }

    // Final whole-branch review, finding #3 — the controller must pass
    // the admin's explicit confirm flag through to the service, not
    // silently default/drop it.
    @Test
    void updateRate_passesConfirmFlagThroughToService() {
        when(authResolver.resolveId(auth)).thenReturn(7L);
        when(exchangeRateService.updateRate(new BigDecimal("89.50"), 7L, true))
                .thenReturn(new BigDecimal("89.50"));

        ExchangeRateRequest req = new ExchangeRateRequest();
        req.setRate(new BigDecimal("89.50"));
        req.setConfirm(true);

        ResponseEntity<?> response = controller.updateRate(req, auth);

        verify(exchangeRateService)
                .updateRate(new BigDecimal("89.50"), 7L, true);
        assertThat(response.getStatusCode().value()).isEqualTo(200);
    }

    @Test
    void updateRate_defaultsConfirmToFalseWhenOmitted() {
        when(authResolver.resolveId(auth)).thenReturn(7L);
        when(exchangeRateService.updateRate(new BigDecimal("90000.00"), 7L, false))
                .thenReturn(new BigDecimal("90000.00"));

        // confirm never set — must default to false, not be left null/
        // skipped.
        ExchangeRateRequest req = new ExchangeRateRequest();
        req.setRate(new BigDecimal("90000.00"));

        controller.updateRate(req, auth);

        verify(exchangeRateService)
                .updateRate(new BigDecimal("90000.00"), 7L, false);
    }
}
