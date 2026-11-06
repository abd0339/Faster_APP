package com.faster.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.faster.backend.entity.ExchangeRate;
import com.faster.backend.exception.GlobalExceptionHandler;
import com.faster.backend.repository.ExchangeRateRepository;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.ExchangeRateService;
import com.faster.backend.service.PricingService;

/**
 * Hostile JSON PUT through REAL Jackson deserialization, the REAL
 * {@link ExchangeRateService} (only its repository + messaging
 * dependencies are mocked — see class comment on why this differs from
 * OrderControllerAdversarialTest), and the REAL
 * {@link GlobalExceptionHandler}. Confirms every hostile shape sent to
 * the exchange-rate endpoint produces a clean 4xx with a message, never
 * a 500.
 *
 * NOT covered here (and can't be, at this test layer): "non-ADMIN
 * attempting the PUT". ExchangeRateController's own class comment says
 * the admin-only gate is enforced by SecurityConfig's
 * {@code /api/admin/** -> hasRole("ADMIN")} matcher, not inside the
 * controller — a standalone MockMvc setup (no Spring context) never
 * loads the security filter chain, so that specific scenario has no
 * automated coverage at any layer in this codebase. A real-context
 * (e.g. @SpringBootTest) test would be needed to cover it.
 */
@ExtendWith(MockitoExtension.class)
class ExchangeRateControllerAdversarialTest {

    @Mock
    private ExchangeRateRepository exchangeRateRepository;

    @Mock
    private SimpMessagingTemplate messagingTemplate;

    @Mock
    private AuthenticatedUserResolver authResolver;

    @Mock
    private PricingService pricingService;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        // pricingService is an unstubbed mock — rejectIfScaleIsDangerous
        // is a void method that no-ops by default, which matches every
        // rate in this file's adversarial inputs (none carry a
        // dangerous SCALE, only extreme magnitude).
        ExchangeRateService realService =
                new ExchangeRateService(
                        exchangeRateRepository, messagingTemplate, pricingService);
        // @Value is never processed outside a Spring context — same
        // convention as every other direct-constructed @Value-bearing
        // service test in this codebase (see PricingServiceTest and
        // friends). Final-review fix wave, finding #3.
        ReflectionTestUtils.setField(
                realService, "sanityChangeRatio", new BigDecimal("0.50"));
        ExchangeRateController controller =
                new ExchangeRateController(realService, authResolver);

        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        lenient().when(authResolver.resolveId(any(Authentication.class)))
                .thenReturn(7L);
        lenient().when(exchangeRateRepository.findById(1L))
                .thenReturn(Optional.of(ExchangeRate.builder()
                        .id(1L)
                        .usdToLbpRate(new BigDecimal("89500.00"))
                        .updatedAt(LocalDateTime.now())
                        .build()));
        lenient().when(exchangeRateRepository.save(any(ExchangeRate.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    private Authentication adminAuth() {
        return new UsernamePasswordAuthenticationToken("admin@test.com", null);
    }

    @Test
    void getRate_returnsOk() throws Exception {
        mockMvc.perform(get("/api/exchange-rate"))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isEqualTo(200));
    }

    @Test
    void updateRate_rejectsNegativeRate_cleanly() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rate\": -50}")
                        .principal(adminAuth()))
                .andExpect(result -> {
                    int status = result.getResponse().getStatus();
                    assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
                });
    }

    @Test
    void updateRate_rejectsZeroRate_cleanly() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rate\": 0}")
                        .principal(adminAuth()))
                .andExpect(result -> {
                    int status = result.getResponse().getStatus();
                    assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
                });
    }

    @Test
    void updateRate_rejectsMissingRateField_cleanly() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}")
                        .principal(adminAuth()))
                .andExpect(result -> {
                    int status = result.getResponse().getStatus();
                    assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
                });
    }

    @Test
    void updateRate_rejectsCompletelyMissingBody_withoutServerError() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .principal(adminAuth()))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void updateRate_rejectsNonNumericRate_withoutServerError() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rate\": \"not-a-number\"}")
                        .principal(adminAuth()))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void updateRate_rejectsMalformedJson_withoutServerError() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not json")
                        .principal(adminAuth()))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void updateRate_rejectsAbsurdlyLargeRate_cleanly() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rate\": 99999999999999999999999999999999}")
                        .principal(adminAuth()))
                .andExpect(result -> {
                    int status = result.getResponse().getStatus();
                    assertThat(status).isGreaterThanOrEqualTo(400).isLessThan(500);
                });
    }

    @Test
    void updateRate_acceptsValidRate() throws Exception {
        mockMvc.perform(put("/api/admin/exchange-rate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rate\": 90000.50}")
                        .principal(adminAuth()))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isEqualTo(200));
    }
}
