package com.faster.backend.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;

import com.faster.backend.entity.Order;
import com.faster.backend.entity.User;
import com.faster.backend.exception.GlobalExceptionHandler;
import com.faster.backend.repository.OrderRepository;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.OrderService;

/**
 * Hostile JSON POSTed through REAL Jackson deserialization and REAL
 * {@code @Valid} validation against {@link OrderController}, standalone
 * (no Spring context, no DB — just the controller with its
 * service/repo/resolver dependencies mocked via Mockito).
 *
 * The goal throughout: malicious or malformed input to these endpoints
 * must always get a clean 4xx with a message, never a 500 and never a
 * value that silently reaches OrderService other than what was actually
 * validated.
 */
@ExtendWith(MockitoExtension.class)
class OrderControllerAdversarialTest {

    @Mock
    private OrderService orderService;

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private AuthenticatedUserResolver authResolver;

    private MockMvc mockMvc;
    private Authentication merchantAuth;

    @BeforeEach
    void setUp() {
        OrderController controller =
                new OrderController(orderService, orderRepository, authResolver);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                // Standalone MockMvc does NOT wire up bean validation unless
                // told to — without this, @Valid on OrderRequest's new
                // @DecimalMin/@DecimalMax coordinate constraints would
                // silently never run, and this whole test class would be
                // testing nothing.
                .setValidator(new LocalValidatorFactoryBean())
                // Standalone MockMvc also does NOT auto-discover
                // @RestControllerAdvice beans — without this,
                // GlobalExceptionHandler never runs and a thrown
                // BusinessException/RuntimeException propagates out of
                // MockMvc as a raw ServletException instead of the clean
                // 4xx response the real app would return.
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        merchantAuth = new UsernamePasswordAuthenticationToken(
                "merchant@test.com", null);

        User merchant = User.builder()
                .id(1L)
                .role(User.Role.MERCHANT)
                .build();
        // lenient: not every test in this class reaches a point where the
        // controller calls authResolver.resolve (e.g. malformed-JSON and
        // tracking-location tests fail/short-circuit before that point).
        lenient().when(authResolver.resolve(any(Authentication.class)))
                .thenReturn(merchant);
    }

    private Order dummyOrder() {
        return Order.builder()
                .id(1L)
                .trackingCode("FST-TEST")
                .orderType(Order.OrderType.LOGISTICS)
                .status(Order.OrderStatus.PENDING)
                .build();
    }

    // ───────────────────────── O2O totalPrice ─────────────────────────

    @Test
    void createOrder_rejectsNegativeO2OPrice() throws Exception {
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": -5}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void createOrder_rejectsZeroO2OPrice() throws Exception {
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": 0}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError());
    }

    @Test
    void createOrder_rejectsMissingO2OPrice() throws Exception {
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque"}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError());
    }

    @Test
    void createOrder_rejectsNonNumericO2OPrice_withoutServerError() throws Exception {
        // "abc" as a bare (unquoted) JSON token is not valid JSON at all —
        // this must fail JSON parsing cleanly (400), never 500.
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": abc}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void createOrder_toleratesHugeDigitStringO2OPrice_withoutServerError() throws Exception {
        // A 1000-digit integer — BigDecimal itself has no magnitude limit,
        // but Jackson's own StreamReadConstraints (CVE-mitigation, default
        // since 2.15) caps raw JSON number-token length. Either outcome
        // (accepted as a legitimate-looking huge BigDecimal that later
        // trips PricingService.validateO2OPrice's $1000 max server-side,
        // or rejected at parse time) is fine — a 500 is not.
        String hugeDigits = "9".repeat(1000);
        String body = "{\"isO2O\": true, \"offlineCustomerPhone\": \"+96170000000\","
                + " \"offlineLandmark\": \"Near the mosque\", \"totalPrice\": "
                + hugeDigits + "}";

        when(orderService.createO2OOrder(any(), anyString(), anyString(), any(),
                any(), any(), any(), any(), any()))
                .thenReturn(dummyOrder());

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    // ───────────────────────── Coordinates ─────────────────────────

    @Test
    void createOrder_rejectsOutOfRangeLatitude() throws Exception {
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": 10,
                 "pickupLat": 200.0, "pickupLng": 35.5}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void createOrder_rejectsLatitudeThatOverflowsToInfinity() throws Exception {
        // "1e400" is a syntactically valid JSON number; parsed into a
        // Double field it silently becomes Double.POSITIVE_INFINITY
        // (double overflow) rather than failing to parse. Without a
        // range check this sails through untouched and can defeat the
        // distance cap downstream (see PricingServiceDistanceTest) —
        // @DecimalMax must catch it right here instead.
        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": 10,
                 "pickupLat": 1e400, "pickupLng": 35.5,
                 "deliveryLat": 33.9, "deliveryLng": 35.5}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void createOrder_toleratesSwappedLatLngWithoutServerError() throws Exception {
        // Both values are individually in-range for *some* axis, just
        // swapped (lng value sent as lat and vice versa) — not something
        // a range check alone can catch, but it must never crash; the
        // real PricingService distance math resolves it to a boolean,
        // never an exception, for finite inputs (see
        // PricingServiceDistanceTest.exceedsMaxDeliveryDistance_
        // handlesSwappedLatLngWithoutCrashing).
        when(orderService.createO2OOrder(any(), anyString(), anyString(), any(),
                any(), any(), any(), any(), any()))
                .thenReturn(dummyOrder());

        String body = """
                {"isO2O": true, "offlineCustomerPhone": "+96170000000",
                 "offlineLandmark": "Near the mosque", "totalPrice": 10,
                 "pickupLat": 35.5, "pickupLng": 33.8,
                 "deliveryLat": 35.8, "deliveryLng": 34.4}
                """;

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body)
                        .principal(merchantAuth))
                .andExpect(status().isOk());
    }

    @Test
    void createOrder_rejectsMalformedJsonBody_withoutServerError() throws Exception {
        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not even json")
                        .principal(merchantAuth))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    // ───────────────────────── Quote endpoint @Valid ─────────────────────────
    // Final whole-branch review, finding #6: POST /api/orders/quote took
    // OrderRequest WITHOUT @Valid, so the coordinate @DecimalMin/@DecimalMax
    // checks (wired on every other OrderRequest-based path — see the
    // "Coordinates" section above) were silently skipped here. Low impact
    // (display-only, createOrder() always recomputes for real) but still a
    // gap in validation that's supposed to be universal.

    @Test
    void quoteOrder_rejectsOutOfRangeLatitude() throws Exception {
        String body = """
                {"merchantId": 1, "pickupLat": 200.0, "pickupLng": 35.5,
                 "deliveryLat": 33.9, "deliveryLng": 35.5}
                """;

        mockMvc.perform(post("/api/orders/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));

        verifyNoInteractions(orderService);
    }

    @Test
    void quoteOrder_rejectsLatitudeThatOverflowsToInfinity() throws Exception {
        String body = """
                {"merchantId": 1, "pickupLat": 1e400, "pickupLng": 35.5,
                 "deliveryLat": 33.9, "deliveryLng": 35.5}
                """;

        mockMvc.perform(post("/api/orders/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));

        verifyNoInteractions(orderService);
    }

    @Test
    void quoteOrder_stillAcceptsValidCoordinates() throws Exception {
        when(orderService.quoteLogisticsOrder(any(), any(), any(), any(), any(), any()))
                .thenReturn(com.faster.backend.dto.OrderQuoteResponse.builder()
                        .totalPrice(java.math.BigDecimal.TEN)
                        .deliveryFee(java.math.BigDecimal.ONE)
                        .grandTotal(java.math.BigDecimal.valueOf(11))
                        .build());

        String body = """
                {"merchantId": 1, "pickupLat": 33.5, "pickupLng": 35.5,
                 "deliveryLat": 33.9, "deliveryLng": 35.5}
                """;

        mockMvc.perform(post("/api/orders/quote")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk());
    }

    // ───────────────────────── Tracking location update ─────────────────────────

    @Test
    void updateTrackingLocation_rejectsMalformedJsonBody_withoutServerError() throws Exception {
        mockMvc.perform(patch("/api/tracking/public/{code}/location", "FST-TEST")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("not json at all"))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void updateTrackingLocation_toleratesMissingKeys_withoutServerError() throws Exception {
        when(orderService.updateTrackingLocation(anyString(), any(), any()))
                .thenThrow(new com.faster.backend.exception.BusinessException(
                        "Both lat and lng are required"));

        mockMvc.perform(patch("/api/tracking/public/{code}/location", "FST-TEST")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().is4xxClientError())
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    @Test
    void updateTrackingLocation_toleratesOverflowingCoordinate_withoutServerError() throws Exception {
        // Map<String, Double> request bodies (no DTO, no @Valid) are the
        // one place OrderRequest's new range checks don't apply. This
        // test mocks OrderService entirely, so it ONLY proves the
        // controller/Jackson layer itself survives the extreme "1e400"
        // literal and passes it through to the service layer without
        // crashing — it does NOT prove anything about what OrderService
        // actually does with the value. The
        // real coordinate-validation behavior (OrderService.
        // validateCoordinates, wired into updateTrackingLocation/
        // confirmRecipientLocation/quoteDeliveryFee, plus
        // PricingService's non-finite-distance guard) is exercised with
        // the REAL OrderService in
        // OrderServiceCoordinateAndPriceValidationTest, and end-to-end
        // through this exact endpoint with the real service wired under
        // MockMvc in
        // OrderControllerRealServiceAdversarialTest#updateTrackingLocation_rejectsOverflowingCoordinate_asCleanRejection_notSilentFlag.
        when(orderService.updateTrackingLocation(anyString(), any(), any()))
                .thenReturn(dummyOrder());

        mockMvc.perform(patch("/api/tracking/public/{code}/location", "FST-TEST")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 1e400, \"lng\": 35.5}"))
                .andExpect(result ->
                        assertThat(result.getResponse().getStatus()).isLessThan(500));
    }

    // ───────────── Final whole-branch review, finding #1 ─────────────
    // OrderController used to always say "Location confirmed"/"Delivery
    // location confirmed" even when OrderService actually flagged (not
    // applied) the update — the caller had no way to know. These prove
    // the controller's response now tells the truth, by driving the
    // SAME controller method with a mocked OrderService returning an
    // Order whose isDistanceFlagged differs between cases.

    @Test
    void updateTrackingLocation_reportsHonestMessageAndFlagWhenFlagged() throws Exception {
        Order flaggedOrder = Order.builder()
                .id(1L)
                .trackingCode("FST-TEST")
                .isDistanceFlagged(true)
                .distanceFlagReason("Reported location is beyond the maximum delivery distance from pickup")
                .build();
        when(orderService.updateTrackingLocation(anyString(), any(), any()))
                .thenReturn(flaggedOrder);

        mockMvc.perform(patch("/api/tracking/public/{code}/location", "FST-TEST")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.5, \"lng\": 35.5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.distanceFlagged").value(true))
                .andExpect(jsonPath("$.message").value(
                        "We received your location, but it's outside our delivery area — our team will review it"));
    }

    @Test
    void updateTrackingLocation_reportsNormalMessageAndFlagWhenNotFlagged() throws Exception {
        when(orderService.updateTrackingLocation(anyString(), any(), any()))
                .thenReturn(dummyOrder()); // isDistanceFlagged defaults to false

        mockMvc.perform(patch("/api/tracking/public/{code}/location", "FST-TEST")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.5, \"lng\": 35.5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.distanceFlagged").value(false))
                .andExpect(jsonPath("$.message").value("Location confirmed"));
    }

    @Test
    void confirmMyLocation_reportsHonestMessageAndFlagWhenFlagged() throws Exception {
        Order flaggedOrder = Order.builder()
                .id(1L)
                .trackingCode("FST-TEST")
                .isDistanceFlagged(true)
                .distanceFlagReason("Reported location is beyond the maximum delivery distance from pickup")
                .build();
        when(orderService.confirmRecipientLocation(any(), any(), any(), any()))
                .thenReturn(flaggedOrder);

        mockMvc.perform(patch("/api/orders/{orderId}/confirm-my-location", 1L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.5, \"lng\": 35.5}")
                        .principal(merchantAuth))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.distanceFlagged").value(true))
                .andExpect(jsonPath("$.message").value(
                        "We received your location, but it's outside our delivery area — our team will review it"));
    }

    @Test
    void confirmMyLocation_reportsNormalMessageAndFlagWhenNotFlagged() throws Exception {
        when(orderService.confirmRecipientLocation(any(), any(), any(), any()))
                .thenReturn(dummyOrder());

        mockMvc.perform(patch("/api/orders/{orderId}/confirm-my-location", 1L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lat\": 33.5, \"lng\": 35.5}")
                        .principal(merchantAuth))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.distanceFlagged").value(false))
                .andExpect(jsonPath("$.message").value("Delivery location confirmed"));
    }
}
